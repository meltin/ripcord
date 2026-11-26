import Foundation

/// Saved text that Search Snippets pastes into the frontmost app.
public struct Snippet: Codable, Equatable, Sendable {
  public var name: String
  /// `{date}` and `{clipboard}` are filled in when it's pasted or copied.
  public var text: String
  /// Typed in Search Snippets, it puts the snippet first; #7 will expand it in any app.
  public var keyword: String?
  /// An SF Symbols name shown on its row; nil for a plain document.
  public var icon: String?
  /// Words to find it by in Search Snippets; nil rather than empty, so the file stays short.
  public var tags: [String]?

  public init(
    name: String, text: String, keyword: String? = nil, icon: String? = nil, tags: [String]? = nil
  ) {
    self.name = name
    self.text = text
    self.keyword = keyword
    self.icon = icon
    self.tags = tags
  }

  /// Tags typed as "work, mail": trimmed, blanks and repeats dropped, nil when none are left.
  public static func tags(from text: String) -> [String]? {
    let tags = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    let unique = tags.enumerated().filter { tags.prefix($0.offset).contains($0.element) == false }
      .map(\.element)
    return unique.isEmpty ? nil : unique
  }

  /// The text with `{date}` as `date` and `{clipboard}` as `clipboard`. The clipboard goes in
  /// last, so a `{date}` inside what was copied is left as it was.
  public static func expand(_ text: String, date: String, clipboard: String) -> String {
    text.replacingOccurrences(of: "{date}", with: date)
      .replacingOccurrences(of: "{clipboard}", with: clipboard)
  }
}
