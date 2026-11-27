import Foundation

/// One emoji or symbol for Search Emoji & Symbols, as Resources/Emoji/emoji.json lists it.
public struct Emoji: Decodable, Equatable, Sendable {
  public let character: String
  /// Its category's index in `EmojiCatalog.groups`.
  public let group: Int
  public let name: String
  public let japaneseName: String?
  public let keywords: [String]
  public let japaneseKeywords: [String]
  /// Light to dark, for an emoji with skin tones.
  public let tones: [String]?
  /// The names and keywords folded for search once, as it's read: folding on each key press
  /// slowed typing.
  let foldedNames: [String]
  let foldedKeywords: [String]

  enum CodingKeys: String, CodingKey {
    case character = "c"
    case group = "g"
    case name = "n"
    case japaneseName = "j"
    case keywords = "k"
    case japaneseKeywords = "kj"
    case tones
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    character = try values.decode(String.self, forKey: .character)
    group = try values.decode(Int.self, forKey: .group)
    name = try values.decode(String.self, forKey: .name)
    japaneseName = try values.decodeIfPresent(String.self, forKey: .japaneseName)
    keywords = try values.decodeIfPresent([String].self, forKey: .keywords) ?? []
    japaneseKeywords = try values.decodeIfPresent([String].self, forKey: .japaneseKeywords) ?? []
    tones = try values.decodeIfPresent([String].self, forKey: .tones)
    foldedNames = [name, japaneseName ?? ""].map(Search.foldedForEmoji)
    foldedKeywords = (keywords + japaneseKeywords).map(Search.foldedForEmoji)
  }

  /// The emoji in skin `tone` (1 lightest to 5 darkest), or as it is without one.
  public func character(tone: Int?) -> String {
    guard let tone, let tones, tones.indices.contains(tone - 1) else { return character }
    return tones[tone - 1]
  }

  /// Its name as Raycast shows it: "Cat Face".
  public var title: String { name.split(separator: " ").map(\.capitalized).joined(separator: " ") }

  /// Its code points in skin `tone`, as Copy Unicode copies them: "U+1F431".
  public func unicode(tone: Int?) -> String {
    character(tone: tone).unicodeScalars.map { "U+" + String($0.value, radix: 16, uppercase: true) }
      .joined(separator: " ")
  }
}

/// Every emoji and symbol, in Unicode's order, with the categories they're grouped in.
public struct EmojiCatalog: Decodable, Sendable {
  public let groups: [String]
  public let emoji: [Emoji]

  public init(data: Data) throws {
    self = try JSONDecoder().decode(Self.self, from: data)
  }
}

/// Search Emoji & Symbols' settings, as Raycast's: how many columns its grid has and what
/// Return does on an emoji.
public struct EmojiSettings: Codable, Equatable, Sendable {
  public static let columnCounts = 6...10
  public var columns: Int
  public var primaryAction: ClipboardSettings.PrimaryAction

  public init(columns: Int = 8, primaryAction: ClipboardSettings.PrimaryAction = .paste) {
    self.columns = columns
    self.primaryAction = primaryAction
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? 8
    self.init(
      columns: min(max(columns, Self.columnCounts.lowerBound), Self.columnCounts.upperBound),
      primaryAction: (try? container.decodeIfPresent(
        ClipboardSettings.PrimaryAction.self, forKey: .primaryAction)) ?? .paste)
  }
}

/// The emoji used recently, newest first, and the skin tone picked, kept in a file of their own
/// as Color History is.
public struct EmojiHistory: Sendable {
  public private(set) var recent: [String] = []
  /// 1 lightest to 5 darkest; nil for the emoji's own yellow.
  public private(set) var skinTone: Int?
  public let fileURL: URL
  /// Raycast's Frequently Used shows two rows of eight.
  public static let limit = 16

  private struct Saved: Codable {
    var recent: [String]
    var skinTone: Int?
  }

  public init(fileURL: URL) {
    self.fileURL = fileURL
    guard let data = try? Data(contentsOf: fileURL),
      let saved = try? JSONDecoder().decode(Saved.self, from: data)
    else { return }
    recent = saved.recent
    skinTone = saved.skinTone
  }

  /// Puts `character` (the emoji without a tone) first.
  public mutating func use(_ character: String) throws {
    try save(recent: Array(([character] + recent.filter { $0 != character }).prefix(Self.limit)))
  }

  public mutating func setSkinTone(_ tone: Int?) throws {
    try save(skinTone: tone.flatMap { (1...5).contains($0) ? $0 : nil }, keepTone: false)
  }

  /// Writes, and only then shows it, so the list never differs from the file.
  private mutating func save(recent: [String]? = nil, skinTone: Int? = nil, keepTone: Bool = true)
    throws
  {
    let new = Saved(recent: recent ?? self.recent, skinTone: keepTone ? self.skinTone : skinTone)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(new).write(to: fileURL, options: .atomic)
    self.recent = new.recent
    self.skinTone = new.skinTone
  }
}

extension Search {
  /// Search Emoji & Symbols: Frequently Used and then each category, or the matches for a
  /// query, best first; a query matches English and Japanese names and keywords, kana of
  /// either kind.
  /// With Copy to Clipboard as `primaryAction`, Return copies and ⌘↵ pastes.
  public static func emojiSections(
    for query: String, catalog: EmojiCatalog, history: EmojiHistory, category: Int? = nil,
    primaryAction: ClipboardSettings.PrimaryAction = .paste
  ) -> [SearchSection] {
    let wanted = catalog.emoji.filter { category == nil || $0.group == category }
    let key = foldedForEmoji(query.trimmingCharacters(in: .whitespaces))
    if !key.isEmpty {
      // Within a rank the shorter name first, as Raycast's "cat" lists "cat face" early.
      let ranked = wanted.enumerated().compactMap { index, emoji in
        emojiRank(emoji, key).map {
          (rank: $0, length: emoji.name.count, index: index, emoji: emoji)
        }
      }
      .sorted { ($0.rank, $0.length, $0.index) < ($1.rank, $1.length, $1.index) }.map(\.emoji)
      return ranked.isEmpty
        ? [] : [emojiSection("Results", ranked, history: history, primaryAction: primaryAction)]
    }
    let byCharacter = Dictionary(
      catalog.emoji.map { ($0.character, $0) }, uniquingKeysWith: { first, _ in first })
    let frequent =
      category == nil ? history.recent.compactMap { byCharacter[$0] } : []
    let groups = catalog.groups.indices.compactMap { group -> SearchSection? in
      let members = wanted.filter { $0.group == group }
      return members.isEmpty
        ? nil
        : emojiSection(
          catalog.groups[group], members, history: history, primaryAction: primaryAction)
    }
    return
      (frequent.isEmpty
      ? []
      : [emojiSection("Frequently Used", frequent, history: history, primaryAction: primaryAction)])
      + groups
  }

  /// Lower is better; nil when it doesn't match.
  private static func emojiRank(_ emoji: Emoji, _ key: String) -> Int? {
    let names = emoji.foldedNames
    let keywords = emoji.foldedKeywords
    if names.contains(key) { return 0 }
    // "cat" finds "cat face", then "grinning cat", then "bobcat".
    if names.contains(where: { $0.hasPrefix(key) }) { return 1 }
    if names.contains(where: { $0.split(separator: " ").contains { $0.hasPrefix(key) } }) {
      return 2
    }
    if keywords.contains(key) { return 3 }
    if keywords.contains(where: { $0.hasPrefix(key) }) { return 4 }
    if names.contains(where: { $0.contains(key) }) { return 5 }
    if keywords.contains(where: { $0.contains(key) }) { return 6 }
    return nil
  }

  /// Case, width and kana folded, so "ねこ" finds "ネコ" and "ＣＡＴ" finds "cat".
  static func foldedForEmoji(_ text: String) -> String {
    let wide = text.precomposedStringWithCompatibilityMapping.lowercased()
    // Hiragana ぁ…ゖ sit 0x60 below their katakana; shifting them is far quicker than ICU.
    let scalars = wide.unicodeScalars.map { scalar in
      (0x3041...0x3096).contains(scalar.value)
        ? Unicode.Scalar(scalar.value + 0x60) ?? scalar : scalar
    }
    return String(String.UnicodeScalarView(scalars))
  }

  private static func emojiSection(
    _ title: String, _ members: [Emoji], history: EmojiHistory,
    primaryAction: ClipboardSettings.PrimaryAction
  )
    -> SearchSection
  {
    let all = members.map { $0.character(tone: history.skinTone) }.joined()
    return SearchSection(
      title: title,
      results: members.map {
        emojiResult(
          $0, tone: history.skinTone, in: title, section: all, primaryAction: primaryAction)
      },
      // Frequently Used repeats emoji of the categories below, so the ID tells them apart.
      id: "emoji-section:\(title)")
  }

  private static func emojiResult(
    _ emoji: Emoji, tone: Int?, in sectionTitle: String, section: String,
    primaryAction: ClipboardSettings.PrimaryAction
  ) -> SearchResult {
    let shown = emoji.character(tone: tone)
    let paste = MenuAction(
      title: "Paste", symbol: "doc.on.doc", shortcut: primaryAction == .copy ? "⌘↵" : "↵",
      action: .emoji(shown, base: emoji.character, .paste))
    let copy = MenuAction(
      title: "Copy to Clipboard", symbol: "doc.on.doc",
      shortcut: primaryAction == .copy ? "↵" : "⌘↵",
      action: .emoji(shown, base: emoji.character, .copy))
    var menu =
      (primaryAction == .copy ? [copy, paste] : [paste, copy]) + [
        MenuAction(
          title: "Paste and Keep Window Open", symbol: "doc.on.doc", shortcut: "⌥↵",
          action: .emoji(shown, base: emoji.character, .pasteKeepingOpen)),
        MenuAction(
          title: "Copy Unicode", symbol: "doc.on.doc", shortcut: "⌥⇧⌘C",
          action: .copy(emoji.unicode(tone: tone)), startsSection: true),
        MenuAction(
          title: "Copy All Emojis from Section", symbol: "doc.on.doc", shortcut: "⌃⌘C",
          action: .copy(section)),
      ]
    if emoji.tones != nil {
      menu.append(
        MenuAction(
          title: "Change Skin Tone…", symbol: "hand.wave", shortcut: "⇧⌘S",
          action: .emojiSkinToneMenu(emoji.character), startsSection: true))
    }
    return SearchResult(
      // With the section: Frequently Used lists emoji again.
      id: "emoji:\(sectionTitle):\(emoji.character)", title: emoji.title, subtitle: shown,
      keyword: nil,
      kind: .emoji, action: menu[0].action, menu: menu)
  }

  /// Change Skin Tone's list, each tone shown on `character`.
  public static func skinToneMenu(for character: String, catalog: EmojiCatalog) -> [MenuAction] {
    guard let emoji = catalog.emoji.first(where: { $0.character == character }) else { return [] }
    let names = ["Default", "Light", "Medium-Light", "Medium", "Medium-Dark", "Dark"]
    return names.indices.map { tone in
      MenuAction(
        title: "\(emoji.character(tone: tone == 0 ? nil : tone))  \(names[tone])",
        symbol: "hand.wave", shortcut: "", action: .setEmojiSkinTone(tone == 0 ? nil : tone))
    }
  }
}
