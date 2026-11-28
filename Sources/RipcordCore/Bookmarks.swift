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
  /// What comes before the link on its line (indent, `- `, a task list's `[x] `), kept when the
  /// bookmark is edited.
  public let prefix: String
  /// The link's target as written on the line, which `url` may have percent-encoded.
  public let rawURL: String

  /// Whether the line holds only what the form shows, so an edit loses nothing written on it,
  /// such as a link title (`"Tip"`) or a note after the link.
  public var isEditable: Bool {
    // Spaces at the end of the line don't hold anything.
    text.replacing(/\s+$/, with: "")
      == prefix + "[\(title)](\(rawURL))" + (description.map { " - \($0)" } ?? "")
  }
}

/// `bookmarks.md` as written: every line kept with its own line ending, so a change rewrites
/// only the lines it touches and the rest of the file, prose and blank lines included, comes
/// back byte for byte.
public struct BookmarkFile: Equatable, Sendable {
  /// Each line's text and the ending that followed it ("\n", "\r\n", or "" for the last line).
  public private(set) var lines: [(text: String, ending: String)]

  /// A heading, which a bookmark goes under; line -1 stands for the top, above the first one.
  public struct Heading: Equatable, Sendable {
    public let title: String
    public let line: Int

    public init(title: String, line: Int) {
      self.title = title
      self.line = line
    }
  }

  /// Where a saved or moved bookmark goes.
  public enum Destination: Equatable, Sendable {
    case heading(Heading)
    /// A new `#` heading at the end of the file.
    case newHeading(String)
  }

  public enum EditError: Error, Equatable {
    /// The bookmark or heading isn't on its line any more: the file changed since it was read.
    case changed
    /// What's wrong with the title, URL or group, for the user.
    case invalid(String)
  }

  /// Whether the file starts with a UTF-8 byte order mark. It's kept off the first line, so a
  /// moved line doesn't carry it away, and put back in front of the text.
  public private(set) var hasByteOrderMark = false

  public init(text: String) {
    var lines: [(text: String, ending: String)] = []
    var rest = Substring(text)
    if rest.unicodeScalars.first == "\u{FEFF}" {
      hasByteOrderMark = true
      rest = Substring(rest.unicodeScalars.dropFirst())
    }
    // Swift reads "\r\n" as one Character, so a CRLF ending is found whole, not as "\n".
    while let end = rest.firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) {
      lines.append((String(rest[..<end]), String(rest[end])))
      rest = rest[rest.index(after: end)...]
    }
    if !rest.isEmpty { lines.append((String(rest), "")) }
    self.lines = lines
  }

  /// The file's text, the same bytes as read for the lines no change touched.
  public var text: String {
    (hasByteOrderMark ? "\u{FEFF}" : "") + lines.map { $0.text + $0.ending }.joined()
  }

  public static func == (lhs: BookmarkFile, rhs: BookmarkFile) -> Bool { lhs.text == rhs.text }

  /// The bookmarks, in file order.
  public var bookmarks: [Bookmark] { scan.bookmarks }
  /// The headings, in file order.
  public var headings: [Heading] { scan.headings }

  /// One pass over the lines for headings and bookmarks; lines that are neither, and anything
  /// in a fenced code block, are left alone. Reading and changing the file both go by it.
  private var scan: (headings: [Heading], bookmarks: [Bookmark], endsInFence: Bool) {
    var headings: [Heading] = []
    var bookmarks: [Bookmark] = []
    var group = Heading(title: "", line: -1)
    var fence: String?
    for (index, line) in lines.enumerated() {
      let trimmed = line.text.trimmingCharacters(in: Self.blank)
      // YAML front matter at the top is the file's settings, its `#` lines comments.
      if index == 0, trimmed == "---",
        lines.dropFirst().contains(where: { $0.text.trimmingCharacters(in: Self.blank) == "---" })
      {
        fence = "---"
        continue
      }
      if let open = fence {
        if trimmed.hasPrefix(open) { fence = nil }
        continue
      }
      if let marker = ["```", "~~~"].first(where: trimmed.hasPrefix) {
        fence = marker
        continue
      }
      if let title = Self.heading(trimmed) {
        group = Heading(title: title, line: index)
        headings.append(group)
      } else if let bookmark = Self.bookmark(line.text, group: group, line: index) {
        bookmarks.append(bookmark)
      }
    }
    return (headings, bookmarks, fence != nil)
  }

  static let blank = CharacterSet.whitespaces

  /// Without the bookmark on `line` and what's indented under it, or nil when that line no
  /// longer holds `text` (the file changed since it was read).
  public func deleting(line: Int, text: String) -> BookmarkFile? {
    guard lines.indices.contains(line), lines[line].text == text else { return nil }
    let found = bookmarks.first { $0.line == line }
    return removing(found.map(block(of:)) ?? line..<line + 1)
  }

  /// Without `range`'s lines. Taking the last line away leaves the one before it last, without
  /// a newline, as it was.
  private func removing(_ range: Range<Int>) -> BookmarkFile {
    var file = self
    let lastEnding = lines[range.upperBound - 1].ending
    file.lines.removeSubrange(range)
    if range.upperBound == lines.count, lastEnding.isEmpty, !file.lines.isEmpty {
      file.lines[file.lines.count - 1].ending = ""
    }
    return file
  }

  /// The bookmark's line and the lines indented under it (a note, sub-items), which go with it.
  private func block(of bookmark: Bookmark) -> Range<Int> {
    let indent = bookmark.prefix.prefix(while: \.isWhitespace).count
    var end = bookmark.line + 1
    let indented = { (line: Int) in
      let text = self.lines[line].text
      return !text.allSatisfy(\.isWhitespace) && text.prefix(while: \.isWhitespace).count > indent
    }
    while end < lines.count, indented(end) {
      let trimmed = lines[end].text.trimmingCharacters(in: Self.blank)
      // A heading, or a bookmark of its own however indented, isn't part of this one.
      if Self.heading(trimmed) != nil
        || Self.bookmark(lines[end].text, group: .init(title: "", line: -1), line: end) != nil
      {
        break
      }
      // An indented code block goes with it whole, if it closes while still indented.
      if let marker = ["```", "~~~"].first(where: trimmed.hasPrefix) {
        guard
          let close = lines.indices.dropFirst(end + 1).first(where: {
            !indented($0) || lines[$0].text.trimmingCharacters(in: Self.blank).hasPrefix(marker)
          }), indented(close)
        else { break }
        end = close + 1
        continue
      }
      end += 1
    }
    return bookmark.line..<end
  }

  /// With a bookmark saved from the form: a new one when `original` is nil, otherwise that one
  /// edited, in place while it stays under its heading. Also the line it ended up on.
  public func saving(
    title: String, url: String, description: String, replacing original: (line: Int, text: String)?,
    under destination: Destination
  ) throws(EditError) -> (file: BookmarkFile, line: Int, text: String) {
    let title = title.trimmingCharacters(in: .whitespaces)
    let url = url.trimmingCharacters(in: .whitespaces)
    let description = description.trimmingCharacters(in: .whitespaces)
    let found: Bookmark? = if let original { try bookmark(original) } else { nil }
    if let found, !found.isEditable {
      throw .invalid(
        "This bookmark's line has text the form doesn't show; edit it in the bookmarks file instead."
      )
    }
    guard !title.isEmpty else { throw .invalid("A bookmark needs a title.") }
    guard !url.contains(where: \.isWhitespace), let parsedURL = URL(string: url),
      parsedURL.scheme != nil
    else { throw .invalid("“\(url)” isn't a full URL, such as https://example.com.") }
    let text =
      (found?.prefix ?? "- ") + "[\(title)](\(url))"
      + (description.isEmpty ? "" : " - \(description)")
    // Saved only as it reads back: a stray bracket would change what the line means.
    guard let check = Self.bookmark(text, group: Heading(title: "", line: -1), line: 0),
      check.title == title, check.url == parsedURL,
      check.description == (description.isEmpty ? nil : description),
      !text.contains(where: \.isNewline)
    else {
      throw .invalid(
        "That title or URL can't be written as a Markdown link; take out brackets or parentheses that don't pair up."
      )
    }
    return try placing(text, moving: found, under: destination)
  }

  /// With the bookmark moved under `destination`, its line and what's indented under it kept as
  /// written.
  public func moving(line: Int, text: String, under destination: Destination) throws(EditError)
    -> (file: BookmarkFile, line: Int, text: String)
  {
    let found = try bookmark((line, text))
    return try placing(found.text, moving: found, under: destination)
  }

  /// The bookmark on `original.line`, if that line still holds it.
  private func bookmark(_ original: (line: Int, text: String)) throws(EditError) -> Bookmark {
    guard
      let found = bookmarks.first(where: { $0.line == original.line && $0.text == original.text })
    else { throw .changed }
    return found
  }

  /// `text` under `destination`: on `original`'s line when that's under it already, otherwise
  /// after the last bookmark there and what's indented under it, with `original` and its own
  /// indented lines moved along.
  private func placing(_ text: String, moving original: Bookmark?, under destination: Destination)
    throws(EditError) -> (file: BookmarkFile, line: Int, text: String)
  {
    let current = headings
    var target: Heading?
    var newTitle: String?
    switch destination {
    case .heading(let heading):
      guard heading.line == -1 || current.contains(heading) else { throw .changed }
      target = heading
    case .newHeading(let title):
      let title = title.trimmingCharacters(in: .whitespaces)
      guard !title.isEmpty, Self.heading("# \(title)") == title else {
        throw .invalid("A new group needs a name on one line.")
      }
      // One by that name already: there, rather than a second heading of the same name.
      target = current.first { $0.title == title }
      newTitle = title
    }
    if let original, let target, original.groupLine == target.line {
      var file = self
      // Spaces it ended with stay: two make a line break in Markdown.
      let trailing = original.text.reversed().prefix(while: \.isWhitespace).reversed()
      file.lines[original.line].text = text + String(trailing)
      return (file, original.line, file.lines[original.line].text)
    }
    var file = self
    var placed = [text]
    var headingLine = target?.line ?? -1
    if let original {
      let block = block(of: original)
      placed += lines[block.dropFirst()].map(\.text)
      file = removing(block)
      if headingLine > original.line { headingLine -= block.count }
    }
    guard target != nil else {
      // Lines after a code block left open would land inside it, out of the list.
      guard !file.scan.endsInFence else {
        throw .invalid(
          "The bookmarks file ends inside a code block that isn't closed; close it first.")
      }
      return file.appendingHeading(newTitle ?? "", then: placed)
    }
    let after = file.scan
    let next = after.headings.first { $0.line > headingLine }?.line ?? file.lines.count
    let last =
      after.bookmarks.last { $0.line > headingLine && $0.line < next }
      .map { file.block(of: $0).upperBound - 1 }
      // No group with nothing there yet: just above the first heading, below a title, front
      // matter or prose that opens the file; at the top when the file ends in an open code
      // block, which the end would be inside.
      ?? (headingLine == -1 && !(after.headings.isEmpty && after.endsInFence)
        ? next - 1 : headingLine)
    for (offset, line) in placed.enumerated() { file.insert(line, after: last + offset) }
    return (file, last + 1, text)
  }

  /// With `# title` and then `placed` at the end of the file, a blank line before them.
  private func appendingHeading(_ title: String, then placed: [String])
    -> (file: BookmarkFile, line: Int, text: String)
  {
    var file = self
    let ending = file.lineEnding
    // A file without a final newline stays without one.
    let endsOpen = file.lines.last?.ending.isEmpty ?? false
    if let last = file.lines.indices.last {
      if endsOpen { file.lines[last].ending = ending }
      if !file.lines[last].text.trimmingCharacters(in: Self.blank).isEmpty {
        file.lines.append(("", ending))
      }
    }
    file.lines.append(("# \(title)", ending))
    let line = file.lines.count
    file.lines += placed.map { ($0, ending) }
    if endsOpen { file.lines[file.lines.count - 1].ending = "" }
    return (file, line, placed[0])
  }

  /// Puts `text` after line `index` (-1 for the first line), with the ending its neighbour has.
  private mutating func insert(_ text: String, after index: Int) {
    guard lines.indices.contains(index) else {
      return lines.insert((text, lineEnding), at: 0)
    }
    if lines[index].ending.isEmpty {
      // After the last line, which has no newline: that line gets one, the new line doesn't.
      lines[index].ending = lineEnding
      lines.insert((text, ""), at: index + 1)
    } else {
      lines.insert((text, lines[index].ending), at: index + 1)
    }
  }

  /// The file's line ending, "\n" for a file that has none yet.
  private var lineEnding: String { lines.first { !$0.ending.isEmpty }?.ending ?? "\n" }

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
  static func bookmark(_ text: String, group: Heading, line index: Int) -> Bookmark? {
    let lead = text.prefix { $0.unicodeScalars.allSatisfy(blank.contains) }
    let trimmed = text.trimmingCharacters(in: blank)
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
      group: group.title, groupLine: group.line, line: index, text: text,
      prefix: String(lead) + trimmed[..<item.startIndex], rawURL: String(target))
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
      // With the title, so a heading renamed in place redraws.
      return SearchSection(
        title: rows[0].group.isEmpty ? "Bookmarks" : rows[0].group,
        results: rows.map(result(for:)), id: "heading:\(line):\(rows[0].group)")
    }
  }

  /// Move to Group's list: every heading but the bookmark's own.
  public static func moveMenu(for bookmark: (line: Int, text: String), file: BookmarkFile)
    -> [MenuAction]
  {
    let own = file.bookmarks.first { $0.line == bookmark.line && $0.text == bookmark.text }?
      .groupLine
    return file.headings.filter { $0.line != own }.map { heading in
      MenuAction(
        title: heading.title, symbol: "number", shortcut: "",
        action: .moveBookmark(
          line: bookmark.line, text: bookmark.text, headingLine: heading.line,
          headingTitle: heading.title))
    }
  }

  private static func result(for bookmark: Bookmark) -> SearchResult {
    let menu = [
      MenuAction(
        title: "Open in Browser", symbol: "safari", shortcut: "↵", action: .open(bookmark.url)),
      // MarkMarks' keys; ⌘C copies only while no text is selected in the search field.
      MenuAction(
        title: "Copy URL", symbol: "link", shortcut: "⌘C",
        action: .copy(bookmark.url.absoluteString)),
      MenuAction(
        title: "Copy Title", symbol: "doc.on.doc", shortcut: "⇧⌘C", action: .copy(bookmark.title)),
      MenuAction(
        title: "Edit Bookmark", symbol: "pencil", shortcut: "⌘E",
        action: .editBookmark(line: bookmark.line, text: bookmark.text), startsSection: true),
      MenuAction(
        title: "Move to Group…", symbol: "arrow.turn.up.right", shortcut: "⌘M",
        action: .moveBookmarkMenu(line: bookmark.line, text: bookmark.text)),
      // ⌃X, not MarkMarks' ⌘⌫: that clears the search field, and the delete isn't asked first.
      MenuAction(
        title: "Delete Bookmark", symbol: "trash", shortcut: "⌃X",
        action: .deleteBookmark(line: bookmark.line, text: bookmark.text), isDestructive: true),
      MenuAction(
        title: "Reveal Bookmarks File in Finder", symbol: "folder", shortcut: "⇧⌘O",
        action: .revealBookmarksFile, startsSection: true),
    ]
    // With the line's text, so an edit that keeps the URL still redraws the row.
    return SearchResult(
      id: "bookmark:\(bookmark.line):\(bookmark.text)", title: bookmark.title,
      subtitle: bookmark.description ?? bookmark.url.host() ?? bookmark.url.absoluteString,
      keyword: nil, kind: .bookmark, action: menu[0].action, menu: menu)
  }
}

/// Where bookmarks.md lives: Raycast's MarkMarks has the user pick its file. Unset, Ripcord's
/// own under ~/.config.
public enum BookmarkFileLocation {
  public static let defaultPath = "~/.config/ripcord/bookmarks.md"

  /// `path`, `~` expanded; the default for nil or blank. One typed without `/` or `~/` is taken
  /// from the home folder, never from wherever the app happens to run.
  public static func url(for path: String?, home: String = NSHomeDirectory()) -> URL {
    let trimmed = path?.trimmingCharacters(in: .whitespaces) ?? ""
    let chosen = trimmed.isEmpty ? defaultPath : trimmed
    let expanded =
      chosen == "~" || chosen.hasPrefix("~/")
      ? home + chosen.dropFirst() : chosen.hasPrefix("/") ? chosen : home + "/" + chosen
    return URL(fileURLWithPath: expanded)
  }

  /// `url` as Settings shows it and config.json keeps it, with `~` for the home folder.
  public static func path(for url: URL, home: String = NSHomeDirectory()) -> String {
    url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
  }
}
