import Foundation

/// How keys move through a command's argument fields beside the search bar, as Raycast's do.
public enum ArgumentFieldNavigation {
  /// The field Tab (or ⇧Tab with `back`) moves to from `field`, where nil is the search field:
  /// every field in turn, dropdowns too, and past either end back to the search field.
  public static func next(from field: Int?, count: Int, back: Bool) -> Int? {
    guard count > 0 else { return nil }
    guard let field else { return back ? count - 1 : 0 }
    let target = back ? field - 1 : field + 1
    return (0..<count).contains(target) ? target : nil
  }

  /// A focused dropdown's value after ↑ or ↓: the next choice in `values` without wrapping,
  /// "" (none chosen) above the first, as Raycast's "-".
  public static func step(_ value: String, in values: [String], up: Bool) -> String {
    let current = values.firstIndex(of: value) ?? -1
    let target = min(max(up ? current - 1 : current + 1, -1), values.count - 1)
    return target < 0 ? "" : values[target]
  }

  /// The choices an open dropdown lists for `filter`: those with a word starting with it,
  /// ignoring case, as Raycast's ("e" finds English, not Japanese).
  public static func matches(_ filter: String, in titles: [String]) -> [Int] {
    let typed = filter.trimmingCharacters(in: .whitespaces)
    guard !typed.isEmpty else { return Array(titles.indices) }
    return titles.indices.filter { index in
      titles[index].split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "(" })
        .contains { $0.range(of: typed, options: [.caseInsensitive, .anchored]) != nil }
    }
  }

  /// Whether typing a space after `previous` should go into the first argument field instead:
  /// `previous` is exactly the selected command's alias, and that command takes arguments.
  public static func spaceEntersFields(
    previous: String, query: String, alias: String?, takesArguments: Bool
  ) -> Bool {
    guard takesArguments, let alias, !alias.isEmpty, query == previous + " " else { return false }
    return previous.caseInsensitiveCompare(alias) == .orderedSame
  }
}
