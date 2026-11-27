import Carbon.HIToolbox
import Testing

@testable import RipcordCore

@Suite struct DoubleTapTests {
  let shift = UInt32(shiftKey)
  let cmd = UInt32(cmdKey)

  /// Taps `modifier` down at `start` and up 0.1 s later; what the release returned.
  func tap(_ detector: inout DoubleTapDetector, _ modifier: UInt32, at start: Double) -> UInt32? {
    _ = detector.modifiersChanged(to: modifier, at: start)
    return detector.modifiersChanged(to: 0, at: start + 0.1)
  }

  @Test func twoQuickTapsFireOnTheSecondRelease() {
    var detector = DoubleTapDetector()
    #expect(tap(&detector, shift, at: 0) == nil)
    #expect(tap(&detector, shift, at: 0.3) == shift)
    // A third tap starts over rather than firing again.
    #expect(tap(&detector, shift, at: 0.6) == nil)
  }

  @Test func aSlowSecondTapIsNot() {
    var detector = DoubleTapDetector()
    _ = tap(&detector, shift, at: 0)
    #expect(tap(&detector, shift, at: 1.0) == nil)
  }

  @Test func aHeldModifierIsNotATap() {
    var detector = DoubleTapDetector()
    _ = detector.modifiersChanged(to: shift, at: 0)
    _ = detector.modifiersChanged(to: 0, at: 0.8)
    #expect(tap(&detector, shift, at: 0.9) == nil)
  }

  @Test func aKeyBetweenTheTapsCancels() {
    var detector = DoubleTapDetector()
    _ = tap(&detector, shift, at: 0)
    // ⇧⌘K right after a ⇧ tap stays a chord.
    _ = detector.modifiersChanged(to: shift, at: 0.2)
    detector.keyPressed()
    #expect(detector.modifiersChanged(to: 0, at: 0.3) == nil)
  }

  @Test func anotherModifierJoiningIsAChord() {
    var detector = DoubleTapDetector()
    _ = tap(&detector, shift, at: 0)
    _ = detector.modifiersChanged(to: shift, at: 0.2)
    _ = detector.modifiersChanged(to: shift | cmd, at: 0.25)
    _ = detector.modifiersChanged(to: shift, at: 0.3)
    #expect(detector.modifiersChanged(to: 0, at: 0.35) == nil)
  }

  @Test func twoDifferentModifiersAreNotADoubleTap() {
    var detector = DoubleTapDetector()
    _ = tap(&detector, shift, at: 0)
    #expect(tap(&detector, cmd, at: 0.3) == nil)
  }

  @Test func anUnchangedChangeIsIgnored() {
    var detector = DoubleTapDetector()
    _ = tap(&detector, shift, at: 0)
    // Caps Lock reports the same four modifiers.
    #expect(detector.modifiersChanged(to: 0, at: 0.15) == nil)
    #expect(tap(&detector, shift, at: 0.3) == shift)
  }
}

@Suite struct DoubleTapHotkeyTests {
  @Test func specsRoundTrip() throws {
    let shift = try #require(Hotkey("shift+shift"))
    #expect(shift.isDoubleTap)
    #expect(shift.spec == "shift+shift")
    #expect(shift.keycaps == ["⇧", "⇧"])
    #expect(Hotkey("command+cmd") == Hotkey(doubleTap: UInt32(cmdKey)))
    #expect(Hotkey("cmd+space")?.isDoubleTap == false)
  }

  @Test func repeatedModifiersWithAKeyAreNotAHotkey() {
    #expect(Hotkey("shift+shift+k") == nil)
    #expect(Hotkey("cmd+cmd+k") == nil)
    #expect(Hotkey("shift+cmd") == nil)
  }
}
