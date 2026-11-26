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
}
