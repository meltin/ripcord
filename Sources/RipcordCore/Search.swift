import Foundation

/// Commands Ripcord runs itself, listed alongside apps.
public enum BuiltinCommand: CaseIterable, Sendable {
  case settings, quit

  public var title: String {
    switch self {
    case .settings: "Ripcord Settings"
    case .quit: "Quit Ripcord"
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
  }

  public enum Kind: Equatable, Sendable {
    case application, calculator, quicklink, command

    public var primaryAction: String {
      switch self {
      case .calculator: "Copy Answer"
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
    default:
      return [primary]
    }
  }

  public let id: String
  public let title: String
  public let subtitle: String
  /// Shown as a chip after the title, like a Raycast alias.
  public let keyword: String?
  public let kind: Kind
  public let action: Action
}

public struct SearchSection: Identifiable, Equatable, Sendable {
  public let title: String
  public let results: [SearchResult]
  public var id: String { title }
}

public enum Search {
  /// The start screen for an empty query; otherwise one "Results" section.
  public static func sections(
    for query: String, apps: [AppEntry], running: [AppEntry], quicklinks: [Quicklink]
  ) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard trimmed.isEmpty else {
      let found = results(for: trimmed, apps: apps, quicklinks: quicklinks)
      guard found.isEmpty else { return [SearchSection(title: "Results", results: found)] }
      // Like Raycast's fallback commands: hand the whole query to each Quicklink.
      let fallbacks = quicklinks.compactMap { link in
        link.url(for: trimmed).map { url in
          SearchResult(
            id: "fallback:\(link.name)", title: link.name, subtitle: url.host() ?? "",
            keyword: link.keyword, kind: .quicklink, action: .open(url))
        }
      }
      return fallbacks.isEmpty
        ? [] : [SearchSection(title: "Use “\(trimmed)” with…", results: fallbacks)]
    }
    // Ripcord's own commands live in the footer's root menu; typing still finds them.
    return [
      // Capped so Quicklinks stay in view.
      SearchSection(title: "Running", results: running.prefix(5).map(result(for:))),
      SearchSection(title: "Quicklinks", results: quicklinks.compactMap(result(for:))),
    ].filter { !$0.results.isEmpty }
  }

  /// Calculator first, then a Quicklink whose keyword starts the query, then fuzzy matches.
  public static func results(
    for query: String, apps: [AppEntry], quicklinks: [Quicklink]
  ) -> [SearchResult] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return [] }

    let calculation = Calculator.evaluate(trimmed).map { value in
      let text = Calculator.format(value)
      return SearchResult(
        id: "calculator", title: text, subtitle: trimmed, keyword: nil, kind: .calculator,
        action: .copy(text))
    }

    let expanded = quicklinks.compactMap { link -> SearchResult? in
      guard let keyword = link.keyword, trimmed.hasPrefix(keyword + " ") else { return nil }
      let argument = trimmed.dropFirst(keyword.count + 1).trimmingCharacters(in: .whitespaces)
      guard !argument.isEmpty, let url = link.url(for: argument) else { return nil }
      return SearchResult(
        id: "quicklink-query:\(link.name)", title: argument, subtitle: link.name,
        keyword: keyword, kind: .quicklink, action: .open(url))
    }

    let candidates =
      apps.map { (names: $0.names, result: result(for: $0)) }
      + quicklinks.compactMap { link in
        result(for: link).map {
          (names: [link.name] + [link.keyword].compactMap { $0 }, result: $0)
        }
      }
      + BuiltinCommand.allCases.map { (names: [$0.title], result: result(for: $0)) }
    let ranked =
      candidates
      .compactMap { candidate in
        candidate.names.compactMap { Fuzzy.score(trimmed, in: $0) }.max().map {
          (score: $0, result: candidate.result)
        }
      }
      .sorted {
        ($0.score, -$0.result.title.count, $1.result.title)
          > ($1.score, -$1.result.title.count, $0.result.title)
      }
      .prefix(30)
      .map(\.result)

    return [calculation].compactMap { $0 } + expanded + ranked
  }

  private static func result(for app: AppEntry) -> SearchResult {
    SearchResult(
      id: app.url.path, title: app.names[0], subtitle: "", keyword: nil, kind: .application,
      action: .open(app.url))
  }

  private static func result(for link: Quicklink) -> SearchResult? {
    link.url(for: "").map { url in
      SearchResult(
        id: "quicklink:\(link.name)", title: link.name, subtitle: url.host() ?? "",
        keyword: link.keyword, kind: .quicklink, action: .open(url))
    }
  }

  private static func result(for command: BuiltinCommand) -> SearchResult {
    SearchResult(
      id: "command:\(command)", title: command.title, subtitle: "Ripcord", keyword: nil,
      kind: .command, action: .run(command))
  }
}
