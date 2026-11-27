import Foundation

/// Coffee's durations: what's typed after Caffeinate, and how the time left is shown.
public enum Coffee {
  /// The longest time taken: a week, well past any real use, and far inside what `format` and
  /// the timer can count.
  public static let longest: TimeInterval = 7 * 24 * 3600

  /// Seconds for `1h 30m`, `90m`, `1h30m`, `45s` or `1.5h`; a bare number is minutes. Nil for
  /// anything else, for no time at all, or for more than `longest`.
  public static func duration(from text: String) -> TimeInterval? {
    let compact = text.lowercased().filter { !$0.isWhitespace }
    // Digits, points and units only: Double alone would take "inf", "1e20" and "0x10".
    guard !compact.isEmpty,
      compact.allSatisfy({ $0.isASCII && ($0.isNumber || ".hms".contains($0)) })
    else { return nil }
    if let minutes = Double(compact) {
      return minutes > 0 && minutes * 60 <= longest ? minutes * 60 : nil
    }
    var total: TimeInterval = 0
    var number = ""
    for character in compact {
      if character.isNumber || character == "." {
        number.append(character)
        continue
      }
      let unit: TimeInterval? =
        switch character {
        case "h": 3600
        case "m": 60
        case "s": 1
        default: nil
        }
      guard let unit, let value = Double(number) else { return nil }
      total += value * unit
      number = ""
    }
    // A number left without its unit, as in "1h 30".
    guard number.isEmpty, total > 0, total <= longest else { return nil }
    return total
  }

  /// `1h 30m`, `1m 30s` or `30s`, as Raycast's Coffee shows the time. `seconds: false` leaves
  /// them out from a minute up, for a countdown that needn't tick every second.
  public static func format(_ time: TimeInterval, seconds showsSeconds: Bool = true) -> String {
    let whole = Int(min(max(time, 0), longest).rounded(.up))
    let (hours, minutes, rest) = (whole / 3600, whole % 3600 / 60, whole % 60)
    let parts = [
      hours > 0 ? "\(hours)h" : nil,
      minutes > 0 ? "\(minutes)m" : nil,
      rest > 0 && (showsSeconds || whole < 60) ? "\(rest)s" : nil,
    ].compactMap { $0 }
    return parts.isEmpty ? "0s" : parts.joined(separator: " ")
  }

  /// Seconds for Caffeinate For's hours, minutes and seconds fields, an empty one counting as 0;
  /// nil for anything but whole numbers, for no time at all, or for more than `longest`.
  public static func duration(hours: String, minutes: String, seconds: String) -> TimeInterval? {
    var total: TimeInterval = 0
    for (text, unit) in [(hours, 3600.0), (minutes, 60.0), (seconds, 1.0)] {
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty { continue }
      guard let value = UInt(trimmed) else { return nil }
      total += Double(value) * unit
    }
    return total > 0 && total <= longest ? total : nil
  }

  /// Seconds from `now` to a time of day typed as `5pm`, `5:30 pm`, `17:30` or `5`, read as
  /// Raycast's Caffeinate Until reads it: with am or pm, past 12 or with a leading 0 it's that
  /// time today or tomorrow; a bare `5` is whichever of 5:00 and 17:00 comes next. Nil for
  /// anything else.
  public static func until(_ text: String, now: Date, calendar: Calendar = .current)
    -> TimeInterval?
  {
    guard
      let match = text.trimmingCharacters(in: .whitespaces).lowercased()
        .wholeMatch(of: /(\d{1,2})(?::(\d\d))? *(am|pm)?/),
      var hour = Int(match.1), let minute = Int(match.2 ?? "0")
    else { return nil }
    if match.3 == "pm", hour < 12 { hour += 12 }
    if match.3 == "am", hour == 12 { hour = 0 }
    guard hour <= 24, minute <= 59,
      var target = calendar.date(
        byAdding: DateComponents(hour: hour, minute: minute), to: calendar.startOfDay(for: now))
    else { return nil }
    let step = match.3 != nil || hour > 12 || match.1.hasPrefix("0") ? 24 : 12
    while target <= now {
      guard let next = calendar.date(byAdding: .hour, value: step, to: target) else { return nil }
      target = next
    }
    return target.timeIntervalSince(now)
  }

  /// What Caffeinate Status says: whether the Mac is kept awake, and until when.
  public static func status(
    isActive: Bool, remaining: TimeInterval?, whileApp: String?
  ) -> String {
    guard isActive else { return "Not caffeinated" }
    if let whileApp { return "Caffeinated while \(whileApp) is running" }
    if let remaining { return "Caffeinated for \(format(remaining, seconds: false)) more" }
    return "Caffeinated until Decaffeinate"
  }

  /// The argument fields of Coffee's commands that take them, as Raycast's Coffee has them.
  /// `runningApps` fill Caffeinate While's menu.
  public static func arguments(runningApps: [(title: String, value: String)])
    -> [BuiltinCommand: [ScriptCommand.Argument]]
  {
    [
      .caffeinateFor: ["Hours", "Minutes", "Seconds"].map {
        ScriptCommand.Argument(type: .text, placeholder: $0, optional: true)
      },
      .caffeinateUntil: [
        ScriptCommand.Argument(type: .text, placeholder: "Time (e.g. 5pm)", optional: true)
      ],
      .caffeinateWhile: [
        ScriptCommand.Argument(
          type: .dropdown, placeholder: "Select App",
          data: runningApps.map { .init(title: $0.title, value: $0.value) })
      ],
    ]
  }
}

/// Coffee's settings, as Raycast's Coffee has them: what Caffeinate keeps awake, and whether
/// it starts with Ripcord.
public struct CoffeeSettings: Codable, Equatable, Sendable {
  public var preventDisplay: Bool
  public var preventSystem: Bool
  public var preventDisk: Bool
  /// The system kept awake on AC power even with the lid closed, as `caffeinate -s`.
  public var preventSleepOnAC: Bool
  public var startOnLaunch: Bool

  public init(
    preventDisplay: Bool = true, preventSystem: Bool = true, preventDisk: Bool = true,
    preventSleepOnAC: Bool = false, startOnLaunch: Bool = false
  ) {
    self.preventDisplay = preventDisplay
    self.preventSystem = preventSystem
    self.preventDisk = preventDisk
    self.preventSleepOnAC = preventSleepOnAC
    self.startOnLaunch = startOnLaunch
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let read = { (key: CodingKeys, fallback: Bool) in
      try container.decodeIfPresent(Bool.self, forKey: key) ?? fallback
    }
    self.init(
      preventDisplay: try read(.preventDisplay, true),
      preventSystem: try read(.preventSystem, true),
      preventDisk: try read(.preventDisk, true),
      preventSleepOnAC: try read(.preventSleepOnAC, false),
      startOnLaunch: try read(.startOnLaunch, false))
  }

  /// The power assertions Caffeinate holds, by IOKit's names. With none picked, idle system
  /// sleep is held off, as `caffeinate` with no flags does, which Raycast's Coffee then runs.
  public var assertionTypes: [String] {
    let types = [
      preventDisplay ? "PreventUserIdleDisplaySleep" : nil,
      preventSystem ? "PreventUserIdleSystemSleep" : nil,
      preventDisk ? "PreventDiskIdle" : nil,
      preventSleepOnAC ? "PreventSystemSleep" : nil,
    ].compactMap { $0 }
    return types.isEmpty ? ["PreventUserIdleSystemSleep"] : types
  }
}
