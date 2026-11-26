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

  /// Tags typed as "work, mail" (or with 、 and ，, as a Japanese input method types commas):
  /// trimmed, blanks and repeats dropped, nil when none are left.
  public static func tags(from text: String) -> [String]? {
    let tags = text.split(whereSeparator: { ",、，".contains($0) }).map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    .filter { !$0.isEmpty }
    let unique = tags.enumerated().filter { tags.prefix($0.offset).contains($0.element) == false }
      .map(\.element)
    return unique.isEmpty ? nil : unique
  }

  /// A snippet filled in, and how far back from its end the caret goes for `{cursor}`.
  public struct Expansion: Equatable, Sendable {
    public let text: String
    public let charactersAfterCursor: Int
  }

  /// `{name}` placeholders replaced by `values` (date, time, datetime, day, uuid) and
  /// `{clipboard}` by `clipboard`, which goes in last so placeholders inside what was copied stay
  /// as they were. The first `{cursor}` marks where the caret ends up; others are dropped.
  public static func expand(_ text: String, values: [String: String], clipboard: String)
    -> Expansion
  {
    func fill(_ part: String) -> String {
      let filled = values.reduce(part.replacingOccurrences(of: "{cursor}", with: "")) {
        $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value)
      }
      return filled.replacingOccurrences(of: "{clipboard}", with: clipboard)
    }
    guard let marker = text.range(of: "{cursor}") else {
      return Expansion(text: fill(text), charactersAfterCursor: 0)
    }
    let after = fill(String(text[marker.upperBound...]))
    return Expansion(
      text: fill(String(text[..<marker.lowerBound])) + after, charactersAfterCursor: after.count)
  }

  /// What the placeholders other than `{clipboard}` stand for at `date`.
  public static func values(
    at date: Date, locale: Locale = .current, timeZone: TimeZone = .current, uuid: UUID = UUID()
  ) -> [String: String] {
    func style(_ format: Date.FormatStyle) -> String {
      var format = format
      format.locale = locale
      format.timeZone = timeZone
      return date.formatted(format)
    }
    return [
      "date": style(.init(date: .abbreviated, time: .omitted)),
      "time": style(.init(date: .omitted, time: .shortened)),
      "datetime": style(.init(date: .abbreviated, time: .shortened)),
      "day": style(.init().weekday(.wide)),
      "uuid": uuid.uuidString,
    ]
  }

  /// Snippets as a JSON file in Raycast's shape: name, text and keyword, which Raycast reads,
  /// plus Ripcord's icon and tags.
  public static func exportData(_ snippets: [Snippet]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(snippets)
  }

  /// `imported` added after `current`, leaving out any already there with the same name and
  /// text, so importing a file twice adds nothing. A Raycast export reads as is.
  public static func merging(_ data: Data, into current: [Snippet]) throws -> (
    snippets: [Snippet], added: Int
  ) {
    let imported = try JSONDecoder().decode([Snippet].self, from: data)
    let new = imported.reduce(into: [Snippet]()) { kept, snippet in
      let all = current + kept
      guard !snippet.text.isEmpty,
        !all.contains(where: { $0.name == snippet.name && $0.text == snippet.text })
      else { return }
      // A keyword already in use stays with the snippet that had it.
      var added = snippet
      if let keyword = snippet.keyword, all.contains(where: { $0.keyword == keyword }) {
        added.keyword = nil
      }
      kept += [added]
    }
    return (current + new, new.count)
  }
}
