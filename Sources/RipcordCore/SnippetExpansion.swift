import Foundation

/// Keyword expansion's settings, the main ones Raycast's Snippets settings have.
public struct SnippetExpansion: Codable, Equatable, Sendable {
  /// When a typed keyword turns into its snippet, as Raycast's Expansion Mode.
  public enum Mode: String, Codable, CaseIterable, Sendable {
    case immediately
    case afterDelimiterKeeping
    case afterDelimiterDiscarding

    public var title: String {
      switch self {
      case .immediately: "Immediately"
      case .afterDelimiterKeeping: "After Delimiter (keeping)"
      case .afterDelimiterDiscarding: "After Delimiter (discarding)"
      }
    }
  }

  public var isEnabled: Bool
  public var mode: Mode
  /// Off, a keyword expands only as a word of its own, not at the end of a longer one.
  public var expandsWithinWords: Bool
  /// Bundle IDs of apps it never runs in.
  public var disabledApps: [String]
  /// Delete Snippet asks first, as Raycast's "Show Warning Before Deleting Snippets"; on by default.
  public var showDeleteWarning: Bool

  public init(
    isEnabled: Bool = true, mode: Mode = .immediately, expandsWithinWords: Bool = false,
    disabledApps: [String] = SnippetExpansion.defaultDisabledApps, showDeleteWarning: Bool = true
  ) {
    self.isEnabled = isEnabled
    self.mode = mode
    self.expandsWithinWords = expandsWithinWords
    self.disabledApps = disabledApps
    self.showDeleteWarning = showDeleteWarning
  }

  /// Short keys in config.json, as its other settings have.
  enum CodingKeys: String, CodingKey {
    case isEnabled = "enabled"
    case mode
    case expandsWithinWords = "withinWords"
    case disabledApps
    case showDeleteWarning
  }

  /// Password managers, as Raycast starts with, so a keyword typed there is never replaced.
  public static let defaultDisabledApps = ["com.1password.1password", "com.apple.keychainaccess"]

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    mode = (try? container.decodeIfPresent(Mode.self, forKey: .mode)) ?? .immediately
    expandsWithinWords =
      try container.decodeIfPresent(Bool.self, forKey: .expandsWithinWords) ?? false
    disabledApps =
      try container.decodeIfPresent([String].self, forKey: .disabledApps)
      ?? Self.defaultDisabledApps
    showDeleteWarning = try container.decodeIfPresent(Bool.self, forKey: .showDeleteWarning) ?? true
  }
}

/// What's been typed since the caret last jumped, matched against snippets' keywords.
public struct KeywordMatcher: Sendable {
  public struct Match: Equatable, Sendable {
    public let keyword: String
    /// Characters to take back before pasting: the keyword, and a delimiter typed after it.
    public let deleting: Int
    /// What goes back after the snippet: the delimiter, when it's kept.
    public let trailing: String
  }

  private var typed: [Character] = []
  /// Longer than any keyword needs; kept in memory only.
  private static let limit = 64
  /// What ends a keyword in the After Delimiter modes. Return and Tab aren't among them: they
  /// send or move on, which a Backspace can't take back.
  private static let delimiters: Set<Character> = [" ", ".", ",", "!", "?", ":", ";"]

  public init() {}

  /// Takes one typed character; the match to expand now, if this completes one.
  public mutating func type(
    _ character: Character, keywords: [String], mode: SnippetExpansion.Mode, withinWords: Bool
  ) -> Match? {
    if character.isNewline || character == "\t" {
      reset()
      return nil
    }
    if mode != .immediately, Self.delimiters.contains(character),
      let keyword = matching(keywords, withinWords: withinWords)
    {
      reset()
      return Match(
        keyword: keyword, deleting: keyword.count + 1,
        trailing: mode == .afterDelimiterKeeping ? String(character) : "")
    }
    typed.append(character)
    if typed.count > Self.limit { typed.removeFirst(typed.count - Self.limit) }
    guard mode == .immediately, let keyword = matching(keywords, withinWords: withinWords) else {
      return nil
    }
    reset()
    return Match(keyword: keyword, deleting: keyword.count, trailing: "")
  }

  public mutating func deleteBackward() {
    _ = typed.popLast()
  }

  /// Forgets what was typed, as when the caret moves somewhere else.
  public mutating func reset() {
    typed.removeAll()
  }

  /// The longest keyword the typed text ends with, standing as a word of its own unless
  /// `withinWords`. Empty keywords and ones with spaces never match.
  private func matching(_ keywords: [String], withinWords: Bool) -> String? {
    keywords.filter { keyword in
      let characters = Array(keyword)
      guard !characters.isEmpty, !characters.contains(where: \.isWhitespace),
        typed.count >= characters.count, Array(typed.suffix(characters.count)) == characters
      else { return false }
      let before = typed.dropLast(characters.count).last
      return withinWords || before.map { !$0.isLetter && !$0.isNumber } ?? true
    }
    .max { $0.count < $1.count }
  }
}
