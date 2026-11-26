import Foundation
import Testing

@testable import RipcordCore

@Suite struct BookmarksTests {
  let text = """
    Links I keep.

    # Docs
    - [Swift](https://swift.org) - The language
    - [Bar](https://en.wikipedia.org/wiki/Bar_(law))
    not a bookmark
    - [](https://empty.example)

    ## Tools
    * [Raycast](https://raycast.com)
    """

  @Test func readsBookmarksUnderTheirHeadings() {
    let bookmarks = BookmarkFile(text: text).bookmarks
    #expect(bookmarks.map(\.title) == ["Swift", "Bar", "Raycast"])
    #expect(bookmarks.map(\.group) == ["Docs", "Docs", "Tools"])
    #expect(bookmarks[0].description == "The language")
    #expect(bookmarks[1].url.absoluteString == "https://en.wikipedia.org/wiki/Bar_(law)")
    #expect(bookmarks[1].description == nil)
  }

  @Test func givesTheTextBackByteForByte() {
    for sample in [text, text + "\n", text.replacingOccurrences(of: "\n", with: "\r\n"), ""] {
      #expect(BookmarkFile(text: sample).text == sample)
    }
  }

  @Test func deletesOnlyTheBookmarksLine() throws {
    for ending in ["\n", "\r\n"] {
      let sample = text.replacingOccurrences(of: "\n", with: ending)
      let file = BookmarkFile(text: sample)
      let bar = try #require(file.bookmarks.first { $0.title == "Bar" })
      let after = try #require(file.deleting(line: bar.line, text: bar.text))
      #expect(after.text == sample.replacingOccurrences(of: bar.text + ending, with: ""))
      // The last line, which has no newline, leaves the one before it without one too.
      let raycast = try #require(file.bookmarks.last)
      let withoutLast = try #require(file.deleting(line: raycast.line, text: raycast.text))
      #expect(withoutLast.text == sample.replacingOccurrences(of: ending + raycast.text, with: ""))
    }
  }

  @Test func refusesToDeleteALineThatChanged() {
    let file = BookmarkFile(text: text)
    let swift = file.bookmarks[0]
    #expect(file.deleting(line: swift.line, text: "- [Other](https://other.example)") == nil)
    #expect(file.deleting(line: 99, text: swift.text) == nil)
  }

  @Test func readsMarkdownAsWrittenByHand() {
    let file = BookmarkFile(
      text: """
        \u{FEFF}# Read ##
        - [x] [Done](https://done.example)
        - [ ] [Later](https://later.example "A tip")
        ```
        # not a heading
        - [Code](https://code.example)
        ```
        #\tTools
        - [Raycast](https://raycast.com)
        """)
    #expect(file.bookmarks.map(\.title) == ["Done", "Later", "Raycast"])
    #expect(file.bookmarks.map(\.group) == ["Read", "Read", "Tools"])
    #expect(file.bookmarks[1].url.absoluteString == "https://later.example")
  }

  @Test func keepsTwoHeadingsOfTheSameNameApart() {
    let file = BookmarkFile(
      text: """
        - [A](https://a.example)
        # Bookmarks
        - [B](https://b.example)
        # Work
        ## Docs
        - [C](https://c.example)
        # Home
        ## Docs
        - [D](https://d.example)
        """)
    let sections = Search.bookmarkSections(for: "", file: file)
    #expect(sections.map(\.title) == ["Bookmarks", "Bookmarks", "Docs", "Docs"])
    #expect(Set(sections.map(\.id)).count == 4)
  }

  @Test func searchesTitlesURLsAndDescriptions() {
    let file = BookmarkFile(text: text)
    #expect(Search.bookmarkSections(for: "", file: file).map(\.title) == ["Docs", "Tools"])
    #expect(
      Search.bookmarkSections(for: "language", file: file).flatMap(\.results).map(\.title) == [
        "Swift"
      ])
    #expect(
      Search.bookmarkSections(for: "raycast.com", file: file).flatMap(\.results).map(\.title) == [
        "Raycast"
      ])
    let row = Search.bookmarkSections(for: "swift", file: file)[0].results[0]
    #expect(row.action == .open(URL(string: "https://swift.org")!))
    #expect(row.actions.last?.action == .deleteBookmark(line: 3, text: file.bookmarks[0].text))
  }

  // MARK: Saving and moving

  let sample =
    "Notes.\n\n# Docs\n- [Swift](https://swift.org)\n\n## Sub\n- [Sub](https://sub.example)\n\n# Tools\n  * [x] [Raycast](https://raycast.com) - Launcher\n"

  func save(
    _ file: BookmarkFile, _ title: String, _ url: String, _ description: String = "",
    replacing original: Bookmark? = nil, under destination: BookmarkFile.Destination
  ) throws -> (file: BookmarkFile, line: Int, text: String) {
    try file.saving(
      title: title, url: url, description: description,
      replacing: original.map { ($0.line, $0.text) }, under: destination)
  }

  @Test func addsAfterTheLastBookmarkOfTheGroup() throws {
    let file = BookmarkFile(text: sample)
    let docs = try #require(file.headings.first { $0.title == "Docs" })
    let saved = try save(file, "Apple", "https://apple.com", under: .heading(docs))
    // After Swift, before the blank line and the sub-heading.
    #expect(
      saved.file.text
        == sample.replacingOccurrences(
          of: "- [Swift](https://swift.org)\n",
          with: "- [Swift](https://swift.org)\n- [Apple](https://apple.com)\n"))
    #expect(saved.line == 4)
    // A heading with only sub-headings under it: right after the heading.
    let onlySub = BookmarkFile(text: "# A\n## B\n- [x](https://x.example)\n")
    let a = try #require(onlySub.headings.first)
    #expect(
      try save(onlySub, "N", "https://n.example", under: .heading(a)).file.text
        == "# A\n- [N](https://n.example)\n## B\n- [x](https://x.example)\n")
  }

  @Test func keepsLineEndingsWhenAdding() throws {
    let crlf = BookmarkFile(text: "# A\r\n- [a](https://a.example)")
    let a = try #require(crlf.headings.first)
    #expect(
      try save(crlf, "b", "https://b.example", under: .heading(a)).file.text
        == "# A\r\n- [a](https://a.example)\r\n- [b](https://b.example)")
    #expect(
      try save(crlf, "b", "https://b.example", under: .newHeading("New")).file.text
        == "# A\r\n- [a](https://a.example)\r\n\r\n# New\r\n- [b](https://b.example)")
    #expect(
      try save(BookmarkFile(text: ""), "b", "https://b.example", under: .newHeading("New")).file
        .text == "# New\n- [b](https://b.example)\n")
  }

  @Test func editsInPlaceKeepingTheLinesStart() throws {
    let file = BookmarkFile(text: sample)
    let raycast = try #require(file.bookmarks.last)
    let tools = try #require(file.headings.last)
    let saved = try save(
      file, "Raycast 2", "https://raycast.com", "", replacing: raycast, under: .heading(tools))
    #expect(
      saved.file.text
        == sample.replacingOccurrences(
          of: "  * [x] [Raycast](https://raycast.com) - Launcher",
          with: "  * [x] [Raycast 2](https://raycast.com)"))
    // Above the first heading stays there too.
    let top = BookmarkFile(text: "- [a](https://a.example)\n# H\n")
    let a = try #require(top.bookmarks.first)
    #expect(
      try save(
        top, "b", "https://a.example", replacing: a,
        under: .heading(.init(title: "", line: -1))
      ).file.text == "- [b](https://a.example)\n# H\n")
  }

  @Test func movesTheLineAsWritten() throws {
    let file = BookmarkFile(text: sample)
    let raycast = try #require(file.bookmarks.last)
    let docs = try #require(file.headings.first { $0.title == "Docs" })
    let moved = try file.moving(line: raycast.line, text: raycast.text, under: .heading(docs))
    #expect(
      moved.file.text
        == "Notes.\n\n# Docs\n- [Swift](https://swift.org)\n  * [x] [Raycast](https://raycast.com) - Launcher\n\n## Sub\n- [Sub](https://sub.example)\n\n# Tools\n"
    )
    // Down past where it was.
    let swift = try #require(file.bookmarks.first)
    let tools = try #require(file.headings.last)
    let down = try file.moving(line: swift.line, text: swift.text, under: .heading(tools))
    #expect(down.file.bookmarks.last?.title == "Swift")
    #expect(down.file.bookmarks.last?.group == "Tools")
    // A new group by a name already there goes under that one.
    let named = try file.moving(line: swift.line, text: swift.text, under: .newHeading("Tools"))
    #expect(named.file.headings.count == file.headings.count)
  }

  @Test func refusesWhatWouldNotReadBack() throws {
    let file = BookmarkFile(text: sample)
    let docs = try #require(file.headings.first)
    for (title, url) in [
      ("", "https://a.example"), ("x", "https://a b.example"), ("x", "no-scheme"),
      ("x", "https://a.example/(open"), ("x](y", "https://a.example"),
      // Reads back as a task item titled "y".
      ("x] [y", "https://a.example"),
    ] {
      #expect(throws: BookmarkFile.EditError.self) {
        try save(file, title, url, under: .heading(docs))
      }
    }
    // A title with a lone bracket that still reads back is fine.
    #expect(
      try save(file, "a] [b", "https://a.example", under: .heading(docs)).text.contains("a] [b"))
  }

  @Test func refusesWhenTheFileChanged() throws {
    let file = BookmarkFile(text: sample)
    #expect(throws: BookmarkFile.EditError.changed) {
      try file.moving(line: 3, text: "- [Other](https://o.example)", under: .newHeading("X"))
    }
    #expect(throws: BookmarkFile.EditError.changed) {
      try save(file, "a", "https://a.example", under: .heading(.init(title: "Gone", line: 2)))
    }
  }

  @Test func keepsIndentedLinesWithTheirBookmark() throws {
    let file = BookmarkFile(
      text:
        "# Docs\n- [A](https://a.example)\n  - note about A\n# Tools\n- [T](https://t.example)\n")
    let docs = try #require(file.headings.first)
    // A new one goes after A's note, not between A and it.
    #expect(
      try save(file, "B", "https://b.example", under: .heading(docs)).file.text
        == "# Docs\n- [A](https://a.example)\n  - note about A\n- [B](https://b.example)\n# Tools\n- [T](https://t.example)\n"
    )
    // Moving A takes its note along.
    let a = try #require(file.bookmarks.first)
    let tools = try #require(file.headings.last)
    #expect(
      try file.moving(line: a.line, text: a.text, under: .heading(tools)).file.text
        == "# Docs\n# Tools\n- [T](https://t.example)\n- [A](https://a.example)\n  - note about A\n"
    )
  }

  @Test func keepsTheByteOrderMarkAtTheStart() throws {
    let file = BookmarkFile(text: "\u{FEFF}- [A](https://a.example)\n# Tools\n")
    let a = try #require(file.bookmarks.first)
    let tools = try #require(file.headings.first)
    #expect(
      try file.moving(line: a.line, text: a.text, under: .heading(tools)).file.text
        == "\u{FEFF}# Tools\n- [A](https://a.example)\n")
  }

  @Test func editsOnlyWhatTheFormShows() throws {
    let file = BookmarkFile(
      text:
        "# A\n- [Japan](https://ja.wikipedia.org/wiki/日本)\n- [Tip](https://t.example \"Home\")\n")
    let japan = try #require(file.bookmarks.first)
    #expect(japan.rawURL == "https://ja.wikipedia.org/wiki/日本")
    #expect(japan.isEditable)
    let a = try #require(file.headings.first)
    #expect(
      try save(file, "日本", japan.rawURL, replacing: japan, under: .heading(a)).text
        == "- [日本](https://ja.wikipedia.org/wiki/日本)")
    let tip = try #require(file.bookmarks.last)
    #expect(!tip.isEditable)
    #expect(throws: BookmarkFile.EditError.self) {
      try save(file, "Tip 2", tip.rawURL, replacing: tip, under: .heading(a))
    }
  }

  @Test func refusesANewGroupInsideAnOpenCodeBlock() throws {
    let file = BookmarkFile(text: "# A\n```\ncode\n")
    #expect(throws: BookmarkFile.EditError.self) {
      try save(file, "x", "https://x.example", under: .newHeading("New"))
    }
  }
}
