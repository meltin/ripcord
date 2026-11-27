import Foundation

/// Clipboard History's settings, as Raycast's: how long and how many it keeps, the apps whose
/// copies it never records, and what Return does on an entry.
public struct ClipboardSettings: Codable, Equatable, Sendable {
  /// What Return does on an entry; the other one is on ⌘↵.
  public enum PrimaryAction: String, Codable, CaseIterable, Sendable {
    case paste, copy

    public var title: String {
      switch self {
      case .paste: "Paste to Active App"
      case .copy: "Copy to Clipboard"
      }
    }
  }

  /// How Text Recognition reads images, as Raycast's Recognition Mode.
  public enum RecognitionMode: String, Codable, CaseIterable, Sendable {
    case fast, accurate

    public var title: String {
      switch self {
      case .fast: "Fast"
      case .accurate: "Accurate"
      }
    }
  }

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

  /// Unlimited, as the largest count: a build from before it reads it as keeping everything too,
  /// where 0 would have kept one.
  public static let unlimitedEntries = Int.max
  /// The most unpinned entries kept, newest first.
  public static let entryCounts = [100, 300, 1_000, 3_000, unlimitedEntries]
  /// Raycast's: Passwords and Keychain Access.
  public static let defaultDisabledApps = ["com.apple.Passwords", "com.apple.keychainaccess"]

  public var keepFor: Retention
  public var maxEntries: Int
  /// Bundle IDs of the apps whose copies aren't recorded.
  public var disabledApps: [String]
  public var primaryAction: PrimaryAction
  /// Whether pasting or copying an entry moves it to the top, as Raycast's "Update history
  /// after action".
  public var updateAfterAction: Bool
  /// Whether a paste puts only the text, leaving out the formatting it was copied with, as
  /// Raycast's "Prefer pasting as plain text"; Copy to Clipboard keeps it either way.
  public var preferPlainText: Bool
  /// Whether links' favicons and social images are fetched and shown, in Clipboard History and
  /// for Quicklinks, as Raycast's "Show visual information for links".
  public var showLinkPreviews: Bool
  /// Whether text in copied images is read, so a search finds them by it.
  public var textRecognition: Bool
  public var recognitionMode: RecognitionMode

  /// Unlimited by age, as before this setting: none of what was kept goes until asked.
  public init(
    keepFor: Retention = .unlimited, maxEntries: Int = 300,
    disabledApps: [String] = defaultDisabledApps, primaryAction: PrimaryAction = .paste,
    updateAfterAction: Bool = true, preferPlainText: Bool = true, showLinkPreviews: Bool = true,
    textRecognition: Bool = true,
    recognitionMode: RecognitionMode = .fast
  ) {
    self.keepFor = keepFor
    self.maxEntries = maxEntries
    self.disabledApps = disabledApps
    self.primaryAction = primaryAction
    self.updateAfterAction = updateAfterAction
    self.preferPlainText = preferPlainText
    self.showLinkPreviews = showLinkPreviews
    self.textRecognition = textRecognition
    self.recognitionMode = recognitionMode
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keepFor = (try? container.decodeIfPresent(Retention.self, forKey: .keepFor)) ?? .unlimited
    maxEntries = max(1, try container.decodeIfPresent(Int.self, forKey: .maxEntries) ?? 300)
    disabledApps =
      try container.decodeIfPresent([String].self, forKey: .disabledApps)
      ?? Self.defaultDisabledApps
    primaryAction =
      (try? container.decodeIfPresent(PrimaryAction.self, forKey: .primaryAction)) ?? .paste
    updateAfterAction =
      try container.decodeIfPresent(Bool.self, forKey: .updateAfterAction) ?? true
    preferPlainText = try container.decodeIfPresent(Bool.self, forKey: .preferPlainText) ?? true
    showLinkPreviews =
      try container.decodeIfPresent(Bool.self, forKey: .showLinkPreviews) ?? true
    textRecognition = try container.decodeIfPresent(Bool.self, forKey: .textRecognition) ?? true
    recognitionMode =
      (try? container.decodeIfPresent(RecognitionMode.self, forKey: .recognitionMode)) ?? .fast
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
  public static func isLink(_ text: String) -> Bool {
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
