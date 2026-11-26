import AppKit
import Carbon.HIToolbox
import RipcordCore
import SwiftUI
import os

/// Clean Keyboard: swallows every key press, media keys included, for a while so the keyboard
/// can be wiped, with the time left over every screen. Ends on its own, or early with ⌃⌥⌘↩.
@MainActor
final class KeyboardCleaner {
  private var tap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var timer: Timer?
  private var overlays: [NSWindow] = []
  private let countdown = Countdown()
  private(set) var endsAt: Date?

  var isActive: Bool { endsAt != nil }

  /// Starts for `seconds`; false when macOS refused the tap (Accessibility is off).
  @discardableResult
  func start(for seconds: TimeInterval) -> Bool {
    guard !isActive else { return true }
    // Key downs and ups, modifier changes, and the media and brightness keys (NX_SYSDEFINED).
    let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    let mask = types.reduce(CGEventMask(1 << 14)) { $0 | CGEventMask(1 << $1.rawValue) }
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: keyboardCleanerTap,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    self.tap = tap
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    endsAt = Date.now.addingTimeInterval(seconds)
    countdown.remaining = seconds
    showOverlays()
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
    Self.log.info("Clean Keyboard started for \(Int(seconds), privacy: .public)s")
    return true
  }

  func stop() {
    guard isActive else { return }
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      // Gone, not just off, so no tap is left behind.
      CFMachPortInvalidate(tap)
    }
    if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    tap = nil
    runLoopSource = nil
    timer?.invalidate()
    timer = nil
    endsAt = nil
    for overlay in overlays { overlay.orderOut(nil) }
    overlays = []
    Self.log.info("Clean Keyboard ended")
  }

  private func tick() {
    guard let endsAt else { return }
    let remaining = endsAt.timeIntervalSinceNow
    if remaining <= 0 { return stop() }
    countdown.remaining = remaining
  }

  /// Handles a key event the tap caught; every one is swallowed. ⌃⌥⌘↩ ends it.
  fileprivate func handle(_ type: CGEventType, flags: CGEventFlags, keyCode: Int64) {
    // macOS turns a tap off when it's slow or the user acts; turned back on, or keys would leak.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return
    }
    if type == .keyDown,
      flags.intersection([.maskControl, .maskAlternate, .maskCommand])
        == [.maskControl, .maskAlternate, .maskCommand],
      keyCode == Int64(kVK_Return)
    {
      stop()
    }
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

/// The time left, for the overlay to show.
@MainActor
@Observable
final class Countdown {
  var remaining: TimeInterval = 0
}

/// The tap's C callback, handing each event to the cleaner it was created for.
private func keyboardCleanerTap(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let cleaner = Unmanaged<KeyboardCleaner>.fromOpaque(userInfo).takeUnretainedValue()
  let (flags, keyCode) = (event.flags, event.getIntegerValueField(.keyboardEventKeycode))
  // The tap's source is on the main run loop, so this runs on the main thread.
  MainActor.assumeIsolated { cleaner.handle(type, flags: flags, keyCode: keyCode) }
  return nil
}

/// A dimmed screen with the time left, as Raycast's Clean Keyboard shows it.
private struct CleanKeyboardOverlay: View {
  let countdown: Countdown

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
      VStack(spacing: 14) {
        Image(systemName: "keyboard").font(.system(size: 56, weight: .light))
        Text("Cleaning Keyboard").font(.system(size: 28, weight: .semibold))
        Text(Coffee.format(countdown.remaining.rounded(.up)))
          .font(.system(size: 48, weight: .medium).monospacedDigit())
        Text("Keys are off until then. ⌃⌥⌘↩ ends it now.")
          .font(.system(size: 15))
          .foregroundStyle(.white.opacity(0.75))
      }
      .foregroundStyle(.white)
    }
    .ignoresSafeArea()
  }
}
