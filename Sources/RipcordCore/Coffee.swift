import Foundation

/// Coffee's durations: what's typed after Caffeinate, and how the time left is shown.
public enum Coffee {
  /// Seconds for `1h 30m`, `90m`, `1h30m`, `45s` or `1.5h`; a bare number is minutes. Nil for
  /// anything else, or for no time at all.
  public static func duration(from text: String) -> TimeInterval? {
    let compact = text.lowercased().filter { !$0.isWhitespace }
    guard !compact.isEmpty else { return nil }
    if let minutes = Double(compact) { return minutes > 0 ? minutes * 60 : nil }
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
    guard number.isEmpty, total > 0 else { return nil }
    return total
  }

  /// `1h 30m`, `45m` or `30s`, as Raycast's Coffee shows the time.
  public static func format(_ seconds: TimeInterval) -> String {
    let whole = Int(seconds.rounded(.up))
    let (hours, minutes, rest) = (whole / 3600, whole % 3600 / 60, whole % 60)
    guard hours > 0 || minutes > 0 else { return "\(rest)s" }
    return [hours > 0 ? "\(hours)h" : nil, minutes > 0 ? "\(minutes)m" : nil]
      .compactMap { $0 }.joined(separator: " ")
  }
}
