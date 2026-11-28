import Foundation

/// How often and how recently each app, command, Quicklink and script was opened from the panel,
/// by its item key, for the empty search's Suggestions, as Raycast's.
public struct Ranking: Codable, Equatable, Sendable {
  public struct Use: Codable, Equatable, Sendable {
    public var count: Int
    public var last: Date
  }

  public private(set) var uses: [String: Use] = [:]

  public init(uses: [String: Use] = [:]) { self.uses = uses }

  public mutating func record(_ key: String, at date: Date = .now) {
    uses[key] = Use(count: (uses[key]?.count ?? 0) + 1, last: date)
  }

  /// Reset Ranking: the item leaves Suggestions until it's opened again.
  public mutating func reset(_ key: String) { uses[key] = nil }

  /// The `limit` keys used most, the uses counting half as much for each week since the last,
  /// so what was used a lot long ago gives way.
  /// shortcut: one decay from the last use, not per use; keep a log of uses if this ranks badly.
  public func top(_ limit: Int, among keys: Set<String>, now: Date = .now) -> [String] {
    uses.filter { keys.contains($0.key) }
      .map { key, use in
        let weeks = max(now.timeIntervalSince(use.last), 0) / (7 * 86400)
        return (key: key, score: Double(use.count) * pow(0.5, weeks), last: use.last)
      }
      .sorted { ($0.score, $0.last, $1.key) > ($1.score, $1.last, $0.key) }
      .prefix(limit).map(\.key)
  }
}

/// The ranking, in a JSON file of its own.
public struct RankingStore: Sendable {
  public private(set) var ranking = Ranking()
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
    guard let data = try? Data(contentsOf: fileURL),
      let saved = try? JSONDecoder().decode(Ranking.self, from: data)
    else { return }
    ranking = saved
  }

  /// Writes `new` when it differs, and only then keeps it, so the list matches the file.
  public mutating func save(_ new: Ranking) throws {
    guard new != ranking else { return }
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(new).write(to: fileURL, options: .atomic)
    ranking = new
  }
}
