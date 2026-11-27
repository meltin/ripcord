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
    return URL(string: url.replacingOccurrences(of: "{query}", with: encoded))
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
        keyword: link.keyword, kind: .quicklink, action: menu[0].action, menu: menu)
    }
    return results.isEmpty ? [] : [SearchSection(title: "Quicklinks", results: results)]
  }
}
