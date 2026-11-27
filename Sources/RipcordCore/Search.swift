import Foundation

/// Commands Ripcord runs itself, listed alongside apps.
public enum BuiltinCommand: CaseIterable, Sendable {
  case clipboardHistory, searchSnippets, createSnippet, exportSnippets, importSnippets
  case searchRepositories, cloneRepo, removeRepo, httpStatusCodes, settings
  case caffeinate, decaffeinate, toggleCaffeinate, caffeinateFor, caffeinateUntil
  case caffeinateWhile, caffeinateStatus
  case sleepTimer, stopSleepTimer
  case lidAwake
  case pickColor, colorHistory, colorNames, convertColor, favoriteColors, colorWheel
  case cleanKeyboard
  case searchBookmarks, addBookmark
  case createQuicklink, searchQuicklinks, importQuicklinks, exportQuicklinks
  case searchEmoji
  case ripcordNotes, createNote, searchNotes
  case generateDummyText
  case resetWindowPosition, checkForUpdates, quit

  public var title: String {
    switch self {
    case .clipboardHistory: "Clipboard History"
    case .searchSnippets: "Search Snippets"
    case .searchRepositories: "Search Repositories"
    case .cloneRepo: "Clone Repo"
    case .removeRepo: "Remove Repo"
    case .httpStatusCodes: "HTTP Status Codes"
    case .createSnippet: "Create Snippet"
    case .exportSnippets: "Export Snippets"
    case .importSnippets: "Import Snippets"
    case .settings: "Ripcord Settings"
    case .caffeinate: "Caffeinate"
    case .decaffeinate: "Decaffeinate"
    case .toggleCaffeinate: "Toggle Caffeinate"
    // Raycast's title, dots and all.
    case .caffeinateFor: "Caffeinate for ..."
    case .caffeinateUntil: "Caffeinate Until"
    case .caffeinateWhile: "Caffeinate While"
    case .caffeinateStatus: "Caffeinate Status"
    case .sleepTimer: "Sleep Timer"
    case .stopSleepTimer: "Stop Sleep Timer"
    case .lidAwake: "Lid Awake"
    case .pickColor: "Pick Color"
    case .colorHistory: "Color History"
    case .colorNames: "Color Names"
    case .convertColor: "Convert Color"
    case .favoriteColors: "Favorite Colors"
    case .colorWheel: "Color Wheel"
    case .cleanKeyboard: "Clean Keyboard"
    case .searchBookmarks: "Search Bookmarks"
    case .createQuicklink: "Create Quicklink"
    case .searchQuicklinks: "Search Quicklinks"
    case .importQuicklinks: "Import Quicklinks"
    case .exportQuicklinks: "Export Quicklinks"
    case .addBookmark: "Add Bookmark"
    case .searchEmoji: "Search Emoji & Symbols"
    case .ripcordNotes: "Ripcord Notes"
    case .createNote: "Create Note"
    case .searchNotes: "Search Notes"
    case .generateDummyText: "Generate Dummy Text"
    case .resetWindowPosition: "Reset Ripcord Window Position"
    case .checkForUpdates: "Check for Updates"
    case .quit: "Quit Ripcord"
    }
  }

  /// What its row says it belongs to.
  public var group: String {
    switch self {
    case .caffeinate, .decaffeinate, .toggleCaffeinate, .caffeinateFor, .caffeinateUntil,
      .caffeinateWhile, .caffeinateStatus:
      "Coffee"
    case .sleepTimer, .stopSleepTimer: "Sleep Timer"
    case .lidAwake: "Keep the Mac awake with the lid closed"
    case .pickColor, .colorHistory, .colorNames, .convertColor, .favoriteColors, .colorWheel:
      "Color Picker"
    case .cleanKeyboard: "Clean Keyboard"
    // Raycast's extension's name.
    case .searchRepositories, .cloneRepo, .removeRepo: "Git Repos"
    case .searchBookmarks, .addBookmark: "Bookmarks"
    case .createQuicklink, .searchQuicklinks, .importQuicklinks, .exportQuicklinks: "Quicklinks"
    case .searchEmoji: "Emoji & Symbols"
    case .ripcordNotes, .createNote, .searchNotes: "Notes"
    // So "lorem" or "jp" finds the command too; Raycast's extension is "Japanese Lorem Ipsum
    // Generator", shortened here.
    case .generateDummyText: "Lorem Ipsum Generator JP"
    default: "Ripcord"
    }
  }

  /// The key its settings are stored under. Spelled out so renaming a case never strands them.
  public var settingsKey: String {
    switch self {
    case .clipboardHistory: "command:clipboard-history"
    case .searchSnippets: "command:search-snippets"
    case .searchRepositories: "command:search-repositories"
    case .cloneRepo: "command:clone-repo"
    case .removeRepo: "command:remove-repo"
    case .httpStatusCodes: "command:http-status-codes"
    case .createSnippet: "command:create-snippet"
    case .exportSnippets: "command:export-snippets"
    case .importSnippets: "command:import-snippets"
    case .settings: "command:settings"
    case .caffeinate: "command:caffeinate"
    case .lidAwake: "command:lid-awake"
    case .decaffeinate: "command:decaffeinate"
    case .toggleCaffeinate: "command:toggle-caffeinate"
    case .caffeinateFor: "command:caffeinate-for"
    case .caffeinateUntil: "command:caffeinate-until"
    case .caffeinateWhile: "command:caffeinate-while"
    case .caffeinateStatus: "command:caffeinate-status"
    case .sleepTimer: "command:sleep-timer"
    case .stopSleepTimer: "command:stop-sleep-timer"
    case .pickColor: "command:pick-color"
    case .colorHistory: "command:color-history"
    case .colorNames: "command:color-names"
    case .convertColor: "command:convert-color"
    case .favoriteColors: "command:favorite-colors"
    case .colorWheel: "command:color-wheel"
    case .cleanKeyboard: "command:clean-keyboard"
    case .searchBookmarks: "command:search-bookmarks"
    case .createQuicklink: "command:create-quicklink"
    case .searchQuicklinks: "command:search-quicklinks"
    case .importQuicklinks: "command:import-quicklinks"
    case .exportQuicklinks: "command:export-quicklinks"
    case .addBookmark: "command:add-bookmark"
    case .searchEmoji: "command:search-emoji"
    case .ripcordNotes: "command:ripcord-notes"
    case .createNote: "command:create-note"
    case .searchNotes: "command:search-notes"
    case .generateDummyText: "command:generate-dummy-text"
    case .resetWindowPosition: "command:reset-window-position"
    case .checkForUpdates: "command:check-for-updates"
    case .quit: "command:quit"
    }
  }

  /// The menu behind the footer's left button, in Raycast's place for app-level commands.
  public static let rootMenu = [
    MenuAction(
      title: "Settings", symbol: "gearshape", shortcut: "⌘,", action: .run(.settings)),
    MenuAction(
      title: "Check for Updates…", symbol: "arrow.clockwise", shortcut: "",
      action: .run(.checkForUpdates)),
    MenuAction(title: "Quit Ripcord", symbol: "power", shortcut: "⌘Q", action: .run(.quit)),
  ]
}

/// One row of an actions menu, with its shortcut written the way macOS menus show it.
public struct MenuAction: Equatable, Sendable {
  public let title: String
  /// An SF Symbols name.
  public let symbol: String
  /// Modifiers in ⌃⌥⇧⌘ order, then the key, e.g. "⇧⌘C"; "↵" for the primary action.
  public let shortcut: String
  public let action: SearchResult.Action
  /// Drawn in red, as Raycast draws Delete Alias.
  public let isDestructive: Bool
  /// A line above it, setting it apart from the items before.
  public let startsSection: Bool

  public init(
    title: String, symbol: String, shortcut: String, action: SearchResult.Action,
    isDestructive: Bool = false, startsSection: Bool = false
  ) {
    self.title = title
    self.symbol = symbol
    self.shortcut = shortcut
    self.action = action
    self.isDestructive = isDestructive
    self.startsSection = startsSection
  }

  /// Raycast's Configure Command…, which opens `configureMenu` for the command with this key.
  public static func configure(_ settingsKey: String) -> MenuAction {
    MenuAction(
      title: "Configure Command…", symbol: "gearshape", shortcut: "⇧⌘,",
      action: .configureMenu(settingsKey))
  }

  /// What Configure Command… lists for the command with this settings key, given its settings:
  /// its settings page, then setting its hotkey and alias, then deleting those it has.
  public static func configureMenu(_ settingsKey: String, settings: ItemSettings?) -> [MenuAction] {
    let hasHotkey = settings?.hotkey != nil
    let hasAlias = !(settings?.alias ?? "").isEmpty
    let deletes: [(title: String, action: SearchResult.Action)] =
      (hasHotkey ? [("Delete Hotkey", .deleteHotkey(settingsKey))] : [])
      + (hasAlias ? [("Delete Alias", .deleteAlias(settingsKey))] : [])
    return [
      MenuAction(
        title: "Open Command Settings", symbol: "gearshape", shortcut: "",
        action: .configure(settingsKey)),
      MenuAction(
        title: hasHotkey ? "Update Hotkey…" : "Set Hotkey…", symbol: "keyboard", shortcut: "",
        action: .setHotkey(settingsKey), startsSection: true),
      MenuAction(
        title: hasAlias ? "Update Alias…" : "Set Alias…", symbol: "text.cursor",
        shortcut: "", action: .setAlias(settingsKey)),
    ]
      + deletes.enumerated().map { index, delete in
        MenuAction(
          title: delete.title, symbol: "trash", shortcut: "", action: delete.action,
          isDestructive: true, startsSection: index == 0)
      }
  }

}

public struct SearchResult: Identifiable, Equatable, Sendable {
  public enum Action: Equatable, Sendable {
    case open(URL)
    case copy(String)
    case reveal(URL)
    case run(BuiltinCommand)
    case clip(UUID, ClipAction)
    /// The snippet at this index in the config.
    case snippet(Int, SnippetAction)
    /// `confirmed` once its warning has been answered, or for one with none.
    case system(SystemAction, confirmed: Bool = false)
    /// A CleanShot X command, through its URL scheme.
    case cleanShot(CleanShotCommand)
    case window(WindowLayout)
    /// A folder opened in a chosen app, as a repository is.
    case openWith(URL, app: URL)
    /// Settings, at the page that lists the command with this settings key.
    case configure(String)
    /// The Configure Command submenu of the command with this settings key.
    case configureMenu(String)
    /// The panel's own editor for the command's hotkey or alias, as Raycast's.
    case setHotkey(String)
    case setAlias(String)
    case deleteHotkey(String)
    case deleteAlias(String)
    /// Keeps the Mac awake for this many seconds; nil until Decaffeinate.
    case caffeinate(TimeInterval?)
    /// Sleeps the Mac, or only turns its display off, after this many seconds.
    case sleepTimer(TimeInterval, displayOnly: Bool)
    /// Keeps the Mac awake with its lid closed for this many seconds; nil until turned off.
    case lidAwake(TimeInterval?)
    /// Lets the Mac sleep with its lid closed again.
    case stopLidAwake
    /// Removes the picked color with this hex from Color History.
    case deleteColor(String)
    /// Moves the repository to the Trash: once checked for work not committed or pushed, or,
    /// `force`d, as it is; asked first either way.
    case removeRepository(URL, force: Bool)
    /// Moves the repository to the Trash, once asked.
    case trashRepository(URL)
    /// Adds the color with this hex to Favorite Colors, or takes it out.
    case toggleFavoriteColor(String)
    /// Blocks the keyboard for this many seconds, to wipe it.
    case cleanKeyboard(TimeInterval)
    /// Opens Create Quicklink's form on the Quicklink at `index`, if it's still named `name`.
    case editQuicklink(index: Int, name: String)
    /// Deletes the Quicklink at `index`, if it's still named `name`: asked first, then done.
    case deleteQuicklink(index: Int, name: String, confirmed: Bool)
    /// Removes a bookmark's line from bookmarks.md, if it still holds `text`.
    case deleteBookmark(line: Int, text: String)
    /// Opens the form on the bookmark on `line`, if it still holds `text`.
    case editBookmark(line: Int, text: String)
    /// Swaps the ⌘K menu for the headings to move the bookmark under.
    case moveBookmarkMenu(line: Int, text: String)
    /// Moves the bookmark under the heading on `headingLine`, if it's still `headingTitle`.
    case moveBookmark(line: Int, text: String, headingLine: Int, headingTitle: String)
    /// An emoji as shown (in the skin tone picked), and as listed, for Frequently Used.
    case emoji(String, base: String, EmojiAction)
    /// Swaps the ⌘K menu for the skin tones of this emoji.
    case emojiSkinToneMenu(String)
    /// Remembers the skin tone (1 lightest to 5 darkest; nil for none).
    case setEmojiSkinTone(Int?)
    /// Adds the item with this key to Favorites, or takes it out.
    case toggleFavorite(String)
    /// Runs the Script Command at this path.
    case runScript(String)
    /// Reopens a form left unfinished, with what was typed.
    case openDraft(SavedDrafts.Form)
    /// Throws a form's draft away.
    case discardDraft(SavedDrafts.Form)
    /// Moves a favorite past the one shown next to it, up or down.
    case moveFavorite(String, swappingWith: String)
    /// Opens the note in this file in the notes window.
    case openNote(URL)
    /// Moves the note in this file to the Trash.
    case deleteNote(URL)
    /// Generate Dummy Text's ⌘↵: the text copied rather than pasted.
    case copyDummyText
    /// `ripcord pick`'s line at this index, handed back to the command.
    case pick(Int)
  }

  public enum SnippetAction: Equatable, Sendable {
    /// `delete` asks; `confirmDelete` deletes.
    case paste, copy, edit, duplicate, delete, confirmDelete
  }

  public enum ClipAction: Equatable, Sendable {
    case paste, copy, togglePin, delete
    /// Delete All Entries, asked first, and its confirmation; pinned items stay.
    case deleteAll, confirmDeleteAll
  }

  public enum EmojiAction: Equatable, Sendable {
    case paste, copy, pasteKeepingOpen
  }

  public enum Kind: Equatable, Sendable {
    case application, calculator, quicklink, command, text, image, file, snippet, repository
    case statusCode
    case color, bookmark, emoji, draft, script, note, line

    public var primaryAction: String {
      switch self {
      case .calculator: "Copy Answer"
      case .text, .image, .file, .snippet: "Paste to App"
      case .application, .quicklink, .command: "Open Command"
      case .repository: "Open"
      case .statusCode: "Open in Browser"
      case .color: "Copy"
      case .bookmark: "Open in Browser"
      case .emoji: "Paste"
      case .draft: "Open Draft"
      case .script: "Run Script"
      case .note: "Open Note"
      case .line: "Select"
      }
    }
  }

  /// What ⌘K lists for this row, the primary action first.
  public var actions: [MenuAction] {
    if let menu { return menu }
    let primary = MenuAction(
      title: kind.primaryAction, symbol: "return", shortcut: "↵", action: action)
    switch action {
    case .open(let url) where url.isFileURL:
      return [
        primary,
        // ⌘↵, as Raycast's; ⇧⌘F is Add to Favorites.
        MenuAction(
          title: "Show in Finder", symbol: "folder", shortcut: "⌘↵", action: .reveal(url)),
        MenuAction(
          title: "Copy Path", symbol: "doc.on.doc", shortcut: "⇧⌘C", action: .copy(url.path)),
      ] + [settingsKey.map(MenuAction.configure)].compactMap { $0 }
    case .open(let url):
      return [
        primary,
        MenuAction(
          title: "Copy URL", symbol: "doc.on.doc", shortcut: "⇧⌘C",
          action: .copy(url.absoluteString)),
      ]
    case .clip(let id, let clipAction):
      // With Copy to Clipboard as the Primary Action, copy is on ↵ and paste on ⌘↵.
      let pasteAndCopy =
        clipAction == .copy
        ? [
          MenuAction(
            title: "Copy to Clipboard", symbol: "doc.on.doc", shortcut: "↵", action: action),
          MenuAction(
            title: kind.primaryAction, symbol: "return", shortcut: "⌘↵",
            action: .clip(id, .paste)),
        ]
        : [
          primary,
          MenuAction(
            title: "Copy to Clipboard", symbol: "doc.on.doc", shortcut: "⇧⌘C",
            action: .clip(id, .copy)),
        ]
      return pasteAndCopy + [
        MenuAction(
          title: isPinned ? "Unpin" : "Pin", symbol: isPinned ? "pin.slash" : "pin",
          shortcut: "⇧⌘P", action: .clip(id, .togglePin)),
        MenuAction(title: "Delete", symbol: "trash", shortcut: "⌃X", action: .clip(id, .delete)),
        MenuAction(
          title: "Delete All Entries…", symbol: "trash", shortcut: "⇧⌘X",
          action: .clip(id, .deleteAll), isDestructive: true),
        .configure(BuiltinCommand.clipboardHistory.settingsKey),
      ]
    case .snippet(let index, _):
      return [
        primary,
        MenuAction(
          title: "Copy to Clipboard", symbol: "doc.on.doc", shortcut: "⇧⌘C",
          action: .snippet(index, .copy)),
        MenuAction(
          title: "Edit Snippet", symbol: "pencil", shortcut: "⌘E", action: .snippet(index, .edit)),
        MenuAction(
          title: "Duplicate Snippet", symbol: "plus.square.on.square", shortcut: "⌘D",
          action: .snippet(index, .duplicate)),
        MenuAction(
          title: "Create Snippet", symbol: "plus", shortcut: "⌘N", action: .run(.createSnippet)),
        MenuAction(
          title: "Delete Snippet", symbol: "trash", shortcut: "⌃X", action: .snippet(index, .delete)
        ),
        .configure(BuiltinCommand.searchSnippets.settingsKey),
      ]
    case .run(let command): return [primary, .configure(command.settingsKey)]
    case .system(let system, _): return [primary, .configure(system.settingsKey)]
    case .cleanShot(let command): return [primary, .configure(command.settingsKey)]
    case .window(let layout): return [primary, .configure(layout.settingsKey)]
    case .runScript(let path): return [primary, .configure("script:\(path)")]
    default:
      return [primary]
    }
  }

  public let id: String
  public let title: String
  public let subtitle: String
  /// Shown as a chip after the title: an alias, or a Quicklink's keyword.
  public let keyword: String?
  public let kind: Kind
  public let action: Action
  /// A clipboard image's file, drawn as the row's icon.
  public var thumbnail: URL? = nil
  /// An SF Symbols name drawn as the row's icon, as a snippet's chosen one.
  public var symbol: String? = nil
  /// A snippet's tags, shown at the end of its row.
  public var tags: [String] = []
  /// Its ⌘K actions when they depend on settings, as a repository's apps do; nil works them out
  /// from `action`.
  public var menu: [MenuAction]? = nil
  /// An app's key in the settings, for Configure Command…; commands carry theirs in `action`.
  public var settingsKey: String? = nil

  /// What its alias and hotkey are kept under: an app's or a command's settings key, or a
  /// Quicklink's row ID; nil for rows that take neither.
  public var itemKey: String? {
    if let settingsKey { return settingsKey }
    switch action {
    case .run(let command): return command.settingsKey
    case .system(let action, _): return action.settingsKey
    case .cleanShot(let command): return command.settingsKey
    case .window(let layout): return layout.settingsKey
    default: return kind == .quicklink ? id : nil
    }
  }

  /// The hotkeys in the settings by `itemKey`, for showing a row's.
  public static func hotkeys(items: [String: ItemSettings], quicklinks: [Quicklink])
    -> [String: String]
  {
    let fromItems = items.compactMapValues(\.hotkey)
    let fromLinks = quicklinks.compactMap { link in
      link.hotkey.map { (link.rowID, $0) }
    }
    return fromItems.merging(fromLinks) { first, _ in first }
  }
  public var isPinned = false
}

public struct SearchSection: Identifiable, Equatable, Sendable {
  public let title: String
  public let results: [SearchResult]
  /// The title, unless two sections can share one.
  public let id: String

  public init(title: String, results: [SearchResult], id: String? = nil) {
    self.title = title
    self.results = results
    self.id = id ?? title
  }
}

public enum Search {
  /// The start screen for an empty query; otherwise one "Results" section.
  public static func sections(
    for query: String, apps: [AppEntry], running: [AppEntry], quicklinks: [Quicklink],
    items: [String: ItemSettings] = [:], favorites: [String] = [],
    drafts: SavedDrafts = SavedDrafts(), scripts: [ScriptCommand] = [],
    lidAwake: LidAwakeStatus? = nil
  ) -> [SearchSection] {
    let links = quicklinks.filter(\.isEnabled)
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard trimmed.isEmpty else {
      // As typed: results trims it too, but a command's argument needs to see the space after
      // its title.
      let found = results(
        for: query, apps: apps, quicklinks: links, items: items, favorites: favorites,
        scripts: scripts)
      guard found.isEmpty else { return [SearchSection(title: "Results", results: found)] }
      // Like Raycast's fallback commands: hand the whole query to each Quicklink.
      let fallbacks = links.compactMap { link in
        link.url(for: trimmed).map { url in
          SearchResult(
            id: "fallback:\(link.name)", title: link.name, subtitle: url.host() ?? "",
            keyword: link.keyword, kind: .quicklink, action: .open(url))
        }
      }
      return fallbacks.isEmpty
        ? [] : [SearchSection(title: "Use “\(trimmed)” with…", results: fallbacks)]
    }
    // Favorites first, as Raycast's; what's there isn't listed again below.
    let byKey = Dictionary(
      candidates(apps: apps, quicklinks: links, items: items, scripts: scripts).compactMap {
        candidate in
        candidate.result.itemKey.map { ($0, candidate.result) }
      }, uniquingKeysWith: { first, _ in first })
    let shown = shownFavorites(favorites, among: Set(byKey.keys))
    let favored = shown.compactMap { byKey[$0] }
    // Only what Favorites shows leaves the lists below: a favorite that can't be listed there
    // (an app run from outside the folders scanned) stays where it can be seen and removed.
    let shownRunning = running.filter {
      (items[$0.settingsKey]?.isEnabled ?? true) && !shown.contains($0.settingsKey)
    }
    let decorate = { (result: SearchResult) in withFavoriteActions(result, favorites: shown) }
    // Ripcord's own commands live in the footer's root menu; typing still finds them.
    // On, Lid Awake stays at the top with the way to turn it off.
    return [lidAwakeSection(lidAwake), draftSection(drafts)].compactMap { $0 }
      + [
        SearchSection(title: "Favorites", results: favored.map(decorate)),
        // Capped so Quicklinks stay in view.
        SearchSection(
          title: "Running",
          results: shownRunning.prefix(5).map {
            decorate(result(for: $0, alias: items[$0.settingsKey]?.alias))
          }),
        SearchSection(
          title: "Quicklinks",
          results: links.compactMap(result(for:)).filter {
            !shown.contains($0.itemKey ?? "")
          }.map(decorate)),
      ].filter { !$0.results.isEmpty }
  }

  /// The favorites that can be listed, once each, in the user's order: one for an app that's
  /// gone, or a key written twice by hand, isn't shown and doesn't take a place.
  static func shownFavorites(_ favorites: [String], among listed: Set<String>) -> [String] {
    favorites.enumerated().filter { index, key in
      listed.contains(key) && favorites.firstIndex(of: key) == index
    }.map(\.element)
  }

  /// `favorites` with `key` and `other` trading places, so a move skips keys that aren't shown.
  public static func swappingFavorite(_ key: String, with other: String, in favorites: [String])
    -> [String]
  {
    favorites.map { $0 == key ? other : $0 == other ? key : $0 }
  }

  /// `favorites` with `key` added at the end, or taken out.
  public static func togglingFavorite(_ key: String, in favorites: [String]) -> [String] {
    favorites.contains(key) ? favorites.filter { $0 != key } : favorites + [key]
  }

  /// The row's ⌘K actions with Add to Favorites, or a favorite's Remove and Move, as Raycast's
  /// list them; rows that can't be one stay as they are.
  static func withFavoriteActions(_ result: SearchResult, favorites: [String]) -> SearchResult {
    guard let key = result.itemKey else { return result }
    let favorite: [MenuAction] =
      if let index = favorites.firstIndex(of: key) {
        [
          MenuAction(
            title: "Remove from Favorites", symbol: "star", shortcut: "⇧⌘F",
            action: .toggleFavorite(key), startsSection: true)
        ]
          + (index > 0
            ? [
              MenuAction(
                title: "Move Favorite Up", symbol: "chevron.up", shortcut: "⌥⌘↑",
                action: .moveFavorite(key, swappingWith: favorites[index - 1]))
            ] : [])
          + (index < favorites.count - 1
            ? [
              MenuAction(
                title: "Move Favorite Down", symbol: "chevron.down", shortcut: "⌥⌘↓",
                action: .moveFavorite(key, swappingWith: favorites[index + 1]))
            ] : [])
      } else {
        [
          MenuAction(
            title: "Add to Favorites", symbol: "star", shortcut: "⇧⌘F",
            action: .toggleFavorite(key), startsSection: true)
        ]
      }
    // Above Configure Command…, which Raycast keeps last.
    let actions = result.actions
    let configure = actions.last.flatMap { last -> MenuAction? in
      if case .configureMenu = last.action { last } else { nil }
    }
    var decorated = result
    decorated.menu =
      Array(actions.dropLast(configure == nil ? 0 : 1)) + favorite
      + [configure].compactMap { $0 }
    return decorated
  }

  /// Calculator first, then a Quicklink whose keyword starts the query, then fuzzy matches.
  /// An exactly typed alias or keyword puts its item at the top of the matches.
  public static func results(
    for query: String, apps: [AppEntry], quicklinks: [Quicklink],
    items: [String: ItemSettings] = [:], favorites: [String] = [],
    scripts: [ScriptCommand] = []
  ) -> [SearchResult] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return [] }
    let links = quicklinks.filter(\.isEnabled)

    let calculation = Calculator.evaluate(trimmed).map { value in
      let text = Calculator.format(value)
      return SearchResult(
        id: "calculator", title: text, subtitle: trimmed, keyword: nil, kind: .calculator,
        action: .copy(text))
    }

    let expanded = links.compactMap { link -> SearchResult? in
      // Keywords and aliases are stored as typed; a stray trailing space must not break them.
      guard let keyword = link.keyword?.trimmingCharacters(in: .whitespaces), !keyword.isEmpty,
        trimmed.hasPrefix(keyword + " ")
      else { return nil }
      let argument = trimmed.dropFirst(keyword.count + 1).trimmingCharacters(in: .whitespaces)
      guard !argument.isEmpty, let url = link.url(for: argument) else { return nil }
      return SearchResult(
        id: "quicklink-query:\(link.name)", title: argument, subtitle: link.name,
        keyword: keyword, kind: .quicklink, action: .open(url))
    }

    // "caffeinate 1h 30m" or "sleep timer 30m", or an alias and the time, as a Quicklink takes
    // its query.
    let caffeinateFor = typedDuration(after: .caffeinate, in: trimmed, items: items).map {
      SearchResult(
        id: "caffeinate-for", title: "Caffeinate for \(Coffee.format($0))",
        subtitle: "Coffee", keyword: nil, kind: .command, action: .caffeinate($0))
    }
    let sleepIn =
      typedDuration(after: .sleepTimer, in: trimmed, items: items).map { seconds in
        [
          SearchResult(
            id: "sleep-in", title: "Sleep in \(Coffee.format(seconds))", subtitle: "Sleep Timer",
            keyword: nil, kind: .command, action: .sleepTimer(seconds, displayOnly: false)),
          SearchResult(
            id: "display-off-in", title: "Turn Off Display in \(Coffee.format(seconds))",
            subtitle: "Sleep Timer", keyword: nil, kind: .command,
            action: .sleepTimer(seconds, displayOnly: true)),
        ]
      } ?? []

    let lidAwakeFor = typedDuration(after: .lidAwake, in: trimmed, items: items).map {
      SearchResult(
        id: "lid-awake-for", title: "Lid Awake for \(Coffee.format($0))",
        subtitle: BuiltinCommand.lidAwake.group, keyword: nil, kind: .command,
        action: .lidAwake($0))
    }

    let everything = candidates(apps: apps, quicklinks: links, items: items, scripts: scripts)
    let shown = shownFavorites(favorites, among: Set(everything.compactMap(\.result.itemKey)))
    let ranked =
      everything
      .compactMap { candidate -> (score: Int, result: SearchResult)? in
        let names = candidate.names + [candidate.alias].compactMap { $0 }
        // As Raycast, a command is found by the name of what it belongs to too ("clean" lists
        // CleanShot X's), below anything matched by its own name.
        let group =
          [.command, .script].contains(candidate.result.kind)
          ? Fuzzy.score(trimmed, in: candidate.result.subtitle).map { $0 / 2 } : nil
        let own = names.compactMap { Fuzzy.score(trimmed, in: $0) }.max()
        guard let score = [own, group].compactMap({ $0 }).max() else { return nil }
        let exactAlias =
          candidate.alias?.trimmingCharacters(in: .whitespaces)
          .caseInsensitiveCompare(trimmed) == .orderedSame
        return (
          exactAlias ? score + 10_000 : score,
          withFavoriteActions(candidate.result, favorites: shown)
        )
      }
      .sorted {
        ($0.score, -$0.result.title.count, $1.result.title)
          > ($1.score, -$1.result.title.count, $0.result.title)
      }
      .prefix(30)
      .map(\.result)

    // "clean keyboard 30s", or the usual times while none is typed yet.
    // The usual times only once the command put its title and a space in the field: the title or
    // an alias typed alone must not offer a row that turns the keyboard off on Return.
    let cleanArguments = typedArguments(
      after: .cleanKeyboard, in: String(query.drop(while: \.isWhitespace)), items: items)
    let cleanTimes: [TimeInterval] =
      cleanArguments.contains("")
      ? [15, 30, 60, 120]
      : cleanArguments.lazy.compactMap { text in
        // A number without a unit is seconds here, as the usual times are, decimals too.
        text.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
          ? Double(text) : Coffee.duration(from: text)
      }.first.map { [$0] } ?? []
    let cleanFor: [SearchResult] = cleanTimes.filter { $0 > 0 && $0 <= longestClean }.map {
      seconds in
      SearchResult(
        id: "clean-keyboard-\(Int(seconds))",
        title: "Clean Keyboard for \(Coffee.format(seconds))", subtitle: "Clean Keyboard",
        keyword: nil, kind: .command, action: .cleanKeyboard(seconds))
    }
    let timed: [SearchResult] =
      [caffeinateFor, lidAwakeFor].compactMap { $0 } + sleepIn + cleanFor
    return [calculation].compactMap { $0 } + expanded + timed
      + ranked
  }

  typealias Candidate = (names: [String], alias: String?, result: SearchResult)

  /// Every item the root search can list, enabled ones only: apps, Quicklinks, Ripcord's
  /// commands, System Actions, window layouts, and CleanShot X's commands when it's there.
  static func candidates(
    apps: [AppEntry], quicklinks links: [Quicklink], items: [String: ItemSettings],
    scripts: [ScriptCommand] = []
  ) -> [Candidate] {
    let appCandidates: [Candidate] = apps.compactMap { app in
      let settings = items[app.settingsKey] ?? ItemSettings()
      guard settings.isEnabled else { return nil }
      return (app.names, settings.alias, result(for: app, alias: settings.alias))
    }
    let linkCandidates: [Candidate] = links.compactMap { link in
      result(for: link).map { ([link.name], link.keyword, $0) }
    }
    let commandCandidates: [Candidate] = BuiltinCommand.allCases.compactMap { command in
      let settings = items[command.settingsKey] ?? ItemSettings()
      guard settings.isEnabled else { return nil }
      return ([command.title], settings.alias, result(for: command, alias: settings.alias))
    }
    // Only with CleanShot X installed: its commands would open nothing otherwise.
    let hasCleanShot = apps.contains { CleanShotCommand.isCleanShot(bundleID: $0.bundleID) }
    let cleanShotCandidates: [Candidate] = (hasCleanShot ? CleanShotCommand.allCases : [])
      .compactMap { command in
        let settings = items[command.settingsKey] ?? ItemSettings()
        guard settings.isEnabled else { return nil }
        return ([command.title], settings.alias, result(for: command, alias: settings.alias))
      }
    let systemCandidates: [Candidate] = SystemAction.allCases.compactMap { action in
      let settings = items[action.settingsKey] ?? ItemSettings()
      guard settings.isEnabled else { return nil }
      return ([action.title], settings.alias, result(for: action, alias: settings.alias))
    }
    let windowCandidates: [Candidate] = WindowLayout.allCases.compactMap { layout in
      let settings = items[layout.settingsKey] ?? ItemSettings()
      guard settings.isEnabled else { return nil }
      return ([layout.title], settings.alias, result(for: layout, alias: settings.alias))
    }
    let scriptCandidates: [Candidate] = scripts.compactMap { script in
      let settings = items[script.settingsKey] ?? ItemSettings()
      guard settings.isEnabled else { return nil }
      return (
        [script.title], settings.alias,
        SearchResult(
          id: "script:\(script.url.path)", title: script.title, subtitle: script.packageName,
          keyword: settings.alias, kind: .script, action: .runScript(script.url.path),
          symbol: script.icon, settingsKey: script.settingsKey)
      )
    }
    return appCandidates + linkCandidates + commandCandidates + systemCandidates
      + windowCandidates + cleanShotCandidates + scriptCandidates
  }

  /// The longest Clean Keyboard typed after its title: no keyboard for more than five minutes.
  /// Settings › Clean Keyboard's Default Duration can be longer.
  public static let longestClean: TimeInterval = 300

  /// The time typed after `command`'s title or alias, as in "caffeinate 1h 30m"; nil when it's
  /// switched off or what follows isn't a time.
  private static func typedDuration(
    after command: BuiltinCommand, in query: String, items: [String: ItemSettings]
  ) -> TimeInterval? {
    // Each name that starts the query in turn, so an alias that starts with the title still works.
    typedArguments(after: command, in: query, items: items).lazy.compactMap(Coffee.duration(from:))
      .first
  }

  /// What's typed after `command`'s title or alias and a space, trimmed, for each of the two
  /// that starts the query; none when the command is switched off.
  private static func typedArguments(
    after command: BuiltinCommand, in query: String, items: [String: ItemSettings]
  ) -> [String] {
    let settings = items[command.settingsKey] ?? ItemSettings()
    guard settings.isEnabled else { return [] }
    return [command.title, settings.alias]
      .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && query.lowercased().hasPrefix($0.lowercased() + " ") }
      .map { String(query.dropFirst($0.count + 1)).trimmingCharacters(in: .whitespaces) }
  }

  /// Clipboard History's list: pinned items, then the rest by the day they were last copied,
  /// newest first, each kept to items whose text contains the query. Images match "image",
  /// their file name or the text read from them.
  public static func clipboardSections(
    for query: String, history: ClipboardHistory, type: ClipType? = nil, now: Date = .now,
    calendar: Calendar = .current
  ) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let items = type.map { type in history.items.filter { type.matches($0.content) } }
    let matches = (items ?? history.items).compactMap {
      item -> (item: ClipItem, result: SearchResult)? in
      let id = "clip:\(item.id)"
      let action = SearchResult.Action.clip(
        item.id, history.settings.primaryAction == .copy ? .copy : .paste)
      switch item.content {
      case .text(let text):
        guard trimmed.isEmpty || text.localizedStandardContains(trimmed) else { return nil }
        // All of it on one line, as Raycast shows it, so a second line isn't hidden.
        let line = text.drop(while: \.isWhitespace).prefix(1000)
          .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (
          item,
          SearchResult(
            id: id, title: String(line.prefix(200)), subtitle: "", keyword: nil, kind: .text,
            action: action, isPinned: item.isPinned)
        )
      case .image(_, let width, let height):
        // A copied file goes by its name, as Raycast lists it; a pasted image by its size.
        let title = item.name ?? "Image"
        guard
          trimmed.isEmpty || "image".localizedStandardContains(trimmed)
            || title.localizedStandardContains(trimmed)
            // The text read from it, as Raycast's Text Recognition finds an image by.
            || item.recognizedText?.localizedStandardContains(trimmed) == true
        else { return nil }
        return (
          item,
          SearchResult(
            id: id, title: title, subtitle: item.name == nil ? "\(width)×\(height)" : "",
            keyword: nil, kind: .image,
            action: action, thumbnail: history.imageURL(of: item), isPinned: item.isPinned)
        )
      case .files(let paths):
        // By name, as Raycast lists a copied file, with the folder it's in beside it.
        let title = item.name ?? "\(paths.count) Files"
        guard
          trimmed.isEmpty || "file".localizedStandardContains(trimmed)
            || title.localizedStandardContains(trimmed)
            || paths.contains(where: { $0.localizedStandardContains(trimmed) })
        else { return nil }
        let folder = paths.first.map {
          tildePath((($0 as NSString).deletingLastPathComponent), home: NSHomeDirectory())
        }
        return (
          item,
          SearchResult(
            id: id, title: title, subtitle: folder ?? "", keyword: nil, kind: .file,
            action: action, thumbnail: paths.first.map { URL(fileURLWithPath: $0) },
            isPinned: item.isPinned)
        )
      }
    }
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
    func day(of item: ClipItem) -> String {
      if calendar.isDate(item.date, inSameDayAs: now) { return "Today" }
      return calendar.isDate(item.date, inSameDayAs: yesterday) ? "Yesterday" : "Earlier"
    }
    let pinned = matches.filter(\.item.isPinned).map(\.result)
    let unpinned = matches.filter { !$0.item.isPinned }
    let days = ["Today", "Yesterday", "Earlier"].map { title in
      SearchSection(
        title: title, results: unpinned.filter { day(of: $0.item) == title }.map(\.result))
    }
    return ([SearchSection(title: "Pinned", results: pinned)] + days).filter { !$0.results.isEmpty }
  }

  /// Search Snippets' list: snippets whose name, keyword or text contains the query, by name; an
  /// exactly typed keyword comes first. Snippets with no text yet are left out.
  /// `tag`, when set, keeps only the snippets carrying it.
  public static func snippetSections(
    for query: String, snippets: [Snippet], tag: String? = nil
  ) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    func title(_ snippet: Snippet) -> String {
      snippet.name.isEmpty ? "Untitled Snippet" : snippet.name
    }
    func keyword(_ snippet: Snippet) -> String? {
      snippet.keyword?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }
    let matches = snippets.enumerated().filter { _, snippet in
      !snippet.text.isEmpty && (tag.map { snippet.tags?.contains($0) == true } ?? true)
        && (trimmed.isEmpty
          || ([snippet.name, snippet.text] + [keyword(snippet)].compactMap { $0 }
            + (snippet.tags ?? []))
            .contains { $0.localizedStandardContains(trimmed) })
    }
    let sorted = matches.sorted { a, b in
      let exact = [a, b].map {
        keyword($0.element)?.caseInsensitiveCompare(trimmed) == .orderedSame
      }
      if exact[0] != exact[1] { return exact[0] }
      return title(a.element).localizedStandardCompare(title(b.element)) == .orderedAscending
    }
    let results = sorted.map { index, snippet in
      SearchResult(
        // By position: a new snippet's name is empty, and names may repeat.
        id: "snippet:\(index)", title: title(snippet),
        subtitle: "", keyword: keyword(snippet), kind: .snippet,
        action: .snippet(index, .paste), symbol: snippet.icon ?? "doc", tags: snippet.tags ?? [])
    }
    return results.isEmpty ? [] : [SearchSection(title: "Snippets", results: results)]
  }

  /// Search Repositories' list: repositories whose name or path holds the query, best first.
  /// Each opens in the app its settings give the Return pressed, or in Finder.
  /// `removing`, for Remove Repo: Return removes a repository and ⇧⌘D force-removes it, as
  /// Raycast's Remove Repo does.
  public static func repositorySections(
    for query: String, repositories: [Repository], settings: RepositorySettings,
    home: String = NSHomeDirectory(), removing: Bool = false
  ) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    // A pasted absolute path is matched in its `~` form, as the paths are.
    let pathQuery = tildePath(trimmed, home: home)
    let ranked = repositories.compactMap { repository -> (score: Int, repository: Repository)? in
      guard !trimmed.isEmpty else { return (0, repository) }
      let score = [
        Fuzzy.score(trimmed, in: repository.name),
        // From `~`, so the home folder's own path doesn't match every repository.
        tildePath(repository.url.path, home: home).localizedStandardContains(pathQuery) ? 0 : nil,
      ].compactMap { $0 }.max()
      return score.map { ($0, repository) }
    }
    .sorted {
      ($0.score, $1.repository.name.lowercased()) > ($1.score, $0.repository.name.lowercased())
    }
    let results = ranked.map(\.repository).map { repository in
      let url = repository.url
      let opens = RepositorySettings.OpenKey.allCases.compactMap { key -> MenuAction? in
        guard let app = settings.openWith[key.rawValue] else {
          return key == .plain
            ? MenuAction(
              title: "Open in Finder", symbol: "folder", shortcut: "↵", action: .open(url))
            : nil
        }
        let appURL = URL(fileURLWithPath: app)
        return MenuAction(
          title: "Open in \(appURL.deletingPathExtension().lastPathComponent)",
          symbol: "arrow.up.forward.app", shortcut: key.shortcut,
          action: .openWith(url, app: appURL))
      }
      let remote = repository.remote.map { page in
        MenuAction(
          title: page.host() == "github.com" ? "Open on GitHub" : "Open Remote", symbol: "globe",
          shortcut: "⌘O", action: .open(page))
      }
      let removals = [
        MenuAction(
          title: "Remove Repository", symbol: "trash", shortcut: "↵",
          action: .removeRepository(url, force: false), isDestructive: true),
        MenuAction(
          title: "Force Remove Repository", symbol: "trash", shortcut: "⇧⌘D",
          action: .removeRepository(url, force: true), isDestructive: true),
      ]
      let menu =
        removing
        ? removals
        : opens + [remote].compactMap { $0 } + [
          MenuAction(
            title: "Show in Finder", symbol: "folder", shortcut: "⇧⌘F", action: .reveal(url)),
          MenuAction(
            title: "Copy Path", symbol: "doc.on.doc", shortcut: "⇧⌘C", action: .copy(url.path)),
          .configure(BuiltinCommand.searchRepositories.settingsKey),
        ]
      return SearchResult(
        id: "repo:\(url.path)", title: repository.name,
        subtitle: tildePath(url.path, home: home), keyword: nil,
        kind: .repository, action: menu[0].action, menu: menu)
    }
    // Untitled: the list is all repositories, as Raycast's shows it.
    return results.isEmpty ? [] : [SearchSection(title: "", results: results)]
  }

  /// `path` with the home folder written `~`; a sibling such as /Users/alex for /Users/al is
  /// left alone.
  public static func tildePath(_ path: String, home: String) -> String {
    path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
  }

  /// Every app, Quicklink, command and system action the Shortcuts page lists, by section. Disabled
  /// items are included so they can be turned back on; an app found twice is listed once.
  public static func catalog(apps: [AppEntry], quicklinks: [Quicklink]) -> [CatalogSection] {
    let uniqueApps = Dictionary(apps.map { ($0.settingsKey, $0) }) { first, _ in first }.values
      .sorted { $0.names[0].localizedStandardCompare($1.names[0]) == .orderedAscending }
    return [
      CatalogSection(
        title: "Applications",
        entries: uniqueApps.map {
          CatalogEntry(
            target: .item($0.settingsKey), title: $0.names[0], kind: .application, appURL: $0.url)
        }),
      CatalogSection(
        title: "Quicklinks",
        entries: quicklinks.indices.map {
          CatalogEntry(
            target: .quicklink($0), title: quicklinks[$0].name, kind: .quicklink, appURL: nil)
        }),
      CatalogSection(
        title: "Ripcord",
        entries: BuiltinCommand.allCases.map {
          CatalogEntry(target: .item($0.settingsKey), title: $0.title, kind: .command, appURL: nil)
        }),
      CatalogSection(
        title: "System Actions",
        entries: SystemAction.allCases.map {
          CatalogEntry(target: .item($0.settingsKey), title: $0.title, kind: .command, appURL: nil)
        }),
      CatalogSection(
        title: "Window Management",
        entries: WindowLayout.allCases.map {
          CatalogEntry(target: .item($0.settingsKey), title: $0.title, kind: .command, appURL: nil)
        }),
      CatalogSection(
        title: "CleanShot X",
        entries: CleanShotCommand.allCases.map {
          CatalogEntry(target: .item($0.settingsKey), title: $0.title, kind: .command, appURL: nil)
        }),
    ]
  }

  private static func result(for app: AppEntry, alias: String?) -> SearchResult {
    SearchResult(
      id: app.url.path, title: app.names[0], subtitle: "", keyword: alias, kind: .application,
      action: .open(app.url), settingsKey: app.settingsKey)
  }

  private static func result(for link: Quicklink) -> SearchResult? {
    link.url(for: "").map { url in
      SearchResult(
        id: link.rowID, title: link.name, subtitle: url.host() ?? "",
        keyword: link.keyword, kind: .quicklink, action: .open(url))
    }
  }

  private static func result(for layout: WindowLayout, alias: String?) -> SearchResult {
    SearchResult(
      id: layout.settingsKey, title: layout.title, subtitle: "Window Management", keyword: alias,
      kind: .command, action: .window(layout))
  }

  private static func result(for command: CleanShotCommand, alias: String?) -> SearchResult {
    SearchResult(
      id: command.settingsKey, title: command.title, subtitle: "CleanShot X", keyword: alias,
      kind: .command, action: .cleanShot(command))
  }

  private static func result(for action: SystemAction, alias: String?) -> SearchResult {
    SearchResult(
      id: action.settingsKey, title: action.title, subtitle: "System Actions", keyword: alias,
      kind: .command, action: .system(action))
  }

  /// A command's own row, as the root search lists it.
  public static func row(for command: BuiltinCommand) -> SearchResult {
    result(for: command, alias: nil)
  }

  private static func result(for command: BuiltinCommand, alias: String?) -> SearchResult {
    // Return pastes the text into the app you were in, and ⌘↵ copies it, as Search Emoji's do.
    let menu: [MenuAction]? =
      command == .generateDummyText
      ? [
        MenuAction(
          title: "Paste Dummy Text", symbol: "return", shortcut: "↵", action: .run(command)),
        MenuAction(
          title: "Copy Dummy Text", symbol: "doc.on.doc", shortcut: "⌘↵", action: .copyDummyText),
        .configure(command.settingsKey),
      ] : nil
    return SearchResult(
      id: "command:\(command)", title: command.title, subtitle: command.group, keyword: alias,
      kind: .command, action: .run(command), menu: menu)
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
