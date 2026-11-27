import Foundation

/// How the note editor moves and deletes around marks it hides, so they behave as if they
/// weren't in the text, as in Raycast Notes: the caret never rests inside one, and a delete takes
/// visible text, or a whole heading or style once nothing of it is left.
public enum MarkdownEditing {
  static func isContinuation(_ span: MarkdownSpan) -> Bool {
    if case .continuation = span.style { true } else { false }
  }

  static func isHeading(_ span: MarkdownSpan) -> Bool {
    if case .heading = span.style { true } else { false }
  }

  /// A heading, list item, task or quote: a style of the whole line, marked at its start.
  static func isLine(_ span: MarkdownSpan) -> Bool {
    switch span.style {
    case .heading, .bullet, .ordered, .task, .quote, .continuation: true
    default: false
    }
  }

  /// What Return inserts at `caret` in a list item, task or quote: the next one's mark after the
  /// line break (a number one up, a task unchecked), or, on an empty one, the mark taken away to
  /// end the list. Nil elsewhere.
  public static func newline(at caret: Int, in text: String, spans: [MarkdownSpan])
    -> (range: NSRange, replacement: String, caret: Int)?
  {
    let string = text as NSString
    // Return after a lone opening ``` closes the block, with the caret on the line between.
    let line = string.lineRange(for: NSRange(location: caret, length: 0))
    let lineText = string.substring(with: line).trimmingCharacters(in: .newlines)
    let inBlock = spans.contains {
      $0.style == .fenced && $0.marks.contains { NSLocationInRange(line.location, $0) }
    }
    if lineText.trimmingCharacters(in: .whitespaces).hasPrefix("```"), !inBlock,
      caret == line.location + (lineText as NSString).length,
      !string.substring(from: NSMaxRange(line)).contains("```")
    {
      return (NSRange(location: caret, length: 0), "\n\n```", caret + 1)
    }
    guard
      let span = spans.first(where: {
        // A heading's Return is a plain line break.
        isLine($0) && !isHeading($0)
          && NSLocationInRange(
            caret, NSRange(location: $0.range.location, length: $0.range.length + 1))
      }),
      let prefix = span.marks.first, caret >= NSMaxRange(prefix)
    else { return nil }
    // Return on an item's next line starts the next item, as on the item itself.
    if case .continuation = span.style {
      guard
        let owner = spans.last(where: {
          MarkdownSpan.isItem($0.style) && $0.range.location < span.range.location
        }), let ownerMark = owner.marks.first
      else { return nil }
      let next = nextMark(after: string.substring(with: ownerMark), style: owner.style)
      // An empty next line becomes the next item where it is, rather than leaving its spaces.
      if let prefix = span.marks.first, NSMaxRange(span.range) == NSMaxRange(prefix) {
        return (prefix, next, prefix.location + (next as NSString).length)
      }
      let insert = "\n" + next
      return (NSRange(location: caret, length: 0), insert, caret + (insert as NSString).length)
    }
    let mark = string.substring(with: prefix)
    if NSMaxRange(span.range) == NSMaxRange(prefix) {
      return (prefix, "", prefix.location)
    }
    let next = nextMark(after: mark, style: span.style)
    let insert = "\n" + next
    return (NSRange(location: caret, length: 0), insert, caret + (insert as NSString).length)
  }

  /// Tab and Shift-Tab on list items: the lines `selection` touches that are bullets, numbered
  /// or task items move a level in (two spaces) or out. Nil when none of them is an item, so
  /// Tab does what it otherwise does.
  public static func indentItems(
    selection: NSRange, in text: String, spans: [MarkdownSpan], outdent: Bool
  ) -> (range: NSRange, replacement: String, selection: NSRange)? {
    let string = text as NSString
    var range = string.lineRange(for: selection)
    guard
      spans.contains(where: {
        MarkdownSpan.isItem($0.style) && NSLocationInRange($0.range.location, range)
      })
    else { return nil }
    // An item's next lines (Shift-Return) move with it, or they'd fall out of it.
    while NSMaxRange(range) < string.length,
      spans.contains(where: { isContinuation($0) && $0.range.location == NSMaxRange(range) })
    {
      range = NSUnionRange(
        range, string.lineRange(for: NSRange(location: NSMaxRange(range), length: 0)))
    }
    let items = spans.filter {
      (MarkdownSpan.isItem($0.style) || isContinuation($0))
        && NSLocationInRange($0.range.location, range)
    }
    .map(\.range.location)
    var replacement = ""
    var shifts: [(at: Int, by: Int)] = []
    var location = range.location
    while location < NSMaxRange(range) {
      let line = string.lineRange(for: NSRange(location: location, length: 0))
      var text = string.substring(with: line)
      if items.contains(location) {
        if outdent {
          let lead = text.prefix { $0 == " " }.count
          let cut = text.hasPrefix("\t") ? 1 : min(lead, 2)
          text.removeFirst(cut)
          shifts.append((location, -cut))
        } else {
          text = "  " + text
          shifts.append((location, 2))
        }
      }
      replacement += text
      location = NSMaxRange(line)
    }
    // The selection moves with its own line's text; a point inside spaces taken away lands at
    // its line's new start.
    func moved(_ point: Int) -> Int {
      var offset = 0
      for shift in shifts where shift.at <= point {
        if shift.by < 0, point < shift.at - shift.by { return shift.at + offset }
        offset += shift.by
      }
      return point + offset
    }
    let start = moved(selection.location)
    let end = moved(NSMaxRange(selection))
    return (range, replacement, NSRange(location: start, length: max(0, end - start)))
  }

  /// ⌘Return on a task, as in Raycast: its box checked or unchecked. Nil off a task.
  public static func toggleTask(at caret: Int, in text: String, spans: [MarkdownSpan])
    -> (range: NSRange, replacement: String)?
  {
    guard
      let task = spans.first(where: {
        guard case .task = $0.style else { return false }
        return $0.range.location <= caret && caret <= NSMaxRange($0.range)
      }),
      case .task(let checked) = task.style, let mark = task.marks.first
    else { return nil }
    let box = (text as NSString).range(of: "[", range: mark)
    guard box.location != NSNotFound else { return nil }
    return (NSRange(location: box.location + 1, length: 1), checked ? " " : "x")
  }

  /// `- [] ` typed at a line's start, as Raycast takes it, written as Markdown's `- [ ] ` so
  /// the file reads as a task anywhere. Nil when the caret isn't just after one.
  public static func taskShortcut(at caret: Int, in text: String)
    -> (range: NSRange, replacement: String, caret: Int)?
  {
    let string = text as NSString
    let line = string.lineRange(for: NSRange(location: caret, length: 0))
    let typed = string.substring(
      with: NSRange(location: line.location, length: caret - line.location))
    guard typed.range(of: #"^\s*[-*+] \[\] $"#, options: .regularExpression) != nil else {
      return nil
    }
    let box = NSRange(location: caret - 3, length: 2)
    return (box, "[ ]", caret + 1)
  }

  /// The mark the item after one marked `mark` starts with: a number one up, a task unchecked.
  static func nextMark(after mark: String, style: MarkdownSpan.Style) -> String {
    switch style {
    case .ordered:
      let indent = String(mark.prefix { $0 == " " || $0 == "\t" })
      let number = Int(mark.drop { $0 == " " || $0 == "\t" }.prefix { $0.isNumber }) ?? 0
      return "\(indent)\(number + 1). "
    case .task:
      return mark.replacingOccurrences(of: "[x]", with: "[ ]")
        .replacingOccurrences(of: "[X]", with: "[ ]")
    default: return mark
    }
  }

  /// Shift-Return in a list item: a line break inside the item, its next line written under
  /// the item's text, as in most editors. Nil outside a list.
  public static func softBreak(at caret: Int, in text: String, spans: [MarkdownSpan])
    -> (range: NSRange, replacement: String, caret: Int)?
  {
    guard
      let span = spans.first(where: {
        (MarkdownSpan.isItem($0.style) || isContinuation($0))
          && $0.range.location <= caret && caret <= NSMaxRange($0.range)
      }), let mark = span.marks.first
    else { return nil }
    let insert = "\n" + String(repeating: " ", count: mark.length)
    return (NSRange(location: caret, length: 0), insert, caret + (insert as NSString).length)
  }

  /// ↓ on a code block's last line when the block ends the note: a line goes in after its
  /// closing fence for the caret, so it can leave the block. Nil elsewhere.
  public static func leaveBlockDown(at caret: Int, in text: String, spans: [MarkdownSpan])
    -> (range: NSRange, replacement: String, caret: Int)?
  {
    let string = text as NSString
    guard
      let block = spans.first(where: {
        $0.style == .fenced && $0.range.location <= caret && caret <= NSMaxRange($0.range)
      }),
      let closing = block.marks.last, NSMaxRange(closing) == string.length,
      // UTF-16, so a CRLF line end counts too: String sees "\r\n" as one character.
      string.range(
        of: "\n", range: NSRange(location: caret, length: NSMaxRange(block.range) - caret)
      ).location == NSNotFound,
      closing.length == 0 || string.character(at: NSMaxRange(closing) - 1) != 0x0A
    else { return nil }
    return (NSRange(location: string.length, length: 0), "\n", string.length + 1)
  }

  /// ``` typed alone on a line opens a code block straight away, as in Raycast: the closing
  /// fence goes in with an empty line between for the caret. Nil when this ``` would close an
  /// open block instead, or the line holds more.
  public static func codeFenceShortcut(at caret: Int, in text: String)
    -> (range: NSRange, replacement: String, caret: Int)?
  {
    let string = text as NSString
    let line = string.lineRange(for: NSRange(location: caret, length: 0))
    let lineText = string.substring(with: line).trimmingCharacters(in: .newlines)
    guard lineText.trimmingCharacters(in: .whitespaces) == "```",
      caret == line.location + (lineText as NSString).length
    else { return nil }
    // An odd number of fences above means this one closes a block; an odd number below, that
    // it pairs with one left open there. Either way it's a fence of its own, not a new block.
    func fences(_ text: String) -> Int {
      text.components(separatedBy: .newlines)
        .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.count
    }
    guard fences(string.substring(to: line.location)) % 2 == 0,
      fences(string.substring(from: NSMaxRange(line))) % 2 == 0
    else { return nil }
    return (NSRange(location: caret, length: 0), "\n\n```", caret + 1)
  }

  /// A selection made in one go (⌘A, a click and drag) grown over hidden marks at its ends, so
  /// a copy keeps a first line's `# ` or `- `.
  public static func outward(_ range: NSRange, spans: [MarkdownSpan]) -> NSRange {
    let hidden = hidden(in: spans)
    let lineMarks = spans.filter(isLine).compactMap(\.marks.first)
    var start = range.location
    var end = NSMaxRange(range)
    if let mark = hidden.first(where: { $0.location < start && start < NSMaxRange($0) }) {
      start = mark.location
    } else if let mark = lineMarks.first(where: { NSMaxRange($0) == start }) {
      start = mark.location
    }
    if let mark = hidden.first(where: { $0.location < end && end < NSMaxRange($0) }) {
      end = NSMaxRange(mark)
    }
    return NSRange(location: start, length: end - start)
  }

  /// What a delete key does.
  public enum Delete: Equatable, Sendable {
    /// Leave it to the text view.
    case normal
    /// Swallow the key.
    case nothing
    /// Remove these characters instead.
    case remove(NSRange)
  }

  /// The hidden marks, sorted, with any that overlap or touch merged into one.
  public static func hidden(in spans: [MarkdownSpan]) -> [NSRange] {
    let sorted = spans.filter { $0.style == .hidden }.map(\.range)
      .sorted { $0.location < $1.location }
    return sorted.reduce(into: []) { merged, range in
      if let last = merged.last, range.location <= NSMaxRange(last) {
        merged[merged.count - 1] = NSUnionRange(last, range)
      } else {
        merged.append(range)
      }
    }
  }

  /// `text` as the editor shows it, without its hidden marks.
  public static func shown(_ text: String) -> String {
    let shown = NSMutableString(string: text)
    for range in hidden(in: MarkdownSpan.spans(in: text)).reversed() {
      shown.deleteCharacters(in: range)
    }
    return shown as String
  }

  /// Whether the caret may rest at `location`: not on a hidden mark's first character or inside.
  /// It rests after one instead, so what's typed after a heading's `# ` lands in the heading and
  /// what's typed after a closing `**` isn't bold. `stops` are allowed anyway: the end of a code
  /// block's last line, where its closing fence starts.
  static func canRest(at location: Int, hidden: [NSRange], stops: [Int] = []) -> Bool {
    stops.contains(location)
      || !hidden.contains { $0.location <= location && location < NSMaxRange($0) }
  }

  /// Where the caret may rest though a hidden mark starts there: the end of each code block.
  public static func stops(in spans: [MarkdownSpan]) -> [Int] {
    spans.filter { $0.style == .fenced }.compactMap { $0.marks.last?.location }
  }

  /// Where a caret moved from `old` to `proposed` lands. An arrow step into hidden marks carries
  /// on past them to the next visible character; a click or a jump lands after them.
  public static func caret(
    _ proposed: Int, from old: Int, in text: String, hidden: [NSRange], stops: [Int] = []
  ) -> Int {
    let string = text as NSString
    let canRest = { (location: Int) in Self.canRest(at: location, hidden: hidden, stops: stops) }
    guard !canRest(proposed) else { return proposed }
    // Up from below a code block lands at the end of its last line, not past its fence again.
    if proposed < old,
      let stop = stops.first(where: { stop in
        hidden.contains { $0.location == stop && NSLocationInRange(proposed, $0) }
      })
    {
      return stop
    }
    // Up onto a hidden line, a code block's opening fence, carries on to the line above it
    // rather than back down into the block.
    if proposed < old,
      let line = hidden.first(where: {
        NSLocationInRange(proposed, $0) && $0.location > 0
          && string.character(at: NSMaxRange($0) - 1) == 0x0A
          && string.character(at: $0.location - 1) == 0x0A
      })
    {
      return line.location - 1
    }
    if proposed == old - 1 {
      var location = proposed
      while location > 0, !canRest(location) {
        location = string.rangeOfComposedCharacterSequence(at: location - 1).location
      }
      if canRest(location) { return location }
    }
    var location = proposed
    while location < string.length, !canRest(location) {
      location = NSMaxRange(string.rangeOfComposedCharacterSequence(at: location))
    }
    return location
  }

  /// Backspace with the caret at `caret`.
  public static func deleteBackward(at caret: Int, in text: String, spans: [MarkdownSpan])
    -> Delete
  {
    let string = text as NSString
    // At a code block's start: an empty block goes, a written one stays whole.
    if let block = spans.first(where: { $0.style == .fenced && $0.range.location == caret }) {
      guard block.range.length == 0 else { return .nothing }
      return .remove(block.marks.reduce(block.range) { NSUnionRange($0, $1) })
    }
    // At an item's next line's start, it joins the line above, as a soft line break is taken
    // back; its hidden spaces may run on into a style's opening marks, and a CRLF goes whole.
    let merged = hidden(in: spans)
    for span in spans where isContinuation(span) {
      guard let prefix = span.marks.first, prefix.location > 0,
        NSMaxRange(prefix) == caret
          || merged.contains(where: { $0.location == prefix.location && NSMaxRange($0) == caret })
      else { continue }
      let string = text as NSString
      let crlf = prefix.location > 1 && string.character(at: prefix.location - 2) == 0x0D
      let lineBreak = crlf ? 2 : 1
      return .remove(
        NSRange(location: prefix.location - lineBreak, length: prefix.length + lineBreak))
    }
    // At a line style's start: a list item, task or quote goes back to a plain line, and so
    // does an empty heading, while a written one stays, as in Raycast.
    for span in spans where isLine(span) && !isContinuation(span) {
      guard let prefix = span.marks.first, NSMaxRange(prefix) == caret else { continue }
      if case .heading = span.style, NSMaxRange(span.range) != caret { return .nothing }
      return .remove(prefix)
    }
    let hidden = hidden(in: spans)
    var end = caret
    while let mark = hidden.first(where: { NSMaxRange($0) == end && $0.length > 0 }) {
      end = mark.location
    }
    guard end != caret else { return .normal }
    guard end > 0 else { return .nothing }
    return .remove(wholeIfLast(string.rangeOfComposedCharacterSequence(at: end - 1), spans))
  }

  /// Forward delete with the caret at `caret`.
  public static func deleteForward(at caret: Int, in text: String, spans: [MarkdownSpan])
    -> Delete
  {
    let string = text as NSString
    // At a code block's end, its closing fence isn't taken.
    if spans.contains(where: { $0.style == .fenced && $0.marks.last?.location == caret }) {
      return .nothing
    }
    // At the end of a line an item's next line follows: it joins, its hidden spaces with it.
    if caret < string.length {
      let lineBreak =
        string.character(at: caret) == 0x0D && caret + 1 < string.length
          && string.character(at: caret + 1) == 0x0A ? 2 : 1
      if string.character(at: caret) == 0x0A || lineBreak == 2,
        let next = spans.first(where: {
          isContinuation($0) && $0.marks.first?.location == caret + lineBreak
        }), let mark = next.marks.first
      {
        return .remove(NSRange(location: caret, length: lineBreak + mark.length))
      }
    }
    let hidden = hidden(in: spans)
    var start = caret
    while let mark = hidden.first(where: { $0.location == start && $0.length > 0 }) {
      start = NSMaxRange(mark)
    }
    guard start != caret else { return .normal }
    guard start < string.length else { return .nothing }
    return .remove(wholeIfLast(string.rangeOfComposedCharacterSequence(at: start), spans))
  }

  /// `range`, or the whole style with its marks when `range` is all the text it has left, so
  /// deleting it doesn't leave bare `****` behind.
  private static func wholeIfLast(_ range: NSRange, _ spans: [MarkdownSpan]) -> NSRange {
    guard
      let span = spans.first(where: {
        // A code block emptied by Backspace stays, to write in again.
        $0.range == range && $0.marks.count == 2 && $0.style != .fenced
      })
    else { return range }
    return span.marks.reduce(range) { NSUnionRange($0, $1) }
  }

  /// `range` without the hidden marks at its ends.
  static func visible(_ range: NSRange, hidden: [NSRange]) -> NSRange {
    var start = range.location
    var end = NSMaxRange(range)
    while start < end, let mark = hidden.first(where: { NSLocationInRange(start, $0) }) {
      start = NSMaxRange(mark)
    }
    while end > start, let mark = hidden.first(where: { NSLocationInRange(end - 1, $0) }) {
      end = mark.location
    }
    return NSRange(location: start, length: max(0, end - start))
  }

  /// A replacement of `range` with `replacement` (a cut, a word or line delete, typing over a
  /// selection) made to leave no stray marks: a style whose text all goes takes its marks with
  /// it, and one whose text partly stays keeps them. Nil when the edit is fine as it is;
  /// `caret` is where it ends.
  public static func tidy(
    _ range: NSRange, replacement: String, in text: String, spans: [MarkdownSpan]
  ) -> (range: NSRange, replacement: String, caret: Int)? {
    guard range.length > 0 else { return nil }
    let styled = spans.filter { !$0.marks.isEmpty }
    // A style's own text: a line style's is its line after the mark.
    func content(_ span: MarkdownSpan) -> NSRange {
      guard isLine(span), let prefix = span.marks.first else { return span.range }
      return NSRange(
        location: NSMaxRange(prefix), length: NSMaxRange(span.range) - NSMaxRange(prefix))
    }
    // A line's mark goes only with the mark itself in the edit: retyping a heading's words keeps
    // it a heading, as in Raycast.
    let gone = styled.filter {
      let text = content($0)
      let markGoes =
        !isLine($0) || $0.marks.first.map { NSIntersectionRange($0, range) == $0 } == true
      return text.length > 0 && NSIntersectionRange(text, range) == text && markGoes
    }
    let kept = styled.filter { span in !gone.contains { $0.range == span.range } }
    let touched = { (mark: NSRange, region: NSRange) in
      NSIntersectionRange(mark, region).length > 0
    }
    var region = gone.flatMap(\.marks).reduce(range) { NSUnionRange($0, $1) }
    // Marks of styles that stay are kept whole and put back: closing ones before what's typed,
    // opening ones after.
    let closing = kept.compactMap { $0.marks.count == 2 ? $0.marks[1] : nil }
      .filter { touched($0, region) }
    let opening = kept.compactMap(\.marks.first).filter { touched($0, region) }
    region = (closing + opening).reduce(region) { NSUnionRange($0, $1) }
    let string = text as NSString
    let before = closing.sorted { $0.location < $1.location }.map { string.substring(with: $0) }
      .joined()
    let after = opening.sorted { $0.location < $1.location }.map { string.substring(with: $0) }
      .joined()
    guard region != range || !before.isEmpty || !after.isEmpty,
      before + replacement + after != string.substring(with: region) || region == range
    else { return nil }
    return (
      region, before + replacement + after,
      region.location + (before as NSString).length + (replacement as NSString).length
    )
  }

  /// The edit ⌘B and the like make on `selection`: its marks removed when it's already that
  /// style, else added around it, as one replacement so one undo takes it back. With nothing
  /// selected, an empty pair goes in with the caret between, so what's typed next takes the
  /// style. `selection` is then the styled text, or the caret.
  public static func toggle(
    _ style: MarkdownSpan.Style, open: String, close: String, selection: NSRange,
    in text: String, spans: [MarkdownSpan]
  ) -> (range: NSRange, replacement: String, selection: NSRange)? {
    let string = text as NSString
    // A selection that takes in hidden marks at its ends styles the words between them.
    let selection = visible(selection, hidden: hidden(in: spans))
    let openLength = (open as NSString).length
    // ⌘B again at the end of a bold just typed ends it: the caret steps past its closing marks.
    if selection.length == 0,
      let span = spans.first(where: {
        $0.style == style && $0.marks.count == 2 && NSMaxRange($0.range) == selection.location
      })
    {
      return (selection, "", NSRange(location: NSMaxRange(span.marks[1]), length: 0))
    }
    if let span = spans.first(where: {
      $0.style == style && $0.marks.count == 2
        && NSIntersectionRange($0.range, selection) == selection
        && (selection.length > 0 || NSLocationInRange(selection.location, $0.range))
    }) {
      let whole = span.marks.reduce(span.range) { NSUnionRange($0, $1) }
      return (
        whole, string.substring(with: span.range),
        NSRange(location: whole.location, length: span.range.length)
      )
    }
    guard selection.length > 0 else {
      return (
        selection, open + close, NSRange(location: selection.location + openLength, length: 0)
      )
    }
    // Marks go round the words, not the spaces beside them, or they wouldn't read as marks.
    let selected = string.substring(with: selection)
    let trimmed = selected.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
    let lead = (selected as NSString).range(of: trimmed).location
    let words = NSRange(location: selection.location + lead, length: (trimmed as NSString).length)
    return (
      words, open + trimmed + close,
      NSRange(location: words.location + openLength, length: words.length)
    )
  }

  /// What Format as… makes the lines a selection touches.
  public enum LineFormat: Equatable, Sendable {
    case heading(Int)
    case quote, bullet, ordered, task
  }

  /// A heading's, quote's or list item's mark at a line's start, after any indent (group 1).
  private static let linePrefix = try? NSRegularExpression(
    pattern: #"^(\s*)(?:#{1,6}\s+|>\s?|[-*+]\s\[[ xX]\]\s|[-*+]\s|\d+\.\s)"#)

  /// Whether `mark`, without its indent, is `format`'s.
  private static func isMark(_ mark: String, of format: LineFormat) -> Bool {
    let pattern =
      switch format {
      case .heading(let level): "^#{\(level)} $"
      case .quote: #"^> ?$"#
      case .bullet: #"^[-*+] $"#
      case .ordered: #"^\d+\. $"#
      case .task: #"^[-*+] \[[ xX]\] $"#
      }
    return mark.range(of: pattern, options: .regularExpression) != nil
  }

  /// The lines `selection` touches made `format`, or plain when they all are already; another
  /// heading, quote or list mark is swapped for it, as Raycast's Format as… does.
  public static func toggleLines(_ format: LineFormat, selection: NSRange, in text: String)
    -> (range: NSRange, replacement: String, selection: NSRange)
  {
    let string = text as NSString
    let range = string.lineRange(for: selection)
    let block = string.substring(with: range)
    var lines = block.components(separatedBy: "\n")
    // lineRange takes in the last line break; its empty remainder isn't a line.
    let endsWithBreak = block.hasSuffix("\n")
    if endsWithBreak { lines.removeLast() }
    func mark(_ number: Int) -> String {
      switch format {
      case .heading(let level): String(repeating: "#", count: level) + " "
      case .quote: "> "
      case .bullet: "- "
      case .ordered: "\(number). "
      case .task: "- [ ] "
      }
    }
    // A nested item keeps its indent; only the mark after it changes.
    func split(_ line: String) -> (indent: String, mark: String, rest: String) {
      let ns = line as NSString
      guard
        let match = linePrefix?.firstMatch(
          in: line, range: NSRange(location: 0, length: ns.length))
      else {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        return (indent, "", String(line.dropFirst(indent.count)))
      }
      let indent = match.range(at: 1)
      return (
        ns.substring(with: indent),
        ns.substring(
          with: NSRange(
            location: indent.upperBound, length: match.range.upperBound - indent.upperBound)),
        ns.substring(from: match.range.upperBound)
      )
    }
    let written = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let isAlready = !written.isEmpty && written.allSatisfy { isMark(split($0).mark, of: format) }
    var number = 0
    let changed = lines.map { line -> String in
      let (indent, _, rest) = split(line)
      // Blank lines between others stay blank; a lone empty line gets the mark to type after.
      if isAlready || (lines.count > 1 && line.trimmingCharacters(in: .whitespaces).isEmpty) {
        return indent + rest
      }
      number += 1
      return indent + mark(number) + rest
    }
    let replacement = changed.joined(separator: "\n") + (endsWithBreak ? "\n" : "")
    // One line: the caret keeps its place in the text after the mark. More: they stay selected.
    guard lines.count == 1 else {
      return (
        range, replacement,
        NSRange(
          location: range.location,
          length: (replacement as NSString).length - (endsWithBreak ? 1 : 0))
      )
    }
    let shift = (changed[0] as NSString).length - (lines[0] as NSString).length
    let markEnd =
      range.location + (changed[0] as NSString).length
      - (split(changed[0]).rest as NSString).length
    let caret = max(markEnd, selection.location + shift)
    return (range, replacement, NSRange(location: caret, length: selection.length))
  }

  /// The lines `selection` touches put in a ``` code block, or the block it's in taken apart.
  public static func toggleCodeBlock(selection: NSRange, in text: String)
    -> (range: NSRange, replacement: String, selection: NSRange)
  {
    let string = text as NSString
    if let block = MarkdownSpan.spans(in: text).first(where: {
      $0.style == .fenced
        && NSLocationInRange(
          selection.location, NSRange(location: $0.range.location, length: $0.range.length + 1))
    }) {
      // The lines keep the break after the closing fence, if it had one.
      let whole = block.marks.reduce(block.range) { NSUnionRange($0, $1) }
      let keepsBreak = string.substring(with: whole).hasSuffix("\n")
      let body = string.substring(with: block.range)
      return (
        whole, body + (keepsBreak ? "\n" : ""),
        NSRange(location: whole.location, length: (body as NSString).length)
      )
    }
    let lines = string.lineRange(for: selection)
    let inner = string.substring(with: lines)
    let endsWithBreak = inner.hasSuffix("\n")
    let body = endsWithBreak ? String(inner.dropLast()) : inner
    let replacement = "```\n" + body + "\n```" + (endsWithBreak ? "\n" : "")
    return (
      lines, replacement,
      NSRange(location: lines.location + 4, length: (body as NSString).length)
    )
  }
}
