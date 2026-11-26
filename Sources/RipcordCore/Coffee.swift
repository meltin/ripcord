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
}
