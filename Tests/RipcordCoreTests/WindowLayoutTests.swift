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
        == CGRect(x: 0, y: 25, width: 1440, height: 437))
    #expect(
      WindowLayout.bottomRightQuarter.frame(for: window, in: screen)?.origin
        == CGPoint(x: 720, y: 463))
  }

  /// On an odd height a half's 437.5 points are rounded down for both, leaving a point between
  /// them, as Raycast's top and bottom halves do on a screen 1121 points high.
  @Test func neighborsNeverOverlapAndStayOnTheScreen() {
    let top = WindowLayout.topHalf.frame(for: window, in: screen)
    let bottom = WindowLayout.bottomHalf.frame(for: window, in: screen)
    #expect(top?.maxY == 462)
    #expect(bottom?.minY == 463)
    #expect(bottom?.maxY == screen.maxY)
    let tall = CGRect(x: 0, y: 31, width: 2048, height: 1121)
    #expect(
      WindowLayout.topHalf.frame(for: window, in: tall)
        == CGRect(x: 0, y: 31, width: 2048, height: 560))
    #expect(
      WindowLayout.bottomHalf.frame(for: window, in: tall)
        == CGRect(x: 0, y: 592, width: 2048, height: 560))
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

  /// As Raycast's Window Gap (32) and Screen Gap (16) placed a window on a 2048 × 1152 screen.
  @Test func gapsMatchRaycast() {
    let screen = CGRect(x: 0, y: 31, width: 2048, height: 1121)
    let window = CGRect(x: 300, y: 200, width: 600, height: 500)
    let cases: [(CGFloat, CGFloat, WindowLayout, CGRect)] = [
      (32, 0, .leftHalf, CGRect(x: 0, y: 31, width: 1008, height: 1121)),
      (32, 0, .rightHalf, CGRect(x: 1040, y: 31, width: 1008, height: 1121)),
      (32, 0, .topHalf, CGRect(x: 0, y: 31, width: 2048, height: 544)),
      (32, 0, .bottomHalf, CGRect(x: 0, y: 608, width: 2048, height: 544)),
      (32, 0, .maximize, screen),
      (0, 16, .leftHalf, CGRect(x: 16, y: 47, width: 1008, height: 1089)),
      (0, 16, .rightHalf, CGRect(x: 1024, y: 47, width: 1008, height: 1089)),
      (0, 16, .topHalf, CGRect(x: 16, y: 47, width: 2016, height: 544)),
      (0, 16, .bottomHalf, CGRect(x: 16, y: 592, width: 2016, height: 544)),
      (0, 16, .maximize, CGRect(x: 16, y: 47, width: 2016, height: 1089)),
      (32, 16, .leftHalf, CGRect(x: 16, y: 47, width: 992, height: 1089)),
      (32, 16, .rightHalf, CGRect(x: 1040, y: 47, width: 992, height: 1089)),
      (32, 16, .topHalf, CGRect(x: 16, y: 47, width: 2016, height: 528)),
      (32, 16, .bottomHalf, CGRect(x: 16, y: 608, width: 2016, height: 528)),
      (32, 16, .maximize, CGRect(x: 16, y: 47, width: 2016, height: 1089)),
    ]
    for (windowGap, screenGap, layout, frame) in cases {
      let placed = layout.frame(
        for: window, in: screen, windowGap: windowGap, screenGap: screenGap)
      #expect(placed == frame, "\(layout.title) \(windowGap)/\(screenGap)")
    }
    // Used again, a half with gaps goes on to its ⅔.
    let half = WindowLayout.leftHalf.frame(
      for: window, in: screen, cycling: true, windowGap: 32, screenGap: 16)
    let twoThirds = WindowLayout.leftHalf.frame(
      for: half ?? .zero, in: screen, cycling: true, windowGap: 32, screenGap: 16)
    #expect(half?.width == 992)
    #expect(twoThirds == CGRect(x: 16, y: 47, width: 1328, height: 1089))
    // A gap too large for the screen leaves nowhere to go.
    #expect(WindowLayout.leftHalf.frame(for: window, in: screen, screenGap: 2000) == nil)
  }

  /// As Raycast's halves cycled ½ → ⅔ → ⅓ on a 2048 × 1121 screen, where the thirds aren't
  /// whole points: sizes rounded down, the right and bottom ones ending on the screen's edge.
  @Test func cycleStepsRoundAsRaycast() {
    let screen = CGRect(x: 0, y: 31, width: 2048, height: 1121)
    func steps(_ layout: WindowLayout) -> [CGRect] {
      var window = CGRect(x: 300, y: 200, width: 600, height: 500)
      return (0..<3).map { _ in
        window = layout.frame(for: window, in: screen, cycling: true) ?? .zero
        return window
      }
    }
    #expect(
      steps(.leftHalf) == [
        CGRect(x: 0, y: 31, width: 1024, height: 1121),
        CGRect(x: 0, y: 31, width: 1365, height: 1121),
        CGRect(x: 0, y: 31, width: 682, height: 1121),
      ])
    #expect(
      steps(.rightHalf) == [
        CGRect(x: 1024, y: 31, width: 1024, height: 1121),
        CGRect(x: 683, y: 31, width: 1365, height: 1121),
        CGRect(x: 1366, y: 31, width: 682, height: 1121),
      ])
    #expect(steps(.topHalf).map(\.height) == [560, 747, 373])
    #expect(steps(.bottomHalf).map(\.minY) == [592, 405, 779])
  }

  @Test func halvesCycleAsRaycastsSettingDoes() {
    let screen = CGRect(x: 0, y: 34, width: 1512, height: 948)
    var window = CGRect(x: 300, y: 200, width: 600, height: 500)
    var widths: [CGFloat] = []
    for _ in 0..<4 {
      window = WindowLayout.leftHalf.frame(for: window, in: screen, cycling: true) ?? .zero
      #expect(window.minX == 0)
      widths.append(window.width)
    }
    #expect(widths == [756, 1008, 504, 756])
    var heights: [CGFloat] = []
    for _ in 0..<3 {
      window = WindowLayout.bottomHalf.frame(for: window, in: screen, cycling: true) ?? .zero
      #expect(window.maxY == screen.maxY)
      heights.append(window.height)
    }
    #expect(heights == [474, 632, 316])
    // Off, a half is always a half.
    let half = WindowLayout.rightHalf.frame(for: screen, in: screen)
    #expect(WindowLayout.rightHalf.frame(for: half ?? .zero, in: screen, cycling: false) == half)
  }
}
