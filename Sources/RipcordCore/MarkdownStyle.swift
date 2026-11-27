import Foundation

/// Where a note's Markdown asks for a look, so the editor can format it as you type: headings,
/// emphasis, code, quotes, lists, checkboxes and links. Every mark stays in the text, so what's
/// saved is exactly what's typed; as in Raycast Notes, the marks are hidden once complete, and a
/// list's bullet, number or checkbox and a quote's bar are drawn in their place.
public struct MarkdownSpan: Equatable, Sendable {
  public enum Style: Equatable, Sendable {
    case heading(Int)
    case bold, italic, strike, underline, code, codeBlock, quote, link
    /// A list item's line; its mark (`- `, `1. `, with any indent before it) says which.
    case bullet, ordered
    case task(checked: Bool)
    /// A list item's next line, written under its text (Shift-Return): its leading spaces are
    /// its mark, and `level` is its item's.
    case continuation(level: Int)
    /// A closed ``` block, as a whole: its text between the fences, the fences its marks. Each
    /// of its lines is also a `codeBlock`.
    case fenced
    /// A checked task's text.
    case done
    /// The marks, hidden.
    case hidden
  }

  /// UTF-16 offsets, as NSTextView counts them.
  public let range: NSRange
  public let style: Style
  /// A style's hidden marks, so a delete can take them with the text: a line's one at its start,
  /// an inline style's two around it.
  public let marks: [NSRange]

  public init(_ range: NSRange, _ style: Style, marks: [NSRange] = []) {
    self.range = range
    self.style = style
    self.marks = marks
  }

  /// The spans of `text`, line by line; inline styles skip code blocks.
  public static func spans(in text: String) -> [MarkdownSpan] {
    let string = text as NSString
    var lines: [(text: String, range: NSRange, enclosing: NSRange)] = []
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length), options: .byLines
    ) { line, range, enclosing, _ in
      if let line { lines.append((line, range, enclosing)) }
    }
    let fences = lines.indices.filter {
      lines[$0].text.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }
    var spans: [MarkdownSpan] = []
    var inFence = false
    // The list item the lines below may continue: where its text starts, and its level.
    var item: (column: Int, level: Int)?
    for (index, line) in lines.enumerated() {
      let isFence = fences.contains(index)
      if isFence || inFence {
        spans.append(MarkdownSpan(line.range, .codeBlock))
        if isFence { inFence.toggle() }
        item = nil
        continue
      }
      let found = lineSpans(line.text, at: line.range.location)
      if let mark = found.first(where: { isItem($0.style) })?.marks.first {
        let lead = line.text.prefix { $0 == " " || $0 == "\t" }
        item = (mark.length, lead.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2)
      } else if let current = item,
        line.text.prefix(current.column).allSatisfy({ $0 == " " }),
        (line.text as NSString).length >= current.column
      {
        let mark = NSRange(location: line.range.location, length: current.column)
        spans.append(MarkdownSpan(line.range, .continuation(level: current.level), marks: [mark]))
        spans.append(MarkdownSpan(mark, .hidden))
      } else {
        item = nil
      }
      spans += found
    }
    // A closed block's fences are hidden, each with its line break, so no empty line is left;
    // one still open shows its fence, so a lone ``` doesn't turn what follows into hidden code.
    for pair in stride(from: 0, to: fences.count - 1, by: 2) {
      let open = lines[fences[pair]]
      let close = lines[fences[pair + 1]]
      let start = NSMaxRange(open.enclosing)
      let content =
        fences[pair + 1] > fences[pair] + 1
        ? NSRange(location: start, length: NSMaxRange(lines[fences[pair + 1] - 1].range) - start)
        : NSRange(location: start, length: 0)
      let closing = NSRange(
        location: NSMaxRange(content), length: NSMaxRange(close.enclosing) - NSMaxRange(content))
      spans.append(MarkdownSpan(content, .fenced, marks: [open.enclosing, closing]))
      spans.append(MarkdownSpan(open.enclosing, .hidden))
      spans.append(MarkdownSpan(closing, .hidden))
    }
    return spans
  }

  static func isItem(_ style: Style) -> Bool {
    switch style {
    case .bullet, .ordered, .task: true
    default: false
    }
  }

  private static func lineSpans(_ line: String, at start: Int) -> [MarkdownSpan] {
    let whole = NSRange(location: start, length: (line as NSString).length)
    func shifted(_ range: NSRange) -> NSRange {
      NSRange(location: range.location + start, length: range.length)
    }
    var spans: [MarkdownSpan] = []
    if let match = first(heading, in: line) {
      spans.append(
        MarkdownSpan(whole, .heading(match.range(at: 1).length), marks: [shifted(match.range)]))
      spans.append(MarkdownSpan(shifted(match.range), .hidden))
    } else if let match = first(quote, in: line) {
      spans.append(MarkdownSpan(whole, .quote, marks: [shifted(match.range)]))
      spans.append(MarkdownSpan(shifted(match.range), .hidden))
    } else if let match = first(task, in: line) {
      let checked = (line as NSString).substring(with: match.range(at: 1)).lowercased() == "x"
      spans.append(MarkdownSpan(whole, .task(checked: checked), marks: [shifted(match.range)]))
      spans.append(MarkdownSpan(shifted(match.range), .hidden))
      let rest = NSRange(
        location: match.range.upperBound, length: whole.length - match.range.upperBound)
      if checked, rest.length > 0 { spans.append(MarkdownSpan(shifted(rest), .done)) }
    } else if let match = first(listItem, in: line) {
      let ordered = match.range(at: 1).location != NSNotFound
      spans.append(
        MarkdownSpan(whole, ordered ? .ordered : .bullet, marks: [shifted(match.range)]))
      spans.append(MarkdownSpan(shifted(match.range), .hidden))
    }
    // Inline code first: what's inside it isn't emphasis or a link.
    let codes = all(inlineCode, in: line)
    let inCode = { (range: NSRange) in
      codes.contains { NSIntersectionRange($0.range, range).length > 0 }
    }
    for match in codes {
      let open = match.range(at: 1)
      let close = match.range(at: 2)
      spans.append(
        MarkdownSpan(
          shifted(NSRange(location: open.upperBound, length: close.location - open.upperBound)),
          .code, marks: [shifted(open), shifted(close)]))
      spans.append(MarkdownSpan(shifted(open), .hidden))
      spans.append(MarkdownSpan(shifted(close), .hidden))
    }
    // A link's URL isn't emphasis either: `_` and `*` are common in them.
    let urls = all(link, in: line).filter { !inCode($0.range) }.map {
      NSRange(
        location: $0.range(at: 1).upperBound,
        length: $0.range.upperBound - $0.range(at: 1).upperBound)
    }
    let isProtected = { (range: NSRange) in
      inCode(range) || urls.contains { NSIntersectionRange($0, range).length > 0 }
    }
    let emphasis = [
      (boldStars, MarkdownSpan.Style.bold), (boldUnderscores, .bold), (italic, .italic),
      (strike, .strike), (underline, .underline),
    ]
    for (pattern, style) in emphasis {
      for match in all(pattern, in: line) {
        let inner = match.range(at: 2)
        // Marks inside code aren't emphasis; code inside emphasis is fine.
        let opening = NSRange(
          location: match.range.location, length: inner.location - match.range.location)
        let closing = NSRange(
          location: inner.upperBound, length: match.range.upperBound - inner.upperBound)
        guard !isProtected(opening), !isProtected(closing) else { continue }
        spans.append(
          MarkdownSpan(shifted(inner), style, marks: [shifted(opening), shifted(closing)]))
        spans.append(MarkdownSpan(shifted(opening), .hidden))
        spans.append(MarkdownSpan(shifted(closing), .hidden))
      }
    }
    for match in all(link, in: line) where !inCode(match.range) {
      let label = match.range(at: 1)
      let open = shifted(NSRange(location: match.range.location, length: 1))
      let close = shifted(
        NSRange(location: label.upperBound, length: match.range.upperBound - label.upperBound))
      spans.append(MarkdownSpan(shifted(label), .link, marks: [open, close]))
      spans.append(MarkdownSpan(open, .hidden))
      spans.append(MarkdownSpan(close, .hidden))
    }
    return spans
  }

  // Built once, matched per line.
  private static let heading = regex(#"^(#{1,6})\s+"#)
  private static let quote = regex(#"^>\s?"#)
  private static let task = regex(#"^\s*[-*+]\s\[([ xX])\]\s"#)
  /// Group 1 is an ordered item's number.
  private static let listItem = regex(#"^\s*(?:[-*+]|(\d+)\.)\s"#)
  /// `code`: group 1 the opening tick, 2 the closing one; the text between is the code.
  private static let inlineCode = regex(#"(`)[^`]+(`)"#)
  private static let boldStars = regex(#"(\*\*)(?=\S)(.+?)(?<=\S)\*\*"#)
  /// Not inside a word, as in `foo__bar__baz`.
  private static let boldUnderscores = regex(#"(?<!\w)(__)(?=\S)(.+?)(?<=\S)__(?!\w)"#)
  private static let italic = regex(#"(?<![*_\w])([*_])(?=\S)([^*_]+?)(?<=\S)\1(?![*_\w])"#)
  private static let strike = regex(#"(~~)(?=\S)(.+?)(?<=\S)~~"#)
  /// Markdown has no underline; `<u>` is the HTML other editors read as one.
  private static let underline = regex(#"(<u>)(.+?)</u>"#)
  private static let link = regex(#"\[([^\]]+)\]\([^)\s]+\)"#)

  private static func regex(_ pattern: String) -> NSRegularExpression {
    // The patterns are fixed above, so a failure is a programming error.
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      preconditionFailure("Bad Markdown pattern: \(pattern)")
    }
    return regex
  }

  private static func first(_ regex: NSRegularExpression, in line: String) -> NSTextCheckingResult?
  {
    regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
  }

  private static func all(_ regex: NSRegularExpression, in line: String) -> [NSTextCheckingResult] {
    regex.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length))
  }
}
