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

  @Test func neighborsMeetAndStayOnTheScreen() {
    let top = WindowLayout.topHalf.frame(for: window, in: screen)
    let bottom = WindowLayout.bottomHalf.frame(for: window, in: screen)
    #expect(top?.maxY == bottom?.minY)
    #expect(bottom?.maxY == screen.maxY)
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
        == CGRect(x: 72, y: 69, width: 1296, height: 787))
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
    #expect(Hotkey("ctrl+option+return")?.keycaps == ["⌃", "⌥", "↵"])
    // The panel's forms save on ⌘↵.
    #expect(Hotkey("cmd+return") == nil)
  }

  /// Each frame as Raycast's command put the same window on a 1512×948 screen under a 34pt menu
  /// bar (Window Gap and Screen Gap none).
  @Test func matchRaycastsLayouts() {
    let screen = CGRect(x: 0, y: 34, width: 1512, height: 948)
    let window = CGRect(x: 300, y: 200, width: 600, height: 500)
    let expected: [(WindowLayout, CGRect)] = [
      (.firstFourth, CGRect(x: 0, y: 34, width: 378, height: 948)),
      (.secondFourth, CGRect(x: 378, y: 34, width: 378, height: 948)),
      (.thirdFourth, CGRect(x: 756, y: 34, width: 378, height: 948)),
      (.lastFourth, CGRect(x: 1134, y: 34, width: 378, height: 948)),
      (.firstThreeFourths, CGRect(x: 0, y: 34, width: 1134, height: 948)),
      (.lastThreeFourths, CGRect(x: 378, y: 34, width: 1134, height: 948)),
      (.topThird, CGRect(x: 0, y: 34, width: 1512, height: 316)),
      (.middleThird, CGRect(x: 0, y: 350, width: 1512, height: 316)),
      (.bottomThird, CGRect(x: 0, y: 666, width: 1512, height: 316)),
      (.topTwoThirds, CGRect(x: 0, y: 34, width: 1512, height: 632)),
      (.bottomTwoThirds, CGRect(x: 0, y: 350, width: 1512, height: 632)),
      (.centerHalf, CGRect(x: 378, y: 34, width: 756, height: 948)),
      (.centerTwoThirds, CGRect(x: 252, y: 34, width: 1008, height: 948)),
      (.centerThreeFourths, CGRect(x: 189, y: 34, width: 1134, height: 948)),
      (.maximizeHeight, CGRect(x: 300, y: 34, width: 600, height: 948)),
      (.maximizeWidth, CGRect(x: 0, y: 200, width: 1512, height: 500)),
      (.reasonableSize, CGRect(x: 302, y: 224, width: 907, height: 568)),
    ]
    for (layout, frame) in expected {
      #expect(layout.frame(for: window, in: screen) == frame, "\(layout.title)")
    }
  }

  /// As Raycast's commands moved and resized the same window on the same screen.
  @Test func stepsAndMovesMatchRaycast() {
    let screen = CGRect(x: 0, y: 34, width: 1512, height: 948)
    let window = CGRect(x: 300, y: 200, width: 600, height: 500)
    let expected: [(WindowLayout, CGRect)] = [
      (.makeLarger, CGRect(x: 284, y: 184, width: 632, height: 532)),
      (.makeSmaller, CGRect(x: 316, y: 216, width: 568, height: 468)),
      (.moveTop, CGRect(x: 456, y: 34, width: 600, height: 500)),
      (.moveBottom, CGRect(x: 456, y: 482, width: 600, height: 500)),
      (.moveLeft, CGRect(x: 0, y: 258, width: 600, height: 500)),
      (.moveRight, CGRect(x: 912, y: 258, width: 600, height: 500)),
    ]
    for (layout, frame) in expected {
      #expect(layout.frame(for: window, in: screen) == frame, "\(layout.title)")
    }
    // A window as large as the screen stays so.
    #expect(WindowLayout.makeLarger.frame(for: screen, in: screen) == screen)
  }
}
