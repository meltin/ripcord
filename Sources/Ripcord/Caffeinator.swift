import Foundation
import IOKit.pwr_mgt

/// Coffee: keeps the Mac and its display awake with a power assertion, for a time or until
/// Decaffeinate, as `caffeinate -d` does.
@MainActor
final class Caffeinator {
  private var assertion = IOPMAssertionID(0)
  private var timer: Timer?
  private(set) var isActive = false
  /// When a timed Caffeinate ends; nil while it runs until Decaffeinate.
  private(set) var endsAt: Date?
  /// After every change, and each second while timed, for the menu bar.
  var onChange: () -> Void = {}

  var remaining: TimeInterval? { endsAt.map { max(0, $0.timeIntervalSinceNow) } }

  /// Starts, or while running restarts the clock with the new time. False when macOS refused.
  @discardableResult
  func caffeinate(for seconds: TimeInterval?) -> Bool {
    if !isActive {
      let created = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Ripcord Coffee" as CFString, &assertion)
      guard created == kIOReturnSuccess else { return false }
      isActive = true
    }
    endsAt = seconds.map { Date.now.addingTimeInterval($0) }
    timer?.invalidate()
    timer =
      endsAt == nil
      ? nil
      : Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.tick() }
      }
    onChange()
    return true
  }

  func decaffeinate() {
    if isActive { IOPMAssertionRelease(assertion) }
    isActive = false
    endsAt = nil
    timer?.invalidate()
    timer = nil
    onChange()
  }

  private func tick() {
    if let remaining, remaining <= 0 { return decaffeinate() }
    onChange()
  }
}
