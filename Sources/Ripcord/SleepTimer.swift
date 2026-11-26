import AppKit
import os

/// Sleep Timer: sleeps the Mac, or only turns its display off, when the time is up.
@MainActor
final class SleepTimer {
  private var timer: Timer?
  /// When it fires; nil while none is set.
  private(set) var endsAt: Date?
  private(set) var displayOnly = false
  /// After every change, and each second while set, for the menu bar.
  var onChange: () -> Void = {}
  /// When the time is up, with whether only the display should go off.
  var onFire: (_ displayOnly: Bool) -> Void = { _ in }

  init() {
    // Asleep already: a timer left running would put the Mac back to sleep, or its display off,
    // the moment it wakes, as its time passed meanwhile.
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.stop() }
    }
  }

  var isActive: Bool { endsAt != nil }
  var remaining: TimeInterval? { endsAt.map { max(0, $0.timeIntervalSinceNow) } }

  /// Starts, or replaces the one set.
  func start(after seconds: TimeInterval, displayOnly: Bool) {
    timer?.invalidate()
    endsAt = Date.now.addingTimeInterval(seconds)
    self.displayOnly = displayOnly
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    // .common, so it counts down, and fires on time, while a menu is open.
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
    Self.log.info(
      "Sleep timer set for \(Int(seconds), privacy: .public)s, display only: \(displayOnly, privacy: .public)"
    )
    onChange()
  }

  func stop() {
    guard isActive else { return }
    timer?.invalidate()
    timer = nil
    endsAt = nil
    Self.log.info("Sleep timer stopped")
    onChange()
  }

  private func tick() {
    guard let remaining, remaining <= 0 else { return onChange() }
    let displayOnly = displayOnly
    stop()
    Self.log.info("Sleep timer fired, display only: \(displayOnly, privacy: .public)")
    onFire(displayOnly)
  }

  /// Read with: log show --predicate 'subsystem == "io.github.meltin.ripcord"'
  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "io.github.meltin.ripcord", category: "sleep-timer")
}
