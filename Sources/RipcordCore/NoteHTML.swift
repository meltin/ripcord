import Foundation

/// A note's Markdown as HTML, for Copy Note As… › HTML: headings, paragraphs, lists and tasks,
/// quotes and code blocks, with bold, italic, strikethrough, code and links inside them. Only
/// what Ripcord Notes writes; anything else is kept as text.
public enum NoteHTML {
  public static func html(fromMarkdown text: String) -> String {
    var out: [String] = []
    var paragraph: [String] = []
    var list: (tag: String, items: [String])?
    var code: [String]?

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      out.append("<p>\(paragraph.map(inline).joined(separator: "<br>"))</p>")
      paragraph = []
    }
    func flushList() {
      guard let open = list else { return }
      out.append("<\(open.tag)>\(open.items.map { "<li>\($0)</li>" }.joined())</\(open.tag)>")
      list = nil
    }
    func item(_ tag: String, _ html: String) {
      flushParagraph()
      if list?.tag != tag { flushList() }
      list = (tag, (list?.items ?? []) + [html])
    }

    for line in text.components(separatedBy: "\n") {
      if var lines = code {
        if line.hasPrefix("```") {
          out.append("<pre><code>\(lines.map(escape).joined(separator: "\n"))</code></pre>")
          code = nil
        } else {
          lines.append(line)
          code = lines
        }
        continue
      }
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        flushParagraph()
        flushList()
        code = []
      } else if trimmed.isEmpty {
        flushParagraph()
        flushList()
      } else if let heading = trimmed.wholeMatch(of: /(#{1,6})\s+(.*)/) {
        flushParagraph()
        flushList()
        let level = heading.1.count
        out.append("<h\(level)>\(inline(String(heading.2)))</h\(level)>")
      } else if let task = trimmed.wholeMatch(of: /[-*+]\s+\[([ xX])\]\s+(.*)/) {
        let checked = task.1 != " " ? " checked" : ""
        item("ul", "<input type=\"checkbox\" disabled\(checked)> \(inline(String(task.2)))")
      } else if let bullet = trimmed.wholeMatch(of: /[-*+]\s+(.*)/) {
        item("ul", inline(String(bullet.1)))
      } else if let numbered = trimmed.wholeMatch(of: /\d+[.)]\s+(.*)/) {
        item("ol", inline(String(numbered.1)))
      } else if let quote = trimmed.wholeMatch(of: />\s?(.*)/) {
        flushParagraph()
        flushList()
        out.append("<blockquote>\(inline(String(quote.1)))</blockquote>")
      } else {
        flushList()
        paragraph.append(trimmed)
      }
    }
    if let lines = code {
      out.append("<pre><code>\(lines.map(escape).joined(separator: "\n"))</code></pre>")
    }
    flushParagraph()
    flushList()
    return out.joined(separator: "\n")
  }

  /// Bold, italic, strikethrough, code and links in one line, the rest escaped.
  static func inline(_ text: String) -> String {
    var html = escape(text)
    html = html.replacing(/`([^`]+)`/) { "<code>\($0.1)</code>" }
    html = html.replacing(/\[([^\]]+)\]\(([^)\s]+)\)/) { "<a href=\"\($0.2)\">\($0.1)</a>" }
    html = html.replacing(/\*\*([^*]+)\*\*/) { "<strong>\($0.1)</strong>" }
    html = html.replacing(/~~([^~]+)~~/) { "<del>\($0.1)</del>" }
    // After bold, so the stars left are italic's.
    html = html.replacing(/\*([^*\s][^*]*)\*/) { "<em>\($0.1)</em>" }
    return html
  }

  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
}
