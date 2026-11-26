import Foundation

/// Saved text that Search Snippets pastes into the frontmost app.
public struct Snippet: Codable, Equatable, Sendable {
  public var name: String
  /// `{date}` and `{clipboard}` are filled in when it's pasted or copied.
  public var text: String
  /// Typed in Search Snippets, it puts the snippet first; #7 will expand it in any app.
  public var keyword: String?

  public init(name: String, text: String, keyword: String? = nil) {
    self.name = name
    self.text = text
    self.keyword = keyword
  }

  /// The text with `{date}` as `date` and `{clipboard}` as `clipboard`. The clipboard goes in
  /// last, so a `{date}` inside what was copied is left as it was.
  public static func expand(_ text: String, date: String, clipboard: String) -> String {
    text.replacingOccurrences(of: "{date}", with: date)
      .replacingOccurrences(of: "{clipboard}", with: clipboard)
  }
}
