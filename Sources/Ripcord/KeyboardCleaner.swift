import AppKit
import Carbon.HIToolbox
import RipcordCore
import SwiftUI
import os

/// Clean Keyboard: swallows every key press, media keys included, for a while so the keyboard
/// can be wiped, with the time left over every screen. Ends on its own, early with ⌃⌥⌘↩, or from
/// the menu bar.
@MainActor
final class KeyboardCleaner {
  private var tapThread: KeyTapThread?
  /// Which run is on, so ⌃⌥⌘↩ caught by an earlier run's tap as it goes can't end this one.
  private var session = UUID()
  private var timer: Timer?
  private var overlays: [NSWindow] = []
  private let countdown = Countdown()
  private(set) var endsAt: Date?
  /// After it starts and ends, for the menu bar.
  var onChange: () -> Void = {}

  var isActive: Bool { endsAt != nil }

  enum Refusal: Error {
    /// macOS refused the tap: Accessibility is off.
    case noAccess
    /// A field or app holds secure input, so macOS would send keys past the tap.
    case secureInput
  }

  /// Starts for `seconds`, or while running, starts the time over with them.
  func start(for seconds: TimeInterval) throws(Refusal) {
    if !isActive {
      // Keys would reach that field or app anyway, while the screen says they're off.
      guard !IsSecureEventInputEnabled() else { throw .secureInput }
      let session = UUID()
      self.session = session
      let thread = KeyTapThread { [weak self] in
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            if self?.session == session { self?.stop() }
          }
        }
      }
      guard thread.startTap() else { throw .noAccess }
      tapThread = thread
      showOverlays()
      let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.tick() }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }
    endsAt = Date.now.addingTimeInterval(seconds)
    countdown.remaining = seconds
    Self.log.info("Clean Keyboard started for \(Int(seconds), privacy: .public)s")
    onChange()
  }

  func stop() {
    guard isActive else { return }
    tapThread?.stopTap()
    tapThread = nil
    timer?.invalidate()
    timer = nil
    endsAt = nil
    for overlay in overlays { overlay.orderOut(nil) }
    overlays = []
    Self.log.info("Clean Keyboard ended")
    onChange()
  }

  private func tick() {
    guard let endsAt else { return }
    let remaining = endsAt.timeIntervalSinceNow
    if remaining <= 0 { return stop() }
    countdown.remaining = remaining
    countdown.keysGetThrough = IsSecureEventInputEnabled()
  }

  private func showOverlays() {
    overlays = NSScreen.screens.map { screen in
      let window = NSWindow(
        contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.level = .screenSaver
      window.isOpaque = false
      window.backgroundColor = .clear
      window.ignoresMouseEvents = true
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      window.contentView = NSHostingView(rootView: CleanKeyboardOverlay(countdown: countdown))
      window.setFrame(screen.frame, display: true)
      window.orderFrontRegardless()
      return window
    }
  }

  /// Read with: log show --info --predicate 'subsystem == "io.github.meltin.ripcord"'
  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "io.github.meltin.ripcord",
    category: "clean-keyboard")
}

/// The event tap on a thread of its own: on the main run loop, a busy moment there would let
/// macOS switch the tap off, and keys through, until it was turned back on.
private final class KeyTapThread: Thread, @unchecked Sendable {
  // Written on the tap's thread before `ready` is signalled, read after it.
  private var tap: CFMachPort?
  private var runLoop: CFRunLoop?
  private var started = false
  private let ready = DispatchSemaphore(value: 0)
  /// Called on the tap's thread when ⌃⌥⌘↩ is pressed.
  private let onEndKeys: @Sendable () -> Void

  init(onEndKeys: @escaping @Sendable () -> Void) {
    self.onEndKeys = onEndKeys
    super.init()
    name = "Ripcord Clean Keyboard"
  }

  /// Starts the thread and its tap; false when macOS refused the tap.
  func startTap() -> Bool {
    start()
    ready.wait()
    return started
  }

  func stopTap() {
    guard let runLoop else { return }
    let tap = tap
    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
      if let tap {
        CGEvent.tapEnable(tap: tap, enable: false)
        // Gone, not just off, so no tap is left behind.
        CFMachPortInvalidate(tap)
      }
      CFRunLoopStop(CFRunLoopGetCurrent())
    }
    CFRunLoopWakeUp(runLoop)
  }

  override func main() {
    // Key downs and ups, modifier changes, and the media and brightness keys (NX_SYSDEFINED).
    let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    let mask = types.reduce(CGEventMask(1 << 14)) { $0 | CGEventMask(1 << $1.rawValue) }
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: keyTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      ready.signal()
      return
    }
    self.tap = tap
    runLoop = CFRunLoopGetCurrent()
    CFRunLoopAddSource(
      CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    started = true
    ready.signal()
    CFRunLoopRun()
  }

  /// Every key event is swallowed; ⌃⌥⌘↩ also ends it.
  fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    // macOS switches a tap off when it's slow or the user acts; back on, or keys would leak.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return nil
    }
    let held = event.flags.intersection([.maskControl, .maskAlternate, .maskCommand])
    if type == .keyDown, held == [.maskControl, .maskAlternate, .maskCommand],
      event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Return)
    {
      onEndKeys()
    }
    return nil
  }
}

/// The tap's C callback, handing each event to the thread object it was created for.
private func keyTapCallback(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  return Unmanaged<KeyTapThread>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}

/// The time left, and whether secure input lets keys through, for the overlay.
@MainActor
@Observable
final class Countdown {
  var remaining: TimeInterval = 0
  var keysGetThrough = false
}

/// A dimmed screen with the time left, as Raycast's Clean Keyboard shows it.
private struct CleanKeyboardOverlay: View {
  let countdown: Countdown

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
      VStack(spacing: 14) {
        Glyph("keyboard", pointSize: 56)
        Text("Cleaning Keyboard").font(.system(size: 28, weight: .semibold))
        Text(Coffee.format(countdown.remaining.rounded(.up)))
          .font(.system(size: 48, weight: .medium).monospacedDigit())
        if countdown.keysGetThrough {
          Text("Secure input is on in another app, so keys get through. Stop wiping.")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.yellow)
        } else {
          Text("Keys are off until then. ⌃⌥⌘↩ or the menu bar ends it now.")
            .font(.system(size: 15))
            .foregroundStyle(.white.opacity(0.75))
        }
      }
      .foregroundStyle(.white)
    }
    .ignoresSafeArea()
  }
}
