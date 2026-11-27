import Foundation

/// How the note editor moves and deletes around marks it hides, so they behave as if they
/// weren't in the text, as in Raycast Notes: the caret never rests inside one, and a delete takes
/// visible text, or a whole heading or style once nothing of it is left.
public enum MarkdownEditing {
  /// What a delete key does.
  public enum Delete: Equatable, Sendable {
    /// Leave it to the text view.
    case normal
    /// Swallow the key.
    case nothing
    /// Remove these characters instead.
    case remove(NSRange)
  }

  /// The hidden marks, sorted.
  public static func hidden(in spans: [MarkdownSpan]) -> [NSRange] {
    spans.filter { $0.style == .hidden }.map(\.range).sorted { $0.location < $1.location }
  }

  /// Whether the caret may rest at `location`: not on a hidden mark's first character or inside.
  /// It rests after one instead, so what's typed after a heading's `# ` lands in the heading and
  /// what's typed after a closing `**` isn't bold.
  static func canRest(at location: Int, hidden: [NSRange]) -> Bool {
    !hidden.contains { $0.location <= location && location < NSMaxRange($0) }
  }

  /// Where a caret moved from `old` to `proposed` lands. An arrow step into hidden marks carries
  /// on past them to the next visible character; a click or a jump lands after them.
  public static func caret(
    _ proposed: Int, from old: Int, in text: String, hidden: [NSRange]
  ) -> Int {
    let string = text as NSString
    guard !canRest(at: proposed, hidden: hidden) else { return proposed }
    if proposed == old - 1 {
      var location = proposed
      while location > 0, !canRest(at: location, hidden: hidden) {
        location = string.rangeOfComposedCharacterSequence(at: location - 1).location
      }
      if canRest(at: location, hidden: hidden) { return location }
    }
    var location = proposed
    while location < string.length, !canRest(at: location, hidden: hidden) {
      location = NSMaxRange(string.rangeOfComposedCharacterSequence(at: location))
    }
    return location
  }

  /// Backspace with the caret at `caret`.
  public static func deleteBackward(at caret: Int, in text: String, spans: [MarkdownSpan])
    -> Delete
  {
    let string = text as NSString
    // At a heading's start: an empty one goes back to a plain line, a written one stays.
    for span in spans {
      guard case .heading = span.style, let prefix = span.marks.first,
        NSMaxRange(prefix) == caret
      else { continue }
      return NSMaxRange(span.range) == caret ? .remove(prefix) : .nothing
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
        $0.range == range && $0.marks.count == 2 && $0.style != .codeBlock
      })
    else { return range }
    return span.marks.reduce(range) { NSUnionRange($0, $1) }
  }

  /// The edit ⌘B and the like make on `selection`: its marks removed when it's already that
  /// style, else added around it, as one replacement so one undo takes it back. Nil when there's
  /// nothing to style; `selection` is then the styled text.
  public static func toggle(
    _ style: MarkdownSpan.Style, mark: String, selection: NSRange, in text: String,
    spans: [MarkdownSpan]
  ) -> (range: NSRange, replacement: String, selection: NSRange)? {
    let string = text as NSString
    guard selection.length > 0 else { return nil }
    if let span = spans.first(where: {
      $0.style == style && $0.marks.count == 2
        && NSIntersectionRange($0.range, selection) == selection
    }) {
      let whole = span.marks.reduce(span.range) { NSUnionRange($0, $1) }
      return (
        whole, string.substring(with: span.range),
        NSRange(location: whole.location, length: span.range.length)
      )
    }
    // Marks go round the words, not the spaces beside them, or they wouldn't read as marks.
    let selected = string.substring(with: selection)
    let trimmed = selected.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
    let lead = (selected as NSString).range(of: trimmed).location
    let words = NSRange(location: selection.location + lead, length: (trimmed as NSString).length)
    return (
      words, mark + trimmed + mark,
      NSRange(location: words.location + (mark as NSString).length, length: words.length)
    )
  }
}
