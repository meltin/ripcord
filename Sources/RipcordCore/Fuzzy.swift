/// Case-insensitive subsequence matching that favours word starts and runs of characters.
public enum Fuzzy {
  /// Returns nil when `query` is not a subsequence of `text`. Higher is better.
  // shortcut: greedy left-most matching can miss a better alignment ("vsc" takes the "s" in
  // "Visual"); switch to dynamic programming if rankings feel wrong.
  public static func score(_ query: String, in text: String) -> Int? {
    let needle = query.map { $0.lowercased() }
    let original = Array(text)
    let haystack = original.map { $0.lowercased() }
    guard !needle.isEmpty else { return 0 }

    var score = 0
    var next = 0
    var previousMatch = -2
    for (index, character) in haystack.enumerated() where next < needle.count {
      guard character == needle[next] else { continue }
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
