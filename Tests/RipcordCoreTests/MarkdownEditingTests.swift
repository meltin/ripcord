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
      .bold, mark: "**", selection: selection, in: text, spans: MarkdownSpan.spans(in: text)
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
    #expect(toggleBold(text, NSRange(location: 3, length: 0)) == nil)
  }
}
