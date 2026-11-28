import Foundation
import Testing

@testable import RipcordCore

@Suite struct RunningApplicationsTests {
  let rex = AppEntry(
    url: URL(fileURLWithPath: "/Applications/Rex.app"), names: ["Rex"], bundleID: "rex")
  let tool = AppEntry(
    url: URL(fileURLWithPath: "/Users/me/Downloads/Tool.app"), names: ["Tool"], bundleID: "tool")

  @Test func listsRunningAppsWithTheirQuitActions() throws {
    let all = Search.runningSections(for: "", running: [rex, tool], scanned: ["rex"])
    #expect(all.map(\.title) == ["Running"])
    #expect(all[0].results.map(\.title) == ["Rex", "Tool"])
    let row = all[0].results[0]
    #expect(row.action == .open(rex.url))
    #expect(row.actions.contains { $0.action == .controlApp("rex", .quit) })
    #expect(row.actions.last?.title == "Disable Command")
    #expect(
      Search.runningSections(for: "too", running: [rex, tool], scanned: [])[0].results
        .map(\.title) == ["Tool"])
    #expect(Search.runningSections(for: "zzqq", running: [rex], scanned: []).isEmpty)
  }

  @Test func listsEachAppOnceWithoutMovingFavorites() throws {
    #expect(
      Search.runningSections(for: "", running: [rex, rex], scanned: ["rex"])[0].results.count == 1)
    // A favorite here can be removed, not moved: Favorites' order isn't shown.
    let favorites = [BuiltinCommand.searchSnippets.settingsKey, "rex"]
    let row = try #require(
      Search.runningSections(for: "", running: [rex], scanned: ["rex"], favorites: favorites)
        .first?.results.first)
    #expect(row.actions.contains { $0.title == "Remove from Favorites" })
    #expect(!row.actions.contains { $0.title.hasPrefix("Move Favorite") })
  }

  @Test func leavesFavoritesAndDisableOffAnUnscannedApp() throws {
    // Settings doesn't list it, so nothing it turns off or pins could be undone there.
    let row = try #require(
      Search.runningSections(for: "tool", running: [tool], scanned: ["rex"]).first?.results.first)
    #expect(
      !row.actions.contains { $0.title == "Disable Command" || $0.title == "Add to Favorites" })
    #expect(row.actions.contains { $0.title == "Restart Application" })
  }
}
