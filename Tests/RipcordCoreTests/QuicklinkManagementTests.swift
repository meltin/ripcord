import Foundation
import Testing

@testable import RipcordCore

struct QuicklinkManagementTests {
  /// Create Quicklink saves only a named link that opens, its name and keyword its own.
  @Test func checksANewQuicklink() {
    let links = [
      Quicklink(name: "Google", url: "https://google.com/search?q={query}", keyword: "g")
    ]
    func problem(_ name: String, _ link: String, _ keyword: String = "", editing: Int? = nil)
      -> String?
    {
      Quicklink.problem(name: name, link: link, keyword: keyword, among: links, editing: editing)
    }
    #expect(problem("Docs", "https://example.com/{query}") == nil)
    #expect(problem(" ", "https://example.com") != nil)
    #expect(problem("Docs", "") != nil)
    #expect(problem("Docs", "not a link") != nil)
    #expect(problem("Google", "https://example.com") != nil)
    #expect(problem("Docs", "https://example.com", "g") != nil)
    // Saving the one being edited keeps its own name and keyword.
    #expect(problem("Google", "https://google.com", "g", editing: 0) == nil)
  }

  /// Search Quicklinks lists every Quicklink; ⌘K edits, creates and deletes, as Raycast's.
  @Test func listsQuicklinksToManage() {
    let links = [
      Quicklink(name: "Google", url: "https://google.com/search?q={query}", keyword: "g"),
      Quicklink(name: "GitHub", url: "https://github.com/search?q={query}", disabled: true),
    ]
    let all = Search.quicklinkSections(for: "", quicklinks: links).flatMap(\.results)
    #expect(all.map(\.title) == ["Google", "GitHub"])
    // Raycast's names and keys.
    #expect(
      all[0].actions.map(\.title) == [
        "Open Quicklink", "Edit Quicklink", "Duplicate Quicklink", "Copy Name", "Copy Link",
        "Configure Quicklink…", "Create Quicklink", "Delete Quicklink", "Delete All Quicklinks",
      ])
    #expect(
      all[0].actions.map(\.shortcut) == [
        "↵", "⌘E", "⌘D", "⌥⌘C", "⌃⌘C", "⇧⌘,", "⌘N", "⌃X", "⌃⇧X",
      ])
    #expect(all[1].actions[1].action == .editQuicklink(index: 1, name: "GitHub"))
    #expect(all[1].actions[2].action == .duplicateQuicklink(index: 1, name: "GitHub"))
    // The link as written, {query} and all; Configure Quicklink… by the Quicklink's own key.
    #expect(all[0].actions[4].action == .copy("https://google.com/search?q={query}"))
    #expect(all[0].actions[5].action == .configureMenu(links[0].rowID))
    let found = Search.quicklinkSections(for: "hub", quicklinks: links).flatMap(\.results)
    #expect(found.map(\.title) == ["GitHub"])
  }
}

/// Import Quicklinks and Export Quicklinks, in Raycast's file.
struct QuicklinkFileTests {
  /// Raycast's own example reads, its `{argument}` taken as `{query}`, with what Ripcord doesn't
  /// keep left out.
  @Test func importsRaycastsExample() throws {
    let raycast = """
      [
        { "link": "https://duckduckgo.com/?q={argument}", "name": "Search DuckDuckGo" },
        { "openWith": "Finder", "iconName": "folder-16", "link": "~/Downloads", "name": "Downloads" },
        { "link": "https://x.com/search?q={argument name=\\"Query\\"}", "name": "X" }
      ]
      """
    let merged = try Quicklink.merging(Data(raycast.utf8), into: [])
    #expect(merged.added == 3)
    #expect(
      merged.links.map(\.url) == [
        "https://duckduckgo.com/?q={query}", "~/Downloads", "https://x.com/search?q={query}",
      ])
    // A folder opens as one, as in Raycast.
    #expect(merged.links[1].url(for: "")?.isFileURL == true)
    #expect(merged.links[1].url(for: "")?.path == NSHomeDirectory() + "/Downloads")
  }

  /// A Quicklink already here is skipped; a name taken gets a number, a keyword taken is left off.
  @Test func mergesWithoutClashing() throws {
    let current = [Quicklink(name: "Google", url: "https://google.com/?q={query}", keyword: "g")]
    let file = try Quicklink.exportData([
      Quicklink(name: "Google", url: "https://google.com/?q={query}", keyword: "g"),
      Quicklink(name: "Google", url: "https://google.co.jp/?q={query}", keyword: "g"),
    ])
    let merged = try Quicklink.merging(file, into: current)
    #expect(merged.added == 1)
    #expect(merged.skipped == 1)
    #expect(merged.links.last?.name == "Google 2")
    #expect(merged.links.last?.keyword == nil)
  }

  /// What Export writes reads back the same, keywords and all, and says `{argument}` for Raycast.
  @Test func exportsForRaycast() throws {
    let links = [Quicklink(name: "Docs", url: "https://example.com/{query}", keyword: "d")]
    let data = try Quicklink.exportData(links)
    #expect(String(decoding: data, as: UTF8.self).contains("https://example.com/{argument}"))
    #expect(try Quicklink.merging(data, into: []).links == links)
  }
}

/// Pass Selected Text as Argument is off unless set, as Raycast's is.
@Test func readsQuicklinkSettings() throws {
  let empty = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"cmd+space"}"#.utf8))
  #expect(!empty.quicklinkSettings.passSelectedText)
  let on = try JSONDecoder().decode(
    Config.self,
    from: Data(#"{"hotkey":"cmd+space","quicklinkSettings":{"passSelectedText":true}}"#.utf8))
  #expect(on.quicklinkSettings.passSelectedText)
}

/// Snippets and Quicklinks both ask before deleting unless turned off, as Raycast's do.
@Test func warnsBeforeDeletingByDefault() throws {
  let empty = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"cmd+space"}"#.utf8))
  #expect(empty.snippetExpansion.showDeleteWarning)
  #expect(empty.quicklinkSettings.showDeleteWarning)
  let off = try JSONDecoder().decode(
    Config.self,
    from: Data(
      #"{"hotkey":"cmd+space","snippetExpansion":{"showDeleteWarning":false},"quicklinkSettings":{"showDeleteWarning":false}}"#
        .utf8))
  #expect(!off.snippetExpansion.showDeleteWarning)
  #expect(!off.quicklinkSettings.showDeleteWarning)
}
