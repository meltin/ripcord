import Foundation
import Testing

@testable import RipcordCore

@Suite struct SnippetTests {
  @Test func fillsInPlaceholdersAndTheClipboard() {
    let filled = Snippet.expand(
      "On {date} ({day}): {clipboard} {date}", values: ["date": "Nov 26, 2026", "day": "Thursday"],
      clipboard: "copied")
    #expect(
      filled
        == .init(text: "On Nov 26, 2026 (Thursday): copied Nov 26, 2026", charactersAfterCursor: 0))
  }

  @Test func leavesPlaceholdersInsideTheClipboardAlone() {
    let filled = Snippet.expand(
      "{clipboard}", values: ["date": "today"], clipboard: "{date}{cursor}")
    #expect(filled.text == "{date}{cursor}")
  }

  @Test func putsTheCaretAtTheFirstCursor() {
    let filled = Snippet.expand(
      "Hi {cursor}, see {clipboard}{cursor}!", values: [:], clipboard: "this")
    #expect(filled == .init(text: "Hi , see this!", charactersAfterCursor: 11))
  }

  @Test func formatsTheDateTimeDayAndUUID() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-11-26T09:05:00Z"))
    let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let values = Snippet.values(
      at: date, locale: Locale(identifier: "en_US"), timeZone: .gmt, uuid: uuid)
    #expect(values["date"] == "Nov 26, 2026")
    #expect(values["day"] == "Thursday")
    #expect(values["time"]?.hasPrefix("9:05") == true)
    #expect(values["uuid"] == "00000000-0000-0000-0000-000000000001")
  }

  @Test func importsRaycastsExportOnce() throws {
    let raycast = Data(
      #"""
      [{"name": "Address", "text": "1 Infinite Loop", "keyword": "addr"},
       {"name": "Thanks", "text": "Thank you!"}, {"name": "Empty", "text": ""}]
      """#.utf8)
    let first = try Snippet.merging(raycast, into: [Snippet(name: "Thanks", text: "Thank you!")])
    #expect(first.added == 1)
    #expect(first.snippets.map(\.name) == ["Thanks", "Address"])
    #expect(first.snippets[1].keyword == "addr")
    #expect(try Snippet.merging(raycast, into: first.snippets).added == 0)
    let taken = try Snippet.merging(
      raycast, into: [Snippet(name: "Home", text: "x", keyword: "addr")])
    #expect(taken.snippets.first { $0.name == "Address" }?.keyword == nil)
  }

  @Test func exportsWhatImportReads() throws {
    let snippets = [Snippet(name: "Sig", text: "Best,\nMe", keyword: "sig", tags: ["mail"])]
    let data = try Snippet.exportData(snippets)
    #expect(try Snippet.merging(data, into: []).snippets == snippets)
  }

  @Test func readsTagsAsTyped() {
    #expect(Snippet.tags(from: " work, mail ,,work ") == ["work", "mail"])
    #expect(Snippet.tags(from: " , ") == nil)
    #expect(Snippet.tags(from: "仕事、メール，work") == ["仕事", "メール", "work"])
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
    Snippet(name: "Address", text: "1 Infinite Loop", keyword: "addr", icon: "house"),
    Snippet(name: "Greeting", text: "Hello on {date}", keyword: "sig", tags: ["mail"]),
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

  @Test func showsTheChosenIcon() {
    let results = Search.snippetSections(for: "addr", snippets: snippets).flatMap(\.results)
    #expect(results.map(\.symbol) == ["house"])
  }

  @Test func filtersByTag() {
    let titles = Search.snippetSections(for: "", snippets: snippets, tag: "mail")
      .flatMap(\.results).map(\.title)
    #expect(titles == ["Greeting"])
  }

  @Test func findsAndShowsTags() {
    let results = Search.snippetSections(for: "mail", snippets: snippets).flatMap(\.results)
    #expect(results.map(\.title) == ["Greeting"])
    #expect(results.map(\.tags) == [["mail"]])
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

  @Test func offersPasteCopyEditCreateAndDelete() throws {
    let result = try #require(
      Search.snippetSections(for: "Greeting", snippets: snippets).first?.results.first)
    #expect(result.kind.primaryAction == "Paste to App")
    #expect(result.keyword == "sig")
    #expect(result.symbol == "doc")
    #expect(result.actions.map(\.shortcut) == ["↵", "⇧⌘C", "⌘E", "⌘D", "⌘N", "⌃X"])
    #expect(
      result.actions.map(\.action) == [
        .snippet(4, .paste), .snippet(4, .copy), .snippet(4, .edit), .snippet(4, .duplicate),
        .run(.createSnippet),
        .snippet(4, .delete),
      ])
  }

  @Test func theCommandsAreFoundByTyping() {
    #expect(
      Search.results(for: "search snippets", apps: [], quicklinks: []).first?.action
        == .run(.searchSnippets))
    #expect(
      Search.results(for: "create snippet", apps: [], quicklinks: []).first?.action
        == .run(.createSnippet))
  }
}
