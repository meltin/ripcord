import Foundation
import Testing

@testable import RipcordCore

@Suite struct RankingTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func ranksByUseAndRecency() {
    var ranking = Ranking()
    for _ in 0..<3 { ranking.record("old", at: now.addingTimeInterval(-28 * 86400)) }
    ranking.record("new", at: now)
    ranking.record("gone", at: now)
    // Three uses four weeks ago count less than one today; keys not listed are left out.
    #expect(ranking.top(5, among: ["old", "new"], now: now) == ["new", "old"])
    #expect(ranking.top(1, among: ["old", "new"], now: now) == ["new"])
    ranking.reset("new")
    #expect(ranking.top(5, among: ["old", "new"], now: now) == ["old"])
  }

  @Test func suggestsFiveLeavingOutFavoritesAndAvoidingQuicklinkRepeats() throws {
    let link = Quicklink(name: "Docs", url: "https://docs.example/?q={query}", keyword: "d")
    let commands = BuiltinCommand.allCases.prefix(6).map(\.settingsKey)
    var ranking = Ranking()
    for (index, key) in commands.enumerated() {
      for _ in 0...index { ranking.record(key, at: now) }
    }
    for _ in 0..<10 { ranking.record(link.rowID, at: now) }
    let sections = Search.sections(
      for: "", apps: [], quicklinks: [link], favorites: [commands[5]], ranking: ranking)
    let suggestions = try #require(sections.first { $0.title == "Suggestions" })
    // The favorite is shown above, not here; five at most; the Quicklink isn't listed twice.
    #expect(suggestions.results.count == 5)
    #expect(!suggestions.results.contains { $0.itemKey == commands[5] })
    #expect(suggestions.results.map(\.itemKey).prefix(2) == [link.rowID, commands[4]])
    #expect(!sections.contains { $0.title == "Quicklinks" })
  }

  @Test func storeKeepsTheRankingAcrossLaunches() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "ranking-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var store = RankingStore(fileURL: url)
    var ranking = store.ranking
    ranking.record("rex", at: now)
    try store.save(ranking)
    #expect(RankingStore(fileURL: url).ranking == ranking)
  }
}
