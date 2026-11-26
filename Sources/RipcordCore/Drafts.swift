import Foundation

/// Forms left unfinished, as Raycast's Drafts keep them: one per form, kept across relaunches
/// in a file of their own, outside the config.
public struct SavedDrafts: Codable, Equatable, Sendable {
  /// Create Snippet's, with its Tags field as typed.
  public var snippet: Snippet?
  public var snippetTags: String?
  /// Add Bookmark's.
  public var bookmark: BookmarkDraftFields?

  public init(
    snippet: Snippet? = nil, snippetTags: String? = nil, bookmark: BookmarkDraftFields? = nil
  ) {
    self.snippet = snippet
    self.snippetTags = snippetTags
    self.bookmark = bookmark
  }

  public enum Form: String, Codable, Sendable {
    case snippet, bookmark
  }
}

/// What Add Bookmark's form holds, its group by name: the heading's line can change meanwhile.
public struct BookmarkDraftFields: Codable, Equatable, Sendable {
  public var title: String
  public var url: String
  public var description: String
  /// The heading picked; nil for No group, "" with `newGroup` for a new one.
  public var group: String?
  public var newGroup: String

  public init(
    title: String, url: String, description: String, group: String?, newGroup: String
  ) {
    self.title = title
    self.url = url
    self.description = description
    self.group = group
    self.newGroup = newGroup
  }
}

/// `SavedDrafts` read from and written to `fileURL`.
public struct DraftStore: Sendable {
  public private(set) var drafts = SavedDrafts()
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
    guard let data = try? Data(contentsOf: fileURL),
      let saved = try? JSONDecoder().decode(SavedDrafts.self, from: data)
    else { return }
    drafts = saved
  }

  /// Writes `new` when it differs, and only then keeps it, so the list matches the file.
  public mutating func save(_ new: SavedDrafts) throws {
    guard new != drafts else { return }
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(new).write(to: fileURL, options: .atomic)
    drafts = new
  }
}

extension Search {
  /// The root search's Drafts: each form left unfinished, named by what was typed, with
  /// Raycast's Open Draft and Discard Draft.
  public static func draftSection(_ drafts: SavedDrafts) -> SearchSection? {
    let snippet = drafts.snippet.map { snippet in
      draftResult(
        .snippet, command: .createSnippet,
        name: snippet.name.isEmpty ? firstLine(snippet.text) : snippet.name)
    }
    let bookmark = drafts.bookmark.map { fields in
      draftResult(
        .bookmark, command: .addBookmark, name: fields.title.isEmpty ? fields.url : fields.title)
    }
    let results = [snippet, bookmark].compactMap { $0 }
    return results.isEmpty ? nil : SearchSection(title: "Drafts", results: results)
  }

  private static func firstLine(_ text: String) -> String {
    text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
  }

  private static func draftResult(
    _ form: SavedDrafts.Form, command: BuiltinCommand, name: String
  ) -> SearchResult {
    let menu = [
      MenuAction(title: "Open Draft", symbol: "return", shortcut: "↵", action: .openDraft(form)),
      MenuAction(
        title: "Discard Draft", symbol: "trash", shortcut: "⌃X", action: .discardDraft(form),
        isDestructive: true),
    ]
    return SearchResult(
      id: "draft:\(form.rawValue)", title: command.title, subtitle: name, keyword: nil,
      kind: .draft, action: menu[0].action, menu: menu)
  }
}
