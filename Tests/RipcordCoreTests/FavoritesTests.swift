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
    #expect(rex.actions.suffix(2).map(\.title) == ["Configure Command…", "Disable Command"])
    #expect(rex.actions.first { $0.title == "Show in Finder" }?.shortcut == "⌘↵")
    let snippets = BuiltinCommand.searchSnippets.settingsKey
    let favorites = try #require(root([snippets, app.settingsKey]).first?.results)
    #expect(
      favorites[0].actions.map(\.title).suffix(4) == [
        "Remove from Favorites", "Move Favorite Down", "Configure Command…", "Disable Command",
      ])
    // An app's go before its Copy Path, as Raycast's.
    #expect(
      favorites[1].actions.map(\.title)[4...6] == [
        "Remove from Favorites", "Move Favorite Up", "Copy Path",
      ])
    #expect(favorites[1].actions.first { $0.title == "Move Favorite Up" }?.shortcut == "⌥⌘↑")
  }

  @Test func togglesAndMoves() {
    #expect(Search.togglingFavorite("a", in: ["b"]) == ["b", "a"])
    #expect(Search.togglingFavorite("b", in: ["a", "b"]) == ["a"])
    #expect(Search.swappingFavorite("c", with: "b", in: ["a", "b", "c"]) == ["a", "c", "b"])
    // A hidden key between them stays where it is.
    #expect(Search.swappingFavorite("c", with: "a", in: ["a", "gone", "c"]) == ["c", "gone", "a"])
  }

  @Test func hidesAndSkipsWhatCantBeListed() throws {
    let snippets = BuiltinCommand.searchSnippets.settingsKey
    // Gone first and written twice: neither shows nor takes a place.
    let favorites = try #require(
      root(["app:/Gone.app", snippets, snippets, app.settingsKey]).first?.results)
    #expect(favorites.map(\.title) == ["Search Snippets", "Rex"])
    #expect(!favorites[0].actions.contains { $0.title == "Move Favorite Up" })
    #expect(
      favorites[1].actions.first { $0.title == "Move Favorite Up" }?.action
        == .moveFavorite(app.settingsKey, swappingWith: snippets))
    // A running app the index never scanned stays under Running, where it can be removed.
    let elsewhere = AppEntry(
      url: URL(fileURLWithPath: "/Users/me/Downloads/Tool.app"), names: ["Tool"], bundleID: "tool")
    let sections = Search.sections(
      for: "", apps: [app], running: [elsewhere], quicklinks: [], favorites: [elsewhere.settingsKey]
    )
    #expect(sections.map(\.title) == ["Running"])
    // Settings can't turn it back on, so it can't be turned off here; a scanned one can.
    #expect(sections[0].results[0].actions.allSatisfy { $0.title != "Disable Command" })
    #expect(root([]).first?.results.first?.actions.last?.title == "Disable Command")
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
