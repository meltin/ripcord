import Foundation

/// Commands Ripcord runs itself, listed alongside apps.
public enum BuiltinCommand: CaseIterable, Sendable {
  case clipboardHistory, settings, resetWindowPosition, quit

  public var title: String {
    switch self {
    case .clipboardHistory: "Clipboard History"
    case .settings: "Ripcord Settings"
    case .resetWindowPosition: "Reset Ripcord Window Position"
    case .quit: "Quit Ripcord"
    }
  }

  /// The key its settings are stored under. Spelled out so renaming a case never strands them.
  public var settingsKey: String {
    switch self {
    case .clipboardHistory: "command:clipboard-history"
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
}

public struct SearchResult: Identifiable, Equatable, Sendable {
  public enum Action: Equatable, Sendable {
    case open(URL)
    case copy(String)
    case reveal(URL)
    case run(BuiltinCommand)
    case clip(UUID, ClipAction)
  }

  public enum ClipAction: Equatable, Sendable {
    case paste, copy, togglePin, delete
  }

  public enum Kind: Equatable, Sendable {
    case application, calculator, quicklink, command, text, image

    public var primaryAction: String {
      switch self {
      case .calculator: "Copy Answer"
      case .text, .image: "Paste to App"
      case .application, .quicklink, .command: "Open Command"
      }
    }
  }

  /// What ⌘K lists for this row, the primary action first.
  public var actions: [MenuAction] {
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
      ]
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
      ]
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
    let ranked = (appCandidates + linkCandidates + commandCandidates)
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
  /// newest first, each kept to items whose text contains the query. Images match "image".
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

  /// Every app, Quicklink and command the Shortcuts page lists, in its three sections. Disabled
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
    ]
  }

  private static func result(for app: AppEntry, alias: String?) -> SearchResult {
    SearchResult(
      id: app.url.path, title: app.names[0], subtitle: "", keyword: alias, kind: .application,
      action: .open(app.url))
  }

  private static func result(for link: Quicklink) -> SearchResult? {
    link.url(for: "").map { url in
      SearchResult(
        id: "quicklink:\(link.name)", title: link.name, subtitle: url.host() ?? "",
        keyword: link.keyword, kind: .quicklink, action: .open(url))
    }
  }

  private static func result(for command: BuiltinCommand, alias: String?) -> SearchResult {
    SearchResult(
      id: "command:\(command)", title: command.title, subtitle: "Ripcord", keyword: alias,
      kind: .command, action: .run(command))
  }
}
