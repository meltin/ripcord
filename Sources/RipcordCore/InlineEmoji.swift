import Foundation

/// Raycast's inline emoji picker: `:` and a word typed in a text field offer the emoji it names.
public enum InlineEmoji {
  /// The `:word` that ends at `caret` (a UTF-16 offset): a colon at the start or after a space
  /// or punctuation, then two or more letters, digits, `_`, `+` or `-`. Its range, colon and
  /// all, in UTF-16 units, and the word; nil when the caret isn't at the end of one.
  public static func token(in text: String, caret: Int) -> (range: NSRange, word: String)? {
    let units = Array(text.utf16)
    guard caret <= units.count else { return nil }
    var start = caret
    while start > 0, let scalar = Unicode.Scalar(units[start - 1]),
      CharacterSet.alphanumerics.contains(scalar) || "_+-".unicodeScalars.contains(scalar)
    {
      start -= 1
    }
    guard start > 0, units[start - 1] == UInt16(UInt8(ascii: ":")), caret - start >= 2 else {
      return nil
    }
    let colon = start - 1
    // "12:30" or "http://": the colon belongs to the text before it.
    if colon > 0, let before = Unicode.Scalar(units[colon - 1]),
      !CharacterSet.whitespacesAndNewlines.contains(before)
        && !CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: ":"))
          .contains(before)
    {
      return nil
    }
    let word = String(utf16CodeUnits: Array(units[start..<caret]), count: caret - start)
    return (NSRange(location: colon, length: caret - colon), word)
  }

  /// The emoji `word` names, best first, as Search Emoji & Symbols ranks them.
  public static func suggestions(for word: String, catalog: EmojiCatalog, limit: Int = 8)
    -> [(character: String, name: String)]
  {
    let none = EmojiHistory(fileURL: URL(fileURLWithPath: "/dev/null/none"))
    return Search.emojiSections(for: word, catalog: catalog, history: none)
      .flatMap(\.results).prefix(limit)
      .compactMap { result in result.subtitle.isEmpty ? nil : (result.subtitle, result.title) }
  }
}
