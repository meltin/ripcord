import Foundation

/// The Settings sidebar's search, as Raycast's: a page is found by its name, or by a setting or
/// command on it whose title or description holds the query.
public enum SettingsSearch {
  public struct Item: Equatable, Sendable {
    public let title: String
    public let detail: String

    public init(title: String, detail: String = "") {
      self.title = title
      self.detail = detail
    }

    func matches(_ query: String) -> Bool {
      title.localizedStandardContains(query) || detail.localizedStandardContains(query)
    }
  }

  public struct Page: Equatable, Sendable {
    public let name: String
    public let settings: [Item]
    public let commands: [Item]

    public init(name: String, settings: [Item] = [], commands: [Item] = []) {
      self.name = name
      self.settings = settings
      self.commands = commands
    }
  }

  /// The pages found, in order, each with only its settings and commands that matched; nil
  /// while the query is blank, when the sidebar lists every page.
  public static func results(_ query: String, in pages: [Page]) -> [Page]? {
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return nil }
    return pages.compactMap { page in
      let settings = page.settings.filter { $0.matches(query) }
      let commands = page.commands.filter { $0.matches(query) }
      guard page.name.localizedStandardContains(query) || !settings.isEmpty || !commands.isEmpty
      else { return nil }
      return Page(name: page.name, settings: settings, commands: commands)
    }
  }
}
