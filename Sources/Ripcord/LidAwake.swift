import AppKit
import IOKit.ps
import RipcordCore
import os

/// Lid Awake: keeps the Mac awake with its lid closed, on battery too, as Capsomnia does. macOS
/// sleeps a closed Mac on battery whatever an app asks, unless `pmset -a disablesleep 1` is set,
/// which takes root; a sudoers rule installed once lets Ripcord run exactly that, and its `0`,
/// without a password, so turning it off works unattended when its time is up or the battery
/// runs low.
@MainActor
final class LidAwake {
  /// After every change, and each second while on, for the menu bar and the panel.
  var onChange: () -> Void = {}
  /// When it couldn't turn itself off, as sleep then stays disabled.
  var onError: (String) -> Void = { _ in }
  /// Below this percent on battery it turns itself off; 0 never does.
  var lowBattery = 10

  private(set) var isActive = false
  /// When it turns itself off; nil while it stays on until turned off.
  private(set) var endsAt: Date?
  private var timer: Timer?

  var status: LidAwakeStatus? { isActive ? LidAwakeStatus(endsAt: endsAt) : nil }
  var remaining: TimeInterval? { endsAt.map { max(0, $0.timeIntervalSinceNow) } }

  nonisolated static let rulePath = "/etc/sudoers.d/ripcord-lid-awake"
  nonisolated private static let pmset = "/usr/bin/pmset"
  /// Left while on, so a crash or a force quit is put right at the next launch.
  private static let marker = URL.applicationSupportDirectory.appending(
    path: "Ripcord/lid-awake-on")

  init() {
    // On at a crash: sleep is still disabled, so let the Mac sleep again.
    if FileManager.default.fileExists(atPath: Self.marker.path) {
      _ = Self.setSleepDisabled(false)
      try? FileManager.default.removeItem(at: Self.marker)
    }
  }

  /// Whether Ripcord's own rule is installed, which Remove… takes out.
  nonisolated static var hasRule: Bool { FileManager.default.fileExists(atPath: rulePath) }

  /// Whether some sudoers rule lets Ripcord run pmset without a password.
  nonisolated static var isAllowed: Bool {
    run("/usr/bin/sudo", ["-n", "-l", pmset, "-a", "disablesleep", "1"]) == 0
  }

  /// Turns it on, for `seconds` or until turned off; why it couldn't otherwise.
  func start(for seconds: TimeInterval?) -> String? {
    guard Self.isAllowed else {
      return
        "Lid Awake needs a one-time administrator password. Allow it under Settings › Lid Awake."
    }
    if let level = Self.battery(), level.isLow(below: lowBattery) {
      return
        "The battery is at \(level.percent)%, at or below Lid Awake's limit of \(lowBattery)%."
    }
    guard Self.setSleepDisabled(true) else { return "macOS didn't let Ripcord disable sleep." }
    try? FileManager.default.createDirectory(
      at: Self.marker.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: Self.marker.path, contents: nil)
    isActive = true
    endsAt = seconds.map { Date.now.addingTimeInterval($0) }
    if timer == nil {
      let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.tick() }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }
    Self.log.info("Lid Awake on for \(seconds.map { "\(Int($0))s" } ?? "ever", privacy: .public)")
    onChange()
    return nil
  }

  /// Lets the Mac sleep again. When pmset refuses, it stays on, its marker kept for the next
  /// launch, and says so: sleep would otherwise stay disabled with nothing showing it.
  func stop() {
    guard isActive else { return }
    guard Self.setSleepDisabled(false) else {
      Self.log.error("Lid Awake couldn't enable sleep again")
      return onError(
        "Lid Awake couldn't let the Mac sleep again. Run “sudo pmset -a disablesleep 0” in Terminal."
      )
    }
    timer?.invalidate()
    timer = nil
    isActive = false
    endsAt = nil
    try? FileManager.default.removeItem(at: Self.marker)
    Self.log.info("Lid Awake off")
    onChange()
  }

  private func tick() {
    if let remaining, remaining <= 0 { return stop() }
    if let level = Self.battery(), level.isLow(below: lowBattery) {
      Self.log.info("Lid Awake off at \(level.percent, privacy: .public)% battery")
      return stop()
    }
    onChange()
  }

  /// Asks for the administrator password once and installs the rule. Written, checked with
  /// visudo and installed all as root, in a file only root can change, so nothing running as the
  /// user can swap in a rule of its own between the check and the install.
  nonisolated static func allow() -> Bool {
    let user = NSUserName()
    // Only a plain short name goes into a sudoers line.
    guard !user.isEmpty,
      user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) })
    else { return false }
    let rule = "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
    let command =
      "umask 077; f=$(/usr/bin/mktemp /tmp/ripcord-lid-awake.XXXXXX) || exit 1; "
      + "/usr/bin/printf '%s\\n' '# Ripcord Lid Awake' '\(rule)' > \"$f\" "
      + "&& /usr/sbin/visudo -c -f \"$f\" "
      + "&& /usr/bin/install -m 0440 -o root -g wheel \"$f\" \(rulePath); r=$?; /bin/rm -f \"$f\"; exit $r"
    return administrator(
      command, prompt: "Ripcord Lid Awake needs to run pmset's disablesleep without a password.")
  }

  /// Takes the rule out again, with the administrator password, letting the Mac sleep first, as
  /// nothing could turn Lid Awake off once the rule is gone.
  nonisolated static func disallow() -> Bool {
    administrator(
      "\(pmset) -a disablesleep 0; /bin/rm -f \(rulePath)",
      prompt: "Ripcord will remove Lid Awake's permission.")
  }

  nonisolated private static func setSleepDisabled(_ disabled: Bool) -> Bool {
    run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"]) == 0
  }

  /// The internal battery's charge and whether it's in use; nil on a Mac without one.
  nonisolated private static func battery() -> BatteryLevel? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
        let current = description[kIOPSCurrentCapacityKey] as? Int,
        let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
      else { continue }
      let state = description[kIOPSPowerSourceStateKey] as? String
      return BatteryLevel(
        percent: current * 100 / maximum, onBattery: state == kIOPSBatteryPowerValue)
    }
    return nil
  }

  /// Runs `command` as root through macOS's own password prompt.
  nonisolated private static func administrator(_ command: String, prompt: String) -> Bool {
    // AppleScript's string literal: its backslashes and quotes escaped.
    func quoted(_ text: String) -> String {
      "\""
        + text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    let script =
      "do shell script \(quoted(command)) with prompt \(quoted(prompt)) with administrator privileges"
    return run("/usr/bin/osascript", ["-e", script]) == 0
  }

  @discardableResult
  nonisolated private static func run(_ path: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus
    } catch {
      return -1
    }
  }

  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "io.github.meltin.ripcord", category: "lid-awake")
}
