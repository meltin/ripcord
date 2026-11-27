import Foundation

/// A named URL; `{query}` in `url` is replaced by what follows `keyword` in the search field.
/// The keyword doubles as its alias, and the link keeps its own hotkey and on/off switch, so a
/// rename never strands them.
public struct Quicklink: Codable, Equatable, Sendable {
  /// Its row's ID in the panel, which its hotkey is shown by too.
  public var rowID: String { "quicklink:\(name)" }

  public var name: String
  public var url: String
  public var keyword: String?
  public var hotkey: String?
  /// Stored only when true, so untouched links stay as short as before.
  public var disabled: Bool?

  public init(
    name: String, url: String, keyword: String? = nil, hotkey: String? = nil,
    disabled: Bool? = nil
  ) {
    self.name = name
    self.url = url
    self.keyword = keyword
    self.hotkey = hotkey
    self.disabled = disabled
  }

  public var isEnabled: Bool {
    get { disabled != true }
    set { disabled = newValue ? nil : true }
  }

  public func url(for argument: String) -> URL? {
    // Only RFC 3986 unreserved characters pass, so "&", "#" and "+" can't break the query.
    let unreserved = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    let encoded = argument.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    let filled = url.replacingOccurrences(of: "{query}", with: encoded)
    // A file or folder, as Raycast's Quicklinks take one: ~/Downloads or /Applications.
    if filled.hasPrefix("~/") || filled == "~" || filled.hasPrefix("/") {
      return URL(fileURLWithPath: (filled as NSString).expandingTildeInPath)
    }
    return URL(string: filled)
  }
}

extension Quicklink {
  /// Why Create Quicklink's form can't be saved as typed, or nil when it can: a name and a link
  /// that opens, the name and keyword no other Quicklink has. `editing` is the one being edited.
  public static func problem(
    name: String, link: String, keyword: String, among links: [Quicklink], editing: Int?
  ) -> String? {
    let name = name.trimmingCharacters(in: .whitespaces)
    let keyword = keyword.trimmingCharacters(in: .whitespaces)
    let others = links.enumerated().filter { $0.offset != editing }.map(\.element)
    if name.isEmpty { return "Give the Quicklink a name." }
    if link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Type the link to open."
    }
    if Quicklink(name: name, url: link.trimmingCharacters(in: .whitespacesAndNewlines))
      .url(for: "")?.scheme == nil
    {
      return "That link can't be opened. Start it with https:// or another app's scheme."
    }
    if others.contains(where: { $0.name == name }) {
      return "Another Quicklink is named “\(name)”."
    }
    if !keyword.isEmpty, others.contains(where: { $0.keyword == keyword }) {
      return "Another Quicklink has the keyword “\(keyword)”."
    }
    return nil
  }
}

extension Search {
  /// Search Quicklinks' list: every Quicklink, best match first, each opened by Return and
  /// edited or deleted from ⌘K, as Raycast's.
  public static func quicklinkSections(for query: String, quicklinks: [Quicklink])
    -> [SearchSection]
  {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let ranked = quicklinks.enumerated().compactMap {
      entry -> (score: Int, index: Int, link: Quicklink)? in
      let link = entry.element
      guard !trimmed.isEmpty else { return (0, entry.offset, link) }
      let score = [
        Fuzzy.score(trimmed, in: link.name),
        link.url.localizedStandardContains(trimmed) || link.keyword == trimmed ? 0 : nil,
      ].compactMap { $0 }.max()
      return score.map { ($0, entry.offset, link) }
    }
    .sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }
    let results = ranked.map { _, index, link in
      let open = link.url(for: "").map {
        MenuAction(title: "Open Quicklink", symbol: "link", shortcut: "↵", action: .open($0))
      }
      let menu =
        [open].compactMap { $0 } + [
          MenuAction(
            title: "Edit Quicklink", symbol: "pencil", shortcut: "⌘E",
            action: .editQuicklink(index: index, name: link.name)),
          MenuAction(
            title: "Create Quicklink", symbol: "plus", shortcut: "⌘N",
            action: .run(.createQuicklink)),
          MenuAction(
            title: "Delete Quicklink", symbol: "trash", shortcut: "⌃X",
            action: .deleteQuicklink(index: index, name: link.name, confirmed: false),
            isDestructive: true),
        ]
      return SearchResult(
        id: "quicklink-list:\(index)", title: link.name, subtitle: link.url,
        keyword: link.keyword, kind: .quicklink, action: menu[0].action, menu: menu,
        // Its hotkey is kept under its row ID, as on the root search.
        settingsKey: link.rowID)
    }
    return results.isEmpty ? [] : [SearchSection(title: "Quicklinks", results: results)]
  }
}

/// Raycast's Import Quicklinks and Export Quicklinks file: an array of `name` and `link`, with
/// `openWith` and `iconName` Ripcord doesn't keep. Its `{argument}` is Ripcord's `{query}`.
extension Quicklink {
  private struct RaycastEntry: Codable {
    var name: String
    var link: String
    /// Ripcord's own, which Raycast leaves alone.
    var keyword: String?
  }

  /// Quicklinks as Raycast imports them, keywords kept for Ripcord to read back.
  public static func exportData(_ links: [Quicklink]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(
      links.map {
        RaycastEntry(
          name: $0.name, link: $0.url.replacingOccurrences(of: "{query}", with: "{argument}"),
          keyword: $0.keyword)
      })
  }

  /// `imported` added after `current`, as Raycast imports: one with the same name and link as
  /// one already here is skipped. Another's name gets a number, and a keyword already used is
  /// left off. Raycast's `{argument}` and `{argument name="…"}` become `{query}`.
  public static func merging(_ data: Data, into current: [Quicklink]) throws -> (
    links: [Quicklink], added: Int, skipped: Int
  ) {
    let entries = try JSONDecoder().decode([RaycastEntry].self, from: data)
    var links = current
    var skipped = 0
    for entry in entries {
      let name = entry.name.trimmingCharacters(in: .whitespaces)
      let link = entry.link.replacingOccurrences(
        of: #"\{argument( [^}]*)?\}"#, with: "{query}", options: .regularExpression)
      guard !name.isEmpty, !link.isEmpty else { continue }
      if links.contains(where: { $0.name == name && $0.url == link }) {
        skipped += 1
        continue
      }
      var unique = name
      var number = 2
      while links.contains(where: { $0.name == unique }) {
        unique = "\(name) \(number)"
        number += 1
      }
      let keyword = entry.keyword.flatMap { keyword in
        links.contains { $0.keyword == keyword } ? nil : keyword
      }
      links.append(Quicklink(name: unique, url: link, keyword: keyword))
    }
    return (links, links.count - current.count, skipped)
  }
}

/// Settings › Quicklinks' settings, as Raycast's.
public struct QuicklinkSettings: Codable, Equatable, Sendable {
  /// A Quicklink's hotkey fills its `{query}` with the text selected in the app in front, as
  /// Raycast's "Pass Selected Text as Argument"; off by default, as there.
  public var passSelectedText: Bool
  /// Delete Quicklink asks first, as Raycast's "Show Warning Before Deleting Quicklinks"; on by
  /// default.
  public var showDeleteWarning: Bool

  public init(passSelectedText: Bool = false, showDeleteWarning: Bool = true) {
    self.passSelectedText = passSelectedText
    self.showDeleteWarning = showDeleteWarning
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      passSelectedText: try container.decodeIfPresent(Bool.self, forKey: .passSelectedText)
        ?? false,
      showDeleteWarning: try container.decodeIfPresent(Bool.self, forKey: .showDeleteWarning)
        ?? true)
  }
}
