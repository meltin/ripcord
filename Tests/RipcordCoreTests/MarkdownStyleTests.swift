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
    #expect(styled("## Plan") == ["heading(2):## Plan", "hidden:## "])
    #expect(styled("#hashtag").isEmpty)
  }

  @Test func readsEmphasisAndCodeButNotInsideCode() {
    #expect(styled("a **bold** b") == ["bold:bold", "hidden:**", "hidden:**"])
    #expect(styled("an *it* word") == ["italic:it", "hidden:*", "hidden:*"])
    #expect(styled("`**x**`") == ["code:**x**", "hidden:`", "hidden:`"])
    #expect(styled("2 * 3 * 4").isEmpty)
    // Underscores inside a word aren't emphasis.
    #expect(styled("foo__bar__baz").isEmpty)
    #expect(styled("__strong__") == ["bold:strong", "hidden:__", "hidden:__"])
    // Code inside emphasis keeps both.
    #expect(
      styled("**run `make` first**") == [
        "code:make", "hidden:`", "hidden:`", "bold:run `make` first", "hidden:**", "hidden:**",
      ])
  }

  @Test func readsStrikethrough() {
    #expect(styled("~~gone~~ here") == ["strike:gone", "hidden:~~", "hidden:~~"])
    #expect(styled("~~ not ~~").isEmpty)
  }

  @Test func readsListsTasksQuotesAndLinks() {
    #expect(styled("- item") == ["bullet:- item", "hidden:- "])
    #expect(styled("  2. next") == ["ordered:  2. next", "hidden:  2. "])
    #expect(
      styled("- [x] done") == ["task(checked: true):- [x] done", "hidden:- [x] ", "done:done"])
    #expect(styled("- [ ] todo") == ["task(checked: false):- [ ] todo", "hidden:- [ ] "])
    #expect(styled("> said") == ["quote:> said", "hidden:> "])
    #expect(
      styled("[Swift](https://swift.org)") == [
        "link:Swift", "hidden:[", "hidden:](https://swift.org)",
      ])
  }

  @Test func keepsCodeBlocksPlain() {
    let text = "```\n# not a heading\n```\n# Heading"
    #expect(
      styled(text) == [
        "codeBlock:```", "codeBlock:# not a heading", "codeBlock:```", "heading(1):# Heading",
        "hidden:# ", "fenced:# not a heading", "hidden:```\n", "hidden:\n```\n",
      ])
  }

  @Test func showsTheFenceOfABlockNotClosedYet() {
    #expect(styled("```\nlet a") == ["codeBlock:```", "codeBlock:let a"])
  }

  @Test func countsInUTF16() {
    // An emoji is two UTF-16 units; the bold after it must still land on its word.
    #expect(styled("😀 **ok**") == ["bold:ok", "hidden:**", "hidden:**"])
  }
}
