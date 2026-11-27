import AppKit
import IOKit.pwr_mgt
import RipcordCore

/// Coffee: keeps the Mac awake with power assertions, for a time or until Decaffeinate, as
/// `caffeinate` does: the display, the system and the disk, as Settings › Coffee says.
@MainActor
final class Caffeinator {
  private var assertions: [IOPMAssertionID] = []
  /// What it keeps awake; changed while on, it holds the new set at once.
  var settings = CoffeeSettings() {
    didSet {
      guard isActive, settings != oldValue else { return }
      release()
      // Never on while holding nothing.
      if !hold() { decaffeinate() }
    }
  }
  private var timer: Timer?
  private(set) var isActive = false
  /// When a timed Caffeinate ends; nil while it runs until Decaffeinate.
  private(set) var endsAt: Date?
  /// The app Caffeinate While waits on, by name; nil otherwise.
  private(set) var whileApp: String?
  private var whileObserver: NSObjectProtocol?
  /// After every change, and each second while timed, for the menu bar.
  var onChange: () -> Void = {}

  var remaining: TimeInterval? { endsAt.map { max(0, $0.timeIntervalSinceNow) } }

  /// Starts, or while running restarts the clock with the new time. False when macOS refused.
  @discardableResult
  func caffeinate(for seconds: TimeInterval?) -> Bool {
    if !isActive {
      guard hold() else { return false }
      isActive = true
    }
    endsAt = seconds.map { Date.now.addingTimeInterval($0) }
    stopWaiting()
    timer?.invalidate()
    timer = nil
    if endsAt != nil {
      let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.tick() }
      }
      // .common, so it keeps counting, and ends on time, while a menu is open.
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }
    onChange()
    return true
  }

  /// Caffeinate While: kept awake until every copy of the app `bundleID` has quit. False when
  /// it isn't running or macOS refused.
  @discardableResult
  func caffeinate(whileRunning bundleID: String) -> Bool {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
      caffeinate(for: nil)
    else { return false }
    whileApp = app.localizedName ?? bundleID
    whileObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        let left = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if left.allSatisfy(\.isTerminated) { self?.decaffeinate() }
      }
    }
    onChange()
    return true
  }

  private func stopWaiting() {
    whileObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
    whileObserver = nil
    whileApp = nil
  }

  /// Takes the assertions the settings ask for; false, holding none, when macOS refused one.
  private func hold() -> Bool {
    for type in settings.assertionTypes {
      var id = IOPMAssertionID(0)
      let created = IOPMAssertionCreateWithName(
        type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Ripcord Coffee" as CFString,
        &id)
      guard created == kIOReturnSuccess else {
        release()
        return false
      }
      assertions.append(id)
    }
    return true
  }

  private func release() {
    for assertion in assertions { IOPMAssertionRelease(assertion) }
    assertions = []
  }

  func decaffeinate() {
    release()
    isActive = false
    endsAt = nil
    stopWaiting()
    timer?.invalidate()
    timer = nil
    onChange()
  }

  private func tick() {
    if let remaining, remaining <= 0 { return decaffeinate() }
    onChange()
  }
}
