import Foundation
import Testing

@testable import RipcordCore

@Suite struct SnippetTests {
  @Test func fillsInTheDateAndTheClipboard() {
    let text = Snippet.expand(
      "On {date}: {clipboard} ({date})", date: "Nov 26, 2026", clipboard: "copied")
    #expect(text == "On Nov 26, 2026: copied (Nov 26, 2026)")
  }

  @Test func leavesPlaceholdersInsideTheClipboardAlone() {
    #expect(Snippet.expand("{clipboard}", date: "today", clipboard: "{date}") == "{date}")
  }

  @Test func readsConfigsWrittenBeforeSnippetsExisted() throws {
    let data = Data(#"{"hotkey": "ctrl+space", "quicklinks": []}"#.utf8)
    #expect(try JSONDecoder().decode(Config.self, from: data).snippets == [])
  }

  @Test func savesSnippetsAndReadsThemBack() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString).appending(path: "config.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var config = Config.default
    config.snippets = [
      Snippet(name: "Address", text: "1 Infinite Loop\nCupertino", keyword: "addr")
    ]
    try config.save(to: url)
    #expect(try Config.load(from: url) == config)
  }
}

@Suite struct SnippetSearchTests {
  let snippets = [
    Snippet(name: "Signature", text: "Best,\nMe"),
    Snippet(name: "", text: ""),
    Snippet(name: "", text: "No name yet"),
    Snippet(name: "Address", text: "1 Infinite Loop", keyword: "addr"),
    Snippet(name: "Greeting", text: "Hello on {date}", keyword: "sig"),
  ]

  @Test func listsSnippetsWithTextByName() throws {
    let sections = Search.snippetSections(for: "", snippets: snippets)
    #expect(sections.map(\.title) == ["Snippets"])
    #expect(
      sections[0].results.map(\.title) == ["Address", "Greeting", "Signature", "Untitled Snippet"])
    // By position, so an unnamed new snippet can't collide with another.
    #expect(
      sections[0].results.map(\.id) == ["snippet:3", "snippet:4", "snippet:0", "snippet:2"])
  }

  @Test func findsByNameKeywordOrText() {
    func titles(_ query: String) -> [String] {
      Search.snippetSections(for: query, snippets: snippets).flatMap(\.results).map(\.title)
    }
    #expect(titles("addr") == ["Address"])
    #expect(titles("infinite") == ["Address"])
    #expect(titles("nothing") == [])
  }

  @Test func putsAnExactKeywordFirst() {
    let results = Search.snippetSections(for: "sig", snippets: snippets).flatMap(\.results)
    #expect(results.map(\.title) == ["Greeting", "Signature"])
  }

  @Test func pastesOrCopiesTheSavedText() throws {
    let result = try #require(
      Search.snippetSections(for: "Greeting", snippets: snippets).first?.results.first)
    #expect(result.kind.primaryAction == "Paste to App")
    #expect(result.keyword == "sig")
    #expect(result.actions.map(\.shortcut) == ["↵", "⇧⌘C"])
    #expect(
      result.actions.map(\.action) == [
        .snippet("Hello on {date}", .paste), .snippet("Hello on {date}", .copy),
      ])
  }

  @Test func theCommandIsFoundByTyping() {
    let results = Search.results(for: "snippets", apps: [], quicklinks: [])
    #expect(results.first?.action == .run(.searchSnippets))
  }
}
