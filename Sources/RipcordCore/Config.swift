import Foundation

/// The user's settings. The settings window edits it and saves it back to the same JSON file.
public struct Config: Codable, Equatable, Sendable {
  public var hotkey: String
  public var launchAtLogin: Bool
  public var quicklinks: [Quicklink]
  /// Per-app and per-command settings from the Shortcuts page, by settings key.
  public var items: [String: ItemSettings]
  /// The keyboard input source (a TIS ID such as `com.apple.keylayout.ABC`) selected while the
  /// panel is open; nil leaves the input source alone.
  public var inputSource: String?
  public var snippets: [Snippet]
  public var repositories: RepositorySettings
  /// What Pick Color copies, and Color History lists first.
  public var colorFormat: ColorFormat
  /// The root search's Favorites, by item key, in the user's order.
  public var favorites: [String]
  /// Folders holding Raycast Script Commands, `~` allowed.
  public var scriptFolders: [String]
  /// Typing a snippet's keyword in any app replaces it with the snippet.
  public var snippetExpansion: SnippetExpansion
  /// Generate Dummy Text's language when its menu is left alone.
  public var dummyTextLanguage: DummyText.Language
  /// How long and how many Clipboard History keeps.
  public var clipboardHistory: ClipboardSettings
  /// The panel's backdrop shader: "off", a built-in one's name, or a file in the shaders folder.
  public var backdrop: String
  /// Using a half again on the same window goes ½ → ⅔ → ⅓, as Raycast's Cycling setting.
  public var cycleHalves: Bool
  /// Lid Awake turns itself off when the battery falls to this percent; 0 never does.
  public var lidAwakeLowBattery: Int
  /// Points between tiled windows, and between windows and the screen's edges, as Raycast's
  /// Window Gap and Screen Gap.
  public var windowGap: Int
  public var screenGap: Int
  /// What Caffeinate keeps awake, and whether it starts with Ripcord.
  public var coffee: CoffeeSettings
  public var cleanKeyboard: CleanKeyboardSettings
  /// Pick Color's message names the nearest named color too, as Raycast's "Show color name after
  /// picking".
  public var showColorName: Bool
  public var emoji: EmojiSettings
  /// HTTP Status Codes' picture beside each code.
  public var httpStatusPicture: HTTPStatusPicture
  public var notes: NotesSettings
  public var quicklinkSettings: QuicklinkSettings
  public var systemActions: SystemActionSettings
  /// Search Bookmarks' file; nil for ~/.config/ripcord/bookmarks.md.
  public var bookmarksFile: String?

  public init(
    hotkey: String, launchAtLogin: Bool = false, quicklinks: [Quicklink],
    items: [String: ItemSettings] = [:], inputSource: String? = nil, snippets: [Snippet] = [],
    repositories: RepositorySettings = RepositorySettings(), colorFormat: ColorFormat = .hex,
    favorites: [String] = [], scriptFolders: [String] = [],
    snippetExpansion: SnippetExpansion = SnippetExpansion(),
    dummyTextLanguage: DummyText.Language = .japanese,
    clipboardHistory: ClipboardSettings = ClipboardSettings(),
    backdrop: String = Backdrop.off, cycleHalves: Bool = true, lidAwakeLowBattery: Int = 10,
    windowGap: Int = 0, screenGap: Int = 0, coffee: CoffeeSettings = CoffeeSettings(),
    cleanKeyboard: CleanKeyboardSettings = CleanKeyboardSettings(), showColorName: Bool = false,
    emoji: EmojiSettings = EmojiSettings(), httpStatusPicture: HTTPStatusPicture = .none,
    notes: NotesSettings = NotesSettings(),
    quicklinkSettings: QuicklinkSettings = QuicklinkSettings(),
    systemActions: SystemActionSettings = SystemActionSettings(), bookmarksFile: String? = nil
  ) {
    self.hotkey = hotkey
    self.launchAtLogin = launchAtLogin
    self.quicklinks = quicklinks
    self.items = items
    self.inputSource = inputSource
    self.snippets = snippets
    self.repositories = repositories
    self.colorFormat = colorFormat
    self.favorites = favorites
    self.scriptFolders = scriptFolders
    self.snippetExpansion = snippetExpansion
    self.dummyTextLanguage = dummyTextLanguage
    self.clipboardHistory = clipboardHistory
    self.backdrop = backdrop
    self.cycleHalves = cycleHalves
    self.lidAwakeLowBattery = lidAwakeLowBattery
    self.windowGap = windowGap
    self.screenGap = screenGap
    self.coffee = coffee
    self.cleanKeyboard = cleanKeyboard
    self.showColorName = showColorName
    self.emoji = emoji
    self.httpStatusPicture = httpStatusPicture
    self.notes = notes
    self.quicklinkSettings = quicklinkSettings
    self.systemActions = systemActions
    self.bookmarksFile = bookmarksFile
  }

  // Files written before a key existed still load, with that key's default.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? Config.default.hotkey
    launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    quicklinks = try container.decodeIfPresent([Quicklink].self, forKey: .quicklinks) ?? []
    items = try container.decodeIfPresent([String: ItemSettings].self, forKey: .items) ?? [:]
    inputSource = try container.decodeIfPresent(String.self, forKey: .inputSource)
    snippets = try container.decodeIfPresent([Snippet].self, forKey: .snippets) ?? []
    repositories =
      try container.decodeIfPresent(RepositorySettings.self, forKey: .repositories)
      ?? RepositorySettings()
    // An unknown value (say "SwiftUI", as Settings titles it) reads as HEX rather than leaving
    // the whole file unreadable.
    colorFormat = (try? container.decodeIfPresent(ColorFormat.self, forKey: .colorFormat)) ?? .hex
    favorites = try container.decodeIfPresent([String].self, forKey: .favorites) ?? []
    scriptFolders = try container.decodeIfPresent([String].self, forKey: .scriptFolders) ?? []
    snippetExpansion =
      try container.decodeIfPresent(SnippetExpansion.self, forKey: .snippetExpansion)
      ?? SnippetExpansion()
    dummyTextLanguage =
      (try? container.decodeIfPresent(DummyText.Language.self, forKey: .dummyTextLanguage))
      ?? .japanese
    clipboardHistory =
      try container.decodeIfPresent(ClipboardSettings.self, forKey: .clipboardHistory)
      ?? ClipboardSettings()
    backdrop = try container.decodeIfPresent(String.self, forKey: .backdrop) ?? Backdrop.off
    cycleHalves = try container.decodeIfPresent(Bool.self, forKey: .cycleHalves) ?? true
    lidAwakeLowBattery =
      try container.decodeIfPresent(Int.self, forKey: .lidAwakeLowBattery) ?? 10
    windowGap = try container.decodeIfPresent(Int.self, forKey: .windowGap) ?? 0
    screenGap = try container.decodeIfPresent(Int.self, forKey: .screenGap) ?? 0
    coffee = try container.decodeIfPresent(CoffeeSettings.self, forKey: .coffee) ?? CoffeeSettings()
    cleanKeyboard =
      try container.decodeIfPresent(CleanKeyboardSettings.self, forKey: .cleanKeyboard)
      ?? CleanKeyboardSettings()
    showColorName = try container.decodeIfPresent(Bool.self, forKey: .showColorName) ?? false
    emoji = try container.decodeIfPresent(EmojiSettings.self, forKey: .emoji) ?? EmojiSettings()
    httpStatusPicture =
      (try? container.decodeIfPresent(HTTPStatusPicture.self, forKey: .httpStatusPicture)) ?? .none
    notes = try container.decodeIfPresent(NotesSettings.self, forKey: .notes) ?? NotesSettings()
    quicklinkSettings =
      try container.decodeIfPresent(QuicklinkSettings.self, forKey: .quicklinkSettings)
      ?? QuicklinkSettings()
    systemActions =
      try container.decodeIfPresent(SystemActionSettings.self, forKey: .systemActions)
      ?? SystemActionSettings()
    bookmarksFile = try container.decodeIfPresent(String.self, forKey: .bookmarksFile)
  }

  public static let `default` = Config(
    hotkey: "cmd+space",
    quicklinks: [
      Quicklink(
        name: "Google Search", url: "https://www.google.com/search?q={query}", keyword: "g"),
      Quicklink(name: "GitHub Search", url: "https://github.com/search?q={query}", keyword: "gh"),
    ])

  /// Reads `url`, writing the defaults there first when the file doesn't exist yet.
  public static func load(from url: URL) throws -> Config {
    guard FileManager.default.fileExists(atPath: url.path) else {
      try Config.default.save(to: url)
      return .default
    }
    return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    // Atomic, so a crash mid-write never leaves a half-written config behind.
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
