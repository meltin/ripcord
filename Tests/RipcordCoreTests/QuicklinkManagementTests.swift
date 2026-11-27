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
    #expect(
      all[0].actions.map(\.title) == [
        "Open Quicklink", "Edit Quicklink", "Create Quicklink", "Delete Quicklink",
      ])
    #expect(all[1].actions[1].action == .editQuicklink(index: 1, name: "GitHub"))
    let found = Search.quicklinkSections(for: "hub", quicklinks: links).flatMap(\.results)
    #expect(found.map(\.title) == ["GitHub"])
  }
}
