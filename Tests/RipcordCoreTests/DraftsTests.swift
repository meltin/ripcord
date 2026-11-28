import Foundation
import Testing

@testable import RipcordCore

@Suite struct DraftsTests {
  @Test func listsEachFormLeftUnfinishedFirst() throws {
    let drafts = SavedDrafts(
      snippet: Snippet(name: "", text: "Dear team,\nthanks"),
      bookmark: BookmarkDraftFields(
        title: "", url: "https://swift.org", description: "", group: nil, newGroup: ""))
    let sections = Search.sections(
      for: "", apps: [], quicklinks: [], drafts: drafts)
    #expect(sections.first?.title == "Drafts")
    let rows = try #require(sections.first?.results)
    // Named by what was typed: the name, else the text's first line; the title, else the URL.
    #expect(rows.map(\.title) == ["Create Snippet", "Add Bookmark"])
    #expect(rows.map(\.subtitle) == ["Dear team,", "https://swift.org"])
    #expect(rows[0].kind == .draft)
    #expect(rows[0].actions.map(\.title) == ["Open Draft", "Discard Draft"])
    #expect(rows[0].actions[1].shortcut == "⌃X")
    // No drafts, no section; a query doesn't list them.
    #expect(Search.sections(for: "", apps: [], quicklinks: []).isEmpty)
    #expect(
      !Search.sections(for: "dear", apps: [], quicklinks: [], drafts: drafts)
        .contains { $0.title == "Drafts" })
  }

  @Test func keepsDraftsAcrossLaunches() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    var store = DraftStore(fileURL: file)
    try store.save(SavedDrafts(snippet: Snippet(name: "Hi", text: ""), snippetTags: "work"))
    let read = DraftStore(fileURL: file)
    #expect(read.drafts.snippet?.name == "Hi")
    #expect(read.drafts.snippetTags == "work")
  }
}
