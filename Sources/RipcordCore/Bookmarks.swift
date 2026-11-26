import Foundation

/// One bookmark line of `bookmarks.md`: `- [Title](https://example.com) - Optional description`.
public struct Bookmark: Equatable, Sendable {
  public let title: String
  public let url: URL
  public let description: String?
  /// The heading above it; empty before the first heading.
  public let group: String
  /// Where it is in the file, and the line as it was read, to find it again before a change.
  public let line: Int
  public let text: String
}

/// `bookmarks.md` as written: every line kept with its own line ending, so a change rewrites
/// only the lines it touches and the rest of the file, prose and blank lines included, comes
/// back byte for byte.
public struct BookmarkFile: Equatable, Sendable {
  /// Each line's text and the ending that followed it ("\n", "\r\n", or "" for the last line).
  public private(set) var lines: [(text: String, ending: String)]

  public init(text: String) {
    var lines: [(text: String, ending: String)] = []
    var rest = Substring(text)
    // Swift reads "\r\n" as one Character, so a CRLF ending is found whole, not as "\n".
    while let end = rest.firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) {
      lines.append((String(rest[..<end]), String(rest[end])))
      rest = rest[rest.index(after: end)...]
    }
    if !rest.isEmpty { lines.append((String(rest), "")) }
    self.lines = lines
  }

  /// The file's text, the same bytes as read for the lines no change touched.
  public var text: String { lines.map { $0.text + $0.ending }.joined() }

  public static func == (lhs: BookmarkFile, rhs: BookmarkFile) -> Bool { lhs.text == rhs.text }

  /// The bookmarks, in file order; lines that aren't bookmarks or headings are left alone.
  public var bookmarks: [Bookmark] {
    var group = ""
    return lines.enumerated().compactMap { index, line in
      if let heading = Self.heading(line.text) {
        group = heading
        return nil
      }
      return Self.bookmark(line.text, group: group, line: index)
    }
  }

  /// Without the bookmark on `line`, or nil when that line no longer holds `text` (the file
  /// changed since it was read).
  public func deleting(line: Int, text: String) -> BookmarkFile? {
    guard lines.indices.contains(line), lines[line].text == text else { return nil }
    var file = self
    let removed = file.lines.remove(at: line)
    // The last line taken away leaves the one before it last, without a newline, as it was.
    if line == file.lines.count, removed.ending.isEmpty, !file.lines.isEmpty {
      file.lines[file.lines.count - 1].ending = ""
    }
    return file
  }

  /// `# Group` to `###### Group`.
  static func heading(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let hashes = trimmed.prefix { $0 == "#" }
    guard (1...6).contains(hashes.count), trimmed.dropFirst(hashes.count).first == " " else {
      return nil
    }
    let title = trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
    return title.isEmpty ? nil : title
  }

  /// `- [Title](url) - description`, the URL allowed its own parentheses, as Wikipedia's have.
  static func bookmark(_ line: String, group: String, line index: Int) -> Bookmark? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") else { return nil }
    let afterBracket = trimmed.dropFirst(3)
    guard let titleEnd = afterBracket.range(of: "](") else { return nil }
    let title = String(afterBracket[..<titleEnd.lowerBound])
    var depth = 1
    var urlEnd: Substring.Index?
    for index in afterBracket[titleEnd.upperBound...].indices {
      switch afterBracket[index] {
      case "(": depth += 1
      case ")": depth -= 1
      default: break
      }
      if depth == 0 {
        urlEnd = index
        break
      }
    }
    guard let urlEnd, !title.isEmpty,
      let url = URL(string: String(afterBracket[titleEnd.upperBound..<urlEnd])), url.scheme != nil
    else { return nil }
    let rest = afterBracket[afterBracket.index(after: urlEnd)...]
      .trimmingCharacters(in: .whitespaces)
    let description =
      rest.hasPrefix("- ") ? String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces) : nil
    return Bookmark(
      title: title, url: url, description: description?.isEmpty == true ? nil : description,
      group: group, line: index, text: line)
  }
}

extension Search {
  /// The bookmarks under their headings, in file order; a query matches the title, the URL or
  /// the description.
  public static func bookmarkSections(for query: String, file: BookmarkFile) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let matches = file.bookmarks.filter { bookmark in
      trimmed.isEmpty
        || [bookmark.title, bookmark.url.absoluteString, bookmark.description ?? ""]
          .contains { $0.localizedStandardContains(trimmed) }
    }
    // Headings in the order the file has them.
    let groups = matches.map(\.group).reduce(into: [String]()) { order, group in
      if !order.contains(group) { order.append(group) }
    }
    return groups.map { group in
      SearchSection(
        title: group.isEmpty ? "Bookmarks" : group,
        results: matches.filter { $0.group == group }.map(result(for:)))
    }
  }

  private static func result(for bookmark: Bookmark) -> SearchResult {
    let menu = [
      MenuAction(
        title: "Open in Browser", symbol: "safari", shortcut: "↵", action: .open(bookmark.url)),
      MenuAction(
        title: "Copy URL", symbol: "link", shortcut: "⇧⌘C",
        action: .copy(bookmark.url.absoluteString)),
      MenuAction(
        title: "Copy Title", symbol: "doc.on.doc", shortcut: "⌥⌘C", action: .copy(bookmark.title)),
      MenuAction(
        title: "Delete Bookmark", symbol: "trash", shortcut: "⌃X",
        action: .deleteBookmark(line: bookmark.line, text: bookmark.text), isDestructive: true,
        startsSection: true),
    ]
    return SearchResult(
      id: "bookmark:\(bookmark.line):\(bookmark.url.absoluteString)", title: bookmark.title,
      subtitle: bookmark.description ?? bookmark.url.host() ?? bookmark.url.absoluteString,
      keyword: nil, kind: .bookmark, action: menu[0].action, menu: menu)
  }
}
