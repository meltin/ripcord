import CoreGraphics
import Testing

@testable import RipcordCore

@Suite struct WindowLayoutTests {
  /// A 1440×900 display under a 25pt menu bar, in the Accessibility API's top-left coordinates.
  let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
  let window = CGRect(x: 100, y: 100, width: 800, height: 600)

  @Test func halvesAndQuarters() {
    #expect(
      WindowLayout.leftHalf.frame(for: window, in: screen)
        == CGRect(x: 0, y: 25, width: 720, height: 875))
    #expect(
      WindowLayout.rightHalf.frame(for: window, in: screen)
        == CGRect(x: 720, y: 25, width: 720, height: 875))
    #expect(
      WindowLayout.topHalf.frame(for: window, in: screen)
        == CGRect(x: 0, y: 25, width: 1440, height: 438))
    #expect(
      WindowLayout.bottomRightQuarter.frame(for: window, in: screen)?.origin
        == CGPoint(x: 720, y: 463))
  }

  @Test func thirdsRunAlongTheLongSide() {
    #expect(WindowLayout.firstThird.frame(for: window, in: screen)?.width == 480)
    #expect(WindowLayout.lastTwoThirds.frame(for: window, in: screen)?.minX == 480)
    let portrait = CGRect(x: 0, y: 0, width: 900, height: 1440)
    let third = WindowLayout.centerThird.frame(for: window, in: portrait)
    #expect(third == CGRect(x: 0, y: 480, width: 900, height: 480))
  }

  @Test func maximizeFillsTheUsableArea() {
    #expect(WindowLayout.maximize.frame(for: window, in: screen) == screen)
    #expect(
      WindowLayout.almostMaximize.frame(for: window, in: screen)
        == CGRect(x: 72, y: 69, width: 1296, height: 788))
  }

  @Test func centerKeepsTheSizeWithinTheScreen() {
    #expect(
      WindowLayout.center.frame(for: window, in: screen)
        == CGRect(x: 320, y: 163, width: 800, height: 600))
    let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
    #expect(WindowLayout.center.frame(for: huge, in: screen) == screen)
  }

  @Test func displayMovesKeepProportions() {
    let other = CGRect(x: 1440, y: 0, width: 2880, height: 1750)
    #expect(
      WindowLayout.frame(for: window, from: screen, to: other)
        == CGRect(x: 1640, y: 150, width: 1600, height: 1200))
    #expect(WindowLayout.nextDisplay.frame(for: window, in: screen) == nil)
  }

  @Test func foundByTypingWithKeysApartFromTheRest() {
    #expect(
      Search.results(for: "left half", apps: [], quicklinks: []).first?.action
        == .window(.leftHalf))
    let keys = WindowLayout.allCases.map(\.settingsKey)
    #expect(Set(keys).count == keys.count)
    #expect(WindowLayout.leftHalf.settingsKey == "window:left-half")
  }

  @Test func arrowsAndReturnMakeHotkeys() throws {
    let left = try #require(Hotkey("ctrl+option+left"))
    #expect(left.keycaps == ["⌃", "⌥", "←"])
    #expect(left.spec == "ctrl+option+left")
    #expect(Hotkey("ctrl+option+return")?.keycaps == ["⌃", "⌥", "↩"])
  }
}
