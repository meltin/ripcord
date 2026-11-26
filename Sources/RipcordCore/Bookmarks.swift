import Foundation

/// One bookmark line of `bookmarks.md`: `- [Title](https://example.com) - Optional description`.
public struct Bookmark: Equatable, Sendable {
  public let title: String
  public let url: URL
  public let description: String?
  /// The heading above it; empty before the first heading.
  public let group: String
  /// The heading's line, which tells two headings of the same name apart; -1 before the first.
  public let groupLine: Int
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

  /// The bookmarks, in file order; lines that aren't bookmarks or headings, and anything in a
  /// fenced code block, are left alone.
  public var bookmarks: [Bookmark] {
    var group = (title: "", line: -1)
    var fence: String?
    return lines.enumerated().compactMap { index, line in
      let trimmed = line.text.trimmingCharacters(in: Self.blank)
      if let open = fence {
        if trimmed.hasPrefix(open) { fence = nil }
        return nil
      }
      if let marker = ["```", "~~~"].first(where: trimmed.hasPrefix) {
        fence = marker
        return nil
      }
      if let heading = Self.heading(trimmed) {
        group = (heading, index)
        return nil
      }
      return Self.bookmark(trimmed, group: group, line: index, text: line.text)
    }
  }

  /// Spaces, tabs and a UTF-8 byte order mark, which can start the first line.
  static let blank = CharacterSet.whitespaces.union(["\u{FEFF}"])

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

  /// `# Group` to `###### Group`, closing hashes (`## Group ##`) left out.
  static func heading(_ trimmed: String) -> String? {
    let hashes = trimmed.prefix { $0 == "#" }
    guard (1...6).contains(hashes.count), let space = trimmed.dropFirst(hashes.count).first,
      space == " " || space == "\t"
    else { return nil }
    let words = trimmed.dropFirst(hashes.count).split(whereSeparator: \.isWhitespace)
    let title = words.reversed().drop { $0.allSatisfy { $0 == "#" } }.reversed().joined(
      separator: " ")
    return title.isEmpty ? nil : title
  }

  /// `- [Title](url) - description`, the URL allowed its own parentheses, as Wikipedia's have,
  /// and a task list's `[ ]` or `[x]` before the link.
  static func bookmark(
    _ trimmed: String, group: (title: String, line: Int), line index: Int, text: String
  ) -> Bookmark? {
    guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return nil }
    var item = trimmed.dropFirst(2)
    for box in ["[ ] ", "[x] ", "[X] "] where item.hasPrefix(box) {
      item = item.dropFirst(box.count).drop(while: \.isWhitespace)
    }
    guard item.hasPrefix("[") else { return nil }
    let afterBracket = item.dropFirst()
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
    // A link title (`[T](https://x.com "Tip")`) follows the URL after a space.
    let target = afterBracket[titleEnd.upperBound..<(urlEnd ?? afterBracket.endIndex)]
      .prefix { !$0.isWhitespace }
    guard let urlEnd, !title.isEmpty, let url = URL(string: String(target)), url.scheme != nil
    else { return nil }
    let rest = afterBracket[afterBracket.index(after: urlEnd)...]
      .trimmingCharacters(in: .whitespaces)
    let description =
      rest.hasPrefix("- ") ? String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces) : nil
    return Bookmark(
      title: title, url: url, description: description?.isEmpty == true ? nil : description,
      group: group.title, groupLine: group.line, line: index, text: text)
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
    // Each heading where the file has it, even two with the same name.
    let headings = matches.map(\.groupLine).reduce(into: [Int]()) { order, line in
      if order.last != line { order.append(line) }
    }
    return headings.map { line in
      let rows = matches.filter { $0.groupLine == line }
      return SearchSection(
        title: rows[0].group.isEmpty ? "Bookmarks" : rows[0].group,
        results: rows.map(result(for:)), id: "heading:\(line)")
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
