import Foundation

/// How long Clipboard History keeps entries and how many, as Raycast's "Keep history for".
public struct ClipboardSettings: Codable, Equatable, Sendable {
  public enum Retention: String, Codable, CaseIterable, Sendable {
    case day, week, month, threeMonths, sixMonths, year, unlimited

    public var title: String {
      switch self {
      case .day: "1 Day"
      case .week: "1 Week"
      case .month: "1 Month"
      case .threeMonths: "3 Months"
      case .sixMonths: "6 Months"
      case .year: "1 Year"
      case .unlimited: "Unlimited"
      }
    }

    /// The oldest last-copied date kept at `now`; nil keeps every age.
    public func cutoff(at now: Date, calendar: Calendar = .current) -> Date? {
      let span: (Calendar.Component, Int)? =
        switch self {
        case .day: (.day, 1)
        case .week: (.day, 7)
        case .month: (.month, 1)
        case .threeMonths: (.month, 3)
        case .sixMonths: (.month, 6)
        case .year: (.year, 1)
        case .unlimited: nil
        }
      return span.flatMap { calendar.date(byAdding: $0.0, value: -$0.1, to: now) }
    }
  }

  /// The most unpinned entries kept, newest first.
  public static let entryCounts = [100, 300, 1_000, 3_000]

  public var keepFor: Retention
  public var maxEntries: Int

  /// Unlimited by age, as before this setting: none of what was kept goes until asked.
  public init(keepFor: Retention = .unlimited, maxEntries: Int = 300) {
    self.keepFor = keepFor
    self.maxEntries = maxEntries
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keepFor = (try? container.decodeIfPresent(Retention.self, forKey: .keepFor)) ?? .unlimited
    maxEntries = max(1, try container.decodeIfPresent(Int.self, forKey: .maxEntries) ?? 300)
  }
}

/// Clipboard History's type filter, as Raycast's: text, images, files, and text that's a link,
/// an email address or a color.
public enum ClipType: String, CaseIterable, Sendable {
  case text, images, files, links, emails, colors

  public var title: String {
    switch self {
    case .text: "Text"
    case .images: "Images"
    case .files: "Files"
    case .links: "Links"
    case .emails: "Emails"
    case .colors: "Colors"
    }
  }

  public func matches(_ content: ClipItem.Content) -> Bool {
    switch (self, content) {
    case (.text, .text), (.images, .image), (.files, .files): true
    case (.links, .text(let text)): Self.isLink(text)
    case (.emails, .text(let text)): Self.isEmail(text)
    case (.colors, .text(let text)): Self.isColor(text)
    default: false
    }
  }

  /// One web address, nothing around it.
  static func isLink(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil
    else { return false }
    return true
  }

  static func isEmail(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
  }

  /// A hex color, or one written as CSS rgb(), rgba(), hsl() or hsla().
  static func isColor(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let hex = trimmed.wholeMatch(of: /#([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})/)
    let css = trimmed.wholeMatch(of: /(rgb|rgba|hsl|hsla)\([^)]*\)/)
    return hex != nil || css != nil
  }
}
