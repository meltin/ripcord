import Foundation
import Testing

@testable import RipcordCore

@Suite struct FavoritesTests {
  let app = AppEntry(
    url: URL(fileURLWithPath: "/Applications/Rex.app"), names: ["Rex"], bundleID: "rex")
  let link = Quicklink(name: "Docs", url: "https://docs.example/?q={query}", keyword: "d")

  func root(_ favorites: [String]) -> [SearchSection] {
    Search.sections(
      for: "", apps: [app], running: [app], quicklinks: [link], favorites: favorites)
  }

  @Test func listsFavoritesFirstInTheirOrderAndNotAgain() {
    let snippets = BuiltinCommand.searchSnippets.settingsKey
    let sections = root([snippets, app.settingsKey])
    #expect(sections.map(\.title) == ["Favorites", "Quicklinks"])
    #expect(sections[0].results.map(\.title) == ["Search Snippets", "Rex"])
    // Nothing favorited: no section.
    #expect(root([]).map(\.title) == ["Running", "Quicklinks"])
    // A key that's gone (an app uninstalled) is skipped.
    #expect(root(["app:/Gone.app"]).map(\.title) == ["Running", "Quicklinks"])
  }

  @Test func offersRaycastsFavoriteActions() throws {
    let rex = try #require(root([]).first?.results.first)
    let add = try #require(rex.actions.first { $0.title == "Add to Favorites" })
    #expect(add.shortcut == "⇧⌘F")
    #expect(rex.actions.last?.title == "Configure Command…")
    #expect(rex.actions.first { $0.title == "Show in Finder" }?.shortcut == "⌘↵")
    let snippets = BuiltinCommand.searchSnippets.settingsKey
    let favorites = try #require(root([snippets, app.settingsKey]).first?.results)
    #expect(
      favorites[0].actions.map(\.title).suffix(3) == [
        "Remove from Favorites", "Move Favorite Down", "Configure Command…",
      ])
    #expect(
      favorites[1].actions.map(\.title).suffix(3) == [
        "Remove from Favorites", "Move Favorite Up", "Configure Command…",
      ])
    #expect(favorites[1].actions.first { $0.title == "Move Favorite Up" }?.shortcut == "⌥⌘↑")
  }

  @Test func togglesAndMoves() {
    #expect(Search.togglingFavorite("a", in: ["b"]) == ["b", "a"])
    #expect(Search.togglingFavorite("b", in: ["a", "b"]) == ["a"])
    #expect(Search.movingFavorite("c", by: -1, in: ["a", "b", "c"]) == ["a", "c", "b"])
    #expect(Search.movingFavorite("a", by: -1, in: ["a", "b"]) == ["a", "b"])
    #expect(Search.movingFavorite("a", by: 1, in: ["a", "b"]) == ["b", "a"])
  }

  @Test func searchResultsOfferFavoritesToo() throws {
    let found = Search.results(
      for: "rex", apps: [app], quicklinks: [], favorites: [app.settingsKey])
    #expect(found.first?.actions.contains { $0.title == "Remove from Favorites" } == true)
  }

  @Test func readsAConfigWithoutFavorites() throws {
    let data = Data(#"{"hotkey": "ctrl+space", "quicklinks": []}"#.utf8)
    #expect(try JSONDecoder().decode(Config.self, from: data).favorites == [])
  }
}
