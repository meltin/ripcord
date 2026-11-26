import Foundation
import Testing

@testable import RipcordCore

@Suite struct MarkdownStyleTests {
  /// Each span as the text it covers, with its style.
  func styled(_ text: String) -> [String] {
    MarkdownSpan.spans(in: text).map { span in
      "\(span.style):\((text as NSString).substring(with: span.range))"
    }
  }

  @Test func readsHeadingsWithTheirLevel() {
    #expect(styled("## Plan") == ["heading(2):## Plan", "mark:## "])
    #expect(styled("#hashtag").isEmpty)
  }

  @Test func readsEmphasisAndCodeButNotInsideCode() {
    #expect(styled("a **bold** b") == ["bold:bold", "mark:**", "mark:**"])
    #expect(styled("an *it* word") == ["italic:it", "mark:*", "mark:*"])
    #expect(styled("`**x**`") == ["code:**x**", "mark:`", "mark:`"])
    #expect(styled("2 * 3 * 4").isEmpty)
    // Underscores inside a word aren't emphasis.
    #expect(styled("foo__bar__baz").isEmpty)
    #expect(styled("__strong__") == ["bold:strong", "mark:__", "mark:__"])
    // Code inside emphasis keeps both.
    #expect(
      styled("**run `make` first**") == [
        "code:make", "mark:`", "mark:`", "bold:run `make` first", "mark:**", "mark:**",
      ])
  }

  @Test func readsListsTasksQuotesAndLinks() {
    #expect(styled("- item") == ["mark:- "])
    #expect(styled("- [x] done") == ["mark:- [x] ", "done:done"])
    #expect(styled("- [ ] todo") == ["mark:- [ ] "])
    #expect(styled("> said") == ["quote:> said", "mark:> "])
    #expect(
      styled("[Swift](https://swift.org)") == ["link:Swift", "mark:[", "mark:](https://swift.org)"])
  }

  @Test func keepsCodeBlocksPlain() {
    let text = "```\n# not a heading\n```\n# Heading"
    #expect(
      styled(text) == [
        "codeBlock:```", "codeBlock:# not a heading", "codeBlock:```", "heading(1):# Heading",
        "mark:# ",
      ])
  }

  @Test func countsInUTF16() {
    // An emoji is two UTF-16 units; the bold after it must still land on its word.
    #expect(styled("😀 **ok**") == ["bold:ok", "mark:**", "mark:**"])
  }
}
