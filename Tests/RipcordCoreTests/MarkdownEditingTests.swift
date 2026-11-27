import Foundation
import Testing

@testable import RipcordCore

@Suite struct MarkdownEditingTests {
  func caret(_ proposed: Int, from old: Int, _ text: String) -> Int {
    MarkdownEditing.caret(
      proposed, from: old, in: text,
      hidden: MarkdownEditing.hidden(in: MarkdownSpan.spans(in: text)))
  }

  func backspace(_ text: String, at caret: Int) -> MarkdownEditing.Delete {
    MarkdownEditing.deleteBackward(at: caret, in: text, spans: MarkdownSpan.spans(in: text))
  }

  @Test func stepsOverHiddenMarksOneVisibleCharacterAtATime() {
    // a**x**: the caret can rest at 0 (before a), 3 (before x) and 6 (after x).
    let text = "a**x**"
    #expect(caret(5, from: 6, text) == 3)
    #expect(caret(2, from: 3, text) == 0)
    #expect(caret(1, from: 0, text) == 3)
    #expect(caret(4, from: 3, text) == 6)
    // A click on a mark lands after it.
    #expect(caret(4, from: 0, text) == 6)
  }

  @Test func restsInsideAHeadingNotOnItsMarks() {
    let text = "ab\n# Title"
    #expect(caret(3, from: 0, text) == 5)
    #expect(caret(4, from: 5, text) == 2)
    // At the very start, a step left has nowhere to go and stays after the marks.
    #expect(caret(1, from: 2, "# T") == 2)
  }

  @Test func countsAnEmojiBeforeMarksAsOneCharacter() {
    // 😀 is two UTF-16 units: one step left from before x lands before the emoji, not inside it.
    #expect(caret(3, from: 4, "😀**x**") == 0)
  }

  @Test func backspaceAtAHeadingsStartMatchesRaycast() {
    // Written: nothing happens. Empty: back to a plain line.
    #expect(backspace("# Title", at: 2) == .nothing)
    #expect(backspace("# ", at: 2) == .remove(NSRange(location: 0, length: 2)))
  }

  @Test func backspaceTakesVisibleTextOrTheWholeStyle() {
    // After **ab**: the b goes, the marks stay.
    #expect(backspace("**ab**", at: 6) == .remove(NSRange(location: 3, length: 1)))
    // After **a**: the last letter takes its marks with it.
    #expect(backspace("x **a**", at: 7) == .remove(NSRange(location: 2, length: 5)))
    // Plain text is left to the text view.
    #expect(backspace("plain", at: 5) == .normal)
  }

  @Test func forwardDeleteMirrorsBackspace() {
    #expect(
      MarkdownEditing.deleteForward(at: 0, in: "**a** b", spans: MarkdownSpan.spans(in: "**a** b"))
        == .remove(NSRange(location: 0, length: 5)))
  }

  func toggleBold(_ text: String, _ selection: NSRange) -> (text: String, selection: NSRange)? {
    MarkdownEditing.toggle(
      .bold, open: "**", close: "**", selection: selection, in: text,
      spans: MarkdownSpan.spans(in: text)
    ).map {
      ((text as NSString).replacingCharacters(in: $0.range, with: $0.replacement), $0.selection)
    }
  }

  @Test func togglesBoldAroundTheSelectedWords() {
    let text = "say hello now"
    // The space selected with the word stays outside the marks.
    let bold = toggleBold(text, NSRange(location: 3, length: 7))
    #expect(bold?.text == "say **hello** now")
    #expect(bold?.selection == NSRange(location: 6, length: 5))
    let plain = bold.flatMap { toggleBold($0.text, $0.selection) }
    #expect(plain?.text == text)
    #expect(plain?.selection == NSRange(location: 4, length: 5))
    // Nothing selected: an empty pair with the caret between, for what's typed next.
    let empty = toggleBold(text, NSRange(location: 3, length: 0))
    #expect(empty?.text == "say**** hello now")
    #expect(empty?.selection == NSRange(location: 5, length: 0))
  }
}

@Suite struct MarkdownTidyTests {
  func edit(_ text: String, _ range: NSRange, _ replacement: String = "") -> String {
    guard
      let tidy = MarkdownEditing.tidy(
        range, replacement: replacement, in: text, spans: MarkdownSpan.spans(in: text))
    else { return (text as NSString).replacingCharacters(in: range, with: replacement) }
    return (text as NSString).replacingCharacters(in: tidy.range, with: tidy.replacement)
  }

  @Test func takesAStylesMarksWhenAllItsTextGoes() {
    // A word delete or selection of "bold" leaves no bare ****.
    #expect(edit("a **bold** b", NSRange(location: 4, length: 4)) == "a  b")
    // A selection reaching into the closing marks too.
    #expect(edit("a **bold** b", NSRange(location: 4, length: 6)) == "a  b")
    // An empty heading line's text gone with its line: its #s go as well.
    #expect(edit("x\n# Hi", NSRange(location: 1, length: 5)) == "x")
  }

  @Test func keepsAStylesMarksWhenSomeOfItsTextStays() {
    // Deleting "ld** af": the bold keeps its closing marks after "bo".
    #expect(edit("**bold** after", NSRange(location: 4, length: 7)) == "**bo**ter")
    // Deleting " **bo": the opening marks stay before "ld".
    #expect(edit("a **bold**", NSRange(location: 1, length: 5)) == "a**ld**")
  }

  @Test func leavesPlainEditsAlone() {
    #expect(
      MarkdownEditing.tidy(
        NSRange(location: 0, length: 2), replacement: "", in: "plain",
        spans: MarkdownSpan.spans(in: "plain")) == nil)
  }

  @Test func stylesTheWordsWhenASelectionTakesInMarks() {
    let text = "a **b** c"
    // ⇧← from after the bold can take in its closing marks; ⌘B then unbolds b.
    let toggle = MarkdownEditing.toggle(
      .bold, open: "**", close: "**", selection: NSRange(location: 4, length: 3), in: text,
      spans: MarkdownSpan.spans(in: text))
    #expect(toggle?.replacement == "b")
  }
}

@Suite struct MarkdownLineFormatTests {
  func apply(_ edit: (range: NSRange, replacement: String, selection: NSRange), to text: String)
    -> String
  {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
  }

  func lines(_ format: MarkdownEditing.LineFormat, _ text: String, _ selection: NSRange) -> String {
    apply(MarkdownEditing.toggleLines(format, selection: selection, in: text), to: text)
  }

  @Test func togglesAListOnTheLinesSelected() {
    let text = "milk\neggs\ntea"
    #expect(lines(.bullet, text, NSRange(location: 0, length: 9)) == "- milk\n- eggs\ntea")
    #expect(lines(.bullet, "- milk\n- eggs", NSRange(location: 0, length: 13)) == "milk\neggs")
    #expect(lines(.ordered, text, NSRange(location: 0, length: 13)) == "1. milk\n2. eggs\n3. tea")
    #expect(lines(.task, "milk", NSRange(location: 2, length: 0)) == "- [ ] milk")
  }

  @Test func swapsOneLineMarkForAnother() {
    #expect(lines(.quote, "- milk", NSRange(location: 3, length: 0)) == "> milk")
    #expect(lines(.heading(2), "# Plan", NSRange(location: 3, length: 0)) == "## Plan")
    #expect(lines(.heading(1), "# Plan", NSRange(location: 3, length: 0)) == "Plan")
  }

  @Test func keepsTheCaretInTheText() {
    let edit = MarkdownEditing.toggleLines(
      .bullet, selection: NSRange(location: 2, length: 0), in: "milk")
    #expect(edit.selection == NSRange(location: 4, length: 0))
    // On an empty line the mark goes in for what's typed next.
    #expect(lines(.bullet, "a\n\nb", NSRange(location: 2, length: 0)) == "a\n- \nb")
  }

  @Test func wrapsAndUnwrapsACodeBlock() {
    let text = "x\nlet a = 1\ny"
    let wrap = MarkdownEditing.toggleCodeBlock(selection: NSRange(location: 3, length: 0), in: text)
    let wrapped = apply(wrap, to: text)
    #expect(wrapped == "x\n```\nlet a = 1\n```\ny")
    let unwrap = MarkdownEditing.toggleCodeBlock(selection: wrap.selection, in: wrapped)
    #expect(apply(unwrap, to: wrapped) == text)
  }

  @Test func readsUnderlineAsHiddenMarks() {
    let spans = MarkdownSpan.spans(in: "a <u>b</u>")
    #expect(
      spans.contains { $0.style == .underline && $0.range == NSRange(location: 5, length: 1) })
    #expect(MarkdownEditing.hidden(in: spans).count == 2)
  }
}
