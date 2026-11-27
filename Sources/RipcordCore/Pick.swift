import Foundation

extension Search {
  /// `ripcord pick`'s rows: every line in order, or the ones `query` fuzzily matches, best first.
  /// A row's id is the line's index, so two equal lines can each be picked.
  public static func pickSections(for query: String, items: [String]) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let indices =
      trimmed.isEmpty
      ? Array(items.indices)
      : items.indices.compactMap { index in
        Fuzzy.score(trimmed, in: items[index]).map { (index: index, score: $0) }
      }
      .sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }
      .map(\.index)
    let results = indices.map { index in
      SearchResult(
        // Only shown cut short: Return gives the line back whole.
        id: "pick:\(index)", title: String(items[index].prefix(500)), subtitle: "",
        keyword: nil, kind: .line, action: .pick(index))
    }
    return results.isEmpty ? [] : [SearchSection(title: "Lines", results: results)]
  }
}
