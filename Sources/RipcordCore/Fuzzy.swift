/// Case-insensitive subsequence matching that favours word starts and runs of characters.
public enum Fuzzy {
  /// Returns nil when `query` is not a subsequence of `text`. Higher is better.
  /// Tries every place the first character occurs, so "settings" scores "System Settings" on its
  /// second word instead of scattering across "System".
  // shortcut: greedy after the first character ("vsc" still takes the "s" in "Visual"); switch to
  // dynamic programming if rankings feel wrong.
  public static func score(_ query: String, in text: String) -> Int? {
    let needle = query.map { $0.lowercased() }
    let original = Array(text)
    let haystack = original.map { $0.lowercased() }
    guard let first = needle.first else { return 0 }
    return haystack.indices
      .filter { haystack[$0] == first }
      .compactMap { greedyScore(needle, haystack, original, from: $0) }
      .max()
  }

  private static func greedyScore(
    _ needle: [String], _ haystack: [String], _ original: [Character], from start: Int
  ) -> Int? {
    var score = 0
    var next = 0
    var previousMatch = -2
    for index in start..<haystack.count where next < needle.count {
      guard haystack[index] == needle[next] else { continue }
      score += 1
      if index == previousMatch + 1 { score += 5 }
      if isWordStart(original, at: index) { score += 8 }
      previousMatch = index
      next += 1
    }
    return next == needle.count ? score : nil
  }

  private static func isWordStart(_ text: [Character], at index: Int) -> Bool {
    guard index > 0 else { return true }
    let previous = text[index - 1]
    return " -_./".contains(previous) || (previous.isLowercase && text[index].isUppercase)
  }
}
