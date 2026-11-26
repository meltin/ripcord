import Foundation

/// Commands Ripcord runs itself, listed alongside apps.
public enum BuiltinCommand: CaseIterable, Sendable {
  case clipboardHistory, searchSnippets, createSnippet, exportSnippets, importSnippets
  case searchRepositories, settings
  case resetWindowPosition, quit

  public var title: String {
    switch self {
    case .clipboardHistory: "Clipboard History"
    case .searchSnippets: "Search Snippets"
    case .searchRepositories: "Search Repositories"
    case .createSnippet: "Create Snippet"
    case .exportSnippets: "Export Snippets"
    case .importSnippets: "Import Snippets"
    case .settings: "Ripcord Settings"
    case .resetWindowPosition: "Reset Ripcord Window Position"
    case .quit: "Quit Ripcord"
    }
  }

  /// The key its settings are stored under. Spelled out so renaming a case never strands them.
  public var settingsKey: String {
    switch self {
    case .clipboardHistory: "command:clipboard-history"
    case .searchSnippets: "command:search-snippets"
    case .searchRepositories: "command:search-repositories"
    case .createSnippet: "command:create-snippet"
    case .exportSnippets: "command:export-snippets"
    case .importSnippets: "command:import-snippets"
    case .settings: "command:settings"
    case .resetWindowPosition: "command:reset-window-position"
    case .quit: "command:quit"
    }
  }

  /// The menu behind the footer's left button, in Raycast's place for app-level commands.
  public static let rootMenu = [
    MenuAction(
      title: "Settings", symbol: "gearshape", shortcut: "⌘,", action: .run(.settings)),
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
  }

  public enum SnippetAction: Equatable, Sendable {
    /// `delete` asks; `confirmDelete` deletes.
    case paste, copy, edit, duplicate, delete, confirmDelete
  }

  public enum ClipAction: Equatable, Sendable {
    case paste, copy, togglePin, delete
  }

  public enum Kind: Equatable, Sendable {
    case application, calculator, quicklink, command, text, image, snippet, repository

    public var primaryAction: String {
      switch self {
      case .calculator: "Copy Answer"
      case .text, .image, .snippet: "Paste to App"
      case .application, .quicklink, .command: "Open Command"
      case .repository: "Open"
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
        MenuAction(
          title: "Show in Finder", symbol: "folder", shortcut: "⇧⌘F", action: .reveal(url)),
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
    case .clip(let id, _):
      return [
        primary,
        MenuAction(
          title: "Copy to Clipboard", symbol: "doc.on.doc", shortcut: "⇧⌘C",
          action: .clip(id, .copy)),
        MenuAction(
          title: isPinned ? "Unpin" : "Pin", symbol: isPinned ? "pin.slash" : "pin",
          shortcut: "⇧⌘P", action: .clip(id, .togglePin)),
        MenuAction(title: "Delete", symbol: "trash", shortcut: "⌃X", action: .clip(id, .delete)),
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
    case .window(let layout): return [primary, .configure(layout.settingsKey)]
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
  public var isPinned = false
}

public struct SearchSection: Identifiable, Equatable, Sendable {
  public let title: String
  public let results: [SearchResult]
  public var id: String { title }
}

public enum Search {
  /// The start screen for an empty query; otherwise one "Results" section.
  public static func sections(
    for query: String, apps: [AppEntry], running: [AppEntry], quicklinks: [Quicklink],
    items: [String: ItemSettings] = [:]
  ) -> [SearchSection] {
    let links = quicklinks.filter(\.isEnabled)
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard trimmed.isEmpty else {
      let found = results(for: trimmed, apps: apps, quicklinks: links, items: items)
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
    let shownRunning = running.filter { items[$0.settingsKey]?.isEnabled ?? true }
    // Ripcord's own commands live in the footer's root menu; typing still finds them.
    return [
      // Capped so Quicklinks stay in view.
      SearchSection(
        title: "Running",
        results: shownRunning.prefix(5).map { result(for: $0, alias: items[$0.settingsKey]?.alias) }
      ),
      SearchSection(title: "Quicklinks", results: links.compactMap(result(for:))),
    ].filter { !$0.results.isEmpty }
  }

  /// Calculator first, then a Quicklink whose keyword starts the query, then fuzzy matches.
  /// An exactly typed alias or keyword puts its item at the top of the matches.
  public static func results(
    for query: String, apps: [AppEntry], quicklinks: [Quicklink],
    items: [String: ItemSettings] = [:]
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

    typealias Candidate = (names: [String], alias: String?, result: SearchResult)
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
    let ranked =
      (appCandidates + linkCandidates + commandCandidates + systemCandidates + windowCandidates)
      .compactMap { candidate -> (score: Int, result: SearchResult)? in
        let names = candidate.names + [candidate.alias].compactMap { $0 }
        guard let score = names.compactMap({ Fuzzy.score(trimmed, in: $0) }).max() else {
          return nil
        }
        let exactAlias =
          candidate.alias?.trimmingCharacters(in: .whitespaces)
          .caseInsensitiveCompare(trimmed) == .orderedSame
        return (exactAlias ? score + 10_000 : score, candidate.result)
      }
      .sorted {
        ($0.score, -$0.result.title.count, $1.result.title)
          > ($1.score, -$1.result.title.count, $0.result.title)
      }
      .prefix(30)
      .map(\.result)

    return [calculation].compactMap { $0 } + expanded + ranked
  }

  /// Clipboard History's list: pinned items, then the rest by the day they were last copied,
  /// newest first, each kept to items whose text contains the query. Images match "image" or
  /// their file name.
  public static func clipboardSections(
    for query: String, history: ClipboardHistory, now: Date = .now,
    calendar: Calendar = .current
  ) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let matches = history.items.compactMap { item -> (item: ClipItem, result: SearchResult)? in
      let id = "clip:\(item.id)"
      let action = SearchResult.Action.clip(item.id, .paste)
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
        else { return nil }
        return (
          item,
          SearchResult(
            id: id, title: title, subtitle: item.name == nil ? "\(width)×\(height)" : "",
            keyword: nil, kind: .image,
            action: action, thumbnail: history.imageURL(of: item), isPinned: item.isPinned)
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
  public static func repositorySections(
    for query: String, repositories: [Repository], settings: RepositorySettings,
    home: String = NSHomeDirectory()
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
      let menu =
        opens + [remote].compactMap { $0 } + [
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
        id: "quicklink:\(link.name)", title: link.name, subtitle: url.host() ?? "",
        keyword: link.keyword, kind: .quicklink, action: .open(url))
    }
  }

  private static func result(for layout: WindowLayout, alias: String?) -> SearchResult {
    SearchResult(
      id: layout.settingsKey, title: layout.title, subtitle: "Window Management", keyword: alias,
      kind: .command, action: .window(layout))
  }

  private static func result(for action: SystemAction, alias: String?) -> SearchResult {
    SearchResult(
      id: action.settingsKey, title: action.title, subtitle: "System Actions", keyword: alias,
      kind: .command, action: .system(action))
  }

  private static func result(for command: BuiltinCommand, alias: String?) -> SearchResult {
    SearchResult(
      id: "command:\(command)", title: command.title, subtitle: "Ripcord", keyword: alias,
      kind: .command, action: .run(command))
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
