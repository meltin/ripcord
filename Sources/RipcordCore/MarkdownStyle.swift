import Foundation

/// Where a note's Markdown asks for a look, so the editor can format it as you type: headings,
/// emphasis, code, quotes, lists, checkboxes and links. Every mark stays in the text, so what's
/// saved is exactly what's typed; as in Raycast Notes, a heading's or emphasis's marks are hidden
/// once complete, and a list's or quote's are shown dimmed.
public struct MarkdownSpan: Equatable, Sendable {
  public enum Style: Equatable, Sendable {
    case heading(Int)
    case bold, italic, strike, underline, code, codeBlock, quote, link
    /// A checked task's text.
    case done
    /// A list's, task's or quote's marks, shown dimmed.
    case mark
    /// A heading's, emphasis's, code's or link's marks, hidden.
    case hidden
  }

  /// UTF-16 offsets, as NSTextView counts them.
  public let range: NSRange
  public let style: Style
  /// A heading's or inline style's hidden marks, so a delete can take them with the text.
  public let marks: [NSRange]

  public init(_ range: NSRange, _ style: Style, marks: [NSRange] = []) {
    self.range = range
    self.style = style
    self.marks = marks
  }

  /// The spans of `text`, line by line; inline styles skip code blocks.
  public static func spans(in text: String) -> [MarkdownSpan] {
    let string = text as NSString
    var spans: [MarkdownSpan] = []
    var inFence = false
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length), options: .byLines
    ) { line, range, _, _ in
      guard let line else { return }
      let isFence = line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
      if isFence || inFence {
        spans.append(MarkdownSpan(range, .codeBlock))
        if isFence { inFence.toggle() }
        return
      }
      spans += lineSpans(line, at: range.location)
    }
    return spans
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
      spans.append(MarkdownSpan(whole, .quote))
      spans.append(MarkdownSpan(shifted(match.range), .mark))
    } else if let match = first(task, in: line) {
      spans.append(MarkdownSpan(shifted(match.range), .mark))
      let checked = (line as NSString).substring(with: match.range(at: 1)).lowercased() == "x"
      let rest = NSRange(
        location: match.range.upperBound, length: whole.length - match.range.upperBound)
      if checked, rest.length > 0 { spans.append(MarkdownSpan(shifted(rest), .done)) }
    } else if let match = first(listItem, in: line) {
      spans.append(MarkdownSpan(shifted(match.range), .mark))
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
        guard !inCode(opening), !inCode(closing) else { continue }
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
  private static let listItem = regex(#"^\s*(?:[-*+]|\d+\.)\s"#)
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
