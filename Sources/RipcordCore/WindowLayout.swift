import CoreGraphics

/// Raycast's Window Management commands: where to put the frontmost window. Frames are in one
/// coordinate space for the window and its screen's visible area (the Accessibility API's, whose
/// origin is the top left and y grows downward).
public enum WindowLayout: String, CaseIterable, Sendable {
  // Raw values are the settings keys' stable part, spelled out so a rename never strands them.
  case leftHalf = "left-half"
  case rightHalf = "right-half"
  case topHalf = "top-half"
  case bottomHalf = "bottom-half"
  case topLeftQuarter = "top-left-quarter"
  case topRightQuarter = "top-right-quarter"
  case bottomLeftQuarter = "bottom-left-quarter"
  case bottomRightQuarter = "bottom-right-quarter"
  case firstThird = "first-third"
  case centerThird = "center-third"
  case lastThird = "last-third"
  case firstTwoThirds = "first-two-thirds"
  case lastTwoThirds = "last-two-thirds"
  case firstFourth = "first-fourth"
  case secondFourth = "second-fourth"
  case thirdFourth = "third-fourth"
  case lastFourth = "last-fourth"
  case firstThreeFourths = "first-three-fourths"
  case lastThreeFourths = "last-three-fourths"
  case topThird = "top-third"
  case middleThird = "middle-third"
  case bottomThird = "bottom-third"
  case topTwoThirds = "top-two-thirds"
  case bottomTwoThirds = "bottom-two-thirds"
  case centerHalf = "center-half"
  case centerTwoThirds = "center-two-thirds"
  case centerThreeFourths = "center-three-fourths"
  case maximizeHeight = "maximize-height"
  case maximizeWidth = "maximize-width"
  case reasonableSize = "reasonable-size"
  case makeLarger = "make-larger"
  case makeSmaller = "make-smaller"
  case moveTop = "move-top"
  case moveBottom = "move-bottom"
  case moveLeft = "move-left"
  case moveRight = "move-right"
  case minimize = "minimize"
  case toggleFullscreen = "toggle-fullscreen"
  case maximize = "maximize"
  case almostMaximize = "almost-maximize"
  case center = "center"
  case nextDisplay = "next-display"
  case previousDisplay = "previous-display"
  case restore = "restore"

  public var title: String {
    switch self {
    case .leftHalf: "Left Half"
    case .rightHalf: "Right Half"
    case .topHalf: "Top Half"
    case .bottomHalf: "Bottom Half"
    case .topLeftQuarter: "Top Left Quarter"
    case .topRightQuarter: "Top Right Quarter"
    case .bottomLeftQuarter: "Bottom Left Quarter"
    case .bottomRightQuarter: "Bottom Right Quarter"
    case .firstThird: "First Third"
    case .centerThird: "Center Third"
    case .lastThird: "Last Third"
    case .firstTwoThirds: "First Two Thirds"
    case .lastTwoThirds: "Last Two Thirds"
    case .firstFourth: "First Fourth"
    case .secondFourth: "Second Fourth"
    case .thirdFourth: "Third Fourth"
    case .lastFourth: "Last Fourth"
    case .firstThreeFourths: "First Three Fourths"
    case .lastThreeFourths: "Last Three Fourths"
    case .topThird: "Top Third"
    case .middleThird: "Middle Third"
    case .bottomThird: "Bottom Third"
    case .topTwoThirds: "Top Two Thirds"
    case .bottomTwoThirds: "Bottom Two Thirds"
    case .centerHalf: "Center Half"
    case .centerTwoThirds: "Center Two Thirds"
    case .centerThreeFourths: "Center Three Fourths"
    case .maximizeHeight: "Maximize Height"
    case .maximizeWidth: "Maximize Width"
    case .reasonableSize: "Reasonable Size"
    case .makeLarger: "Make Larger"
    case .makeSmaller: "Make Smaller"
    case .moveTop: "Move Top"
    case .moveBottom: "Move Bottom"
    case .moveLeft: "Move Left"
    case .moveRight: "Move Right"
    case .minimize: "Minimize"
    case .toggleFullscreen: "Toggle Fullscreen"
    case .maximize: "Maximize"
    case .almostMaximize: "Almost Maximize"
    case .center: "Center"
    case .nextDisplay: "Move to Next Display"
    case .previousDisplay: "Move to Previous Display"
    case .restore: "Restore"
    }
  }

  public var settingsKey: String { "window:\(rawValue)" }

  /// Where `window` goes on a screen whose usable area is `screen`; nil for the ones that
  /// need more than one screen or the window's history (next and previous display, restore).
  /// As Raycast's Screen Gap and Window Gap: every window keeps `screenGap` from the screen's
  /// edges, and a tiled one `windowGap` from its neighbors, half on each side.
  public func frame(
    for window: CGRect, in screen: CGRect, windowGap: CGFloat = 0, screenGap: CGFloat = 0
  ) -> CGRect? {
    let visible = screen.insetBy(dx: max(screenGap, 0), dy: max(screenGap, 0))
    // A gap set by hand too large for the screen leaves nowhere to put the window.
    guard !visible.isEmpty, windowGap >= 0 else { return nil }
    let (x, y, w, h) = (visible.minX, visible.minY, visible.width, visible.height)
    func part(_ fx: CGFloat, _ fy: CGFloat, _ fw: CGFloat, _ fh: CGFloat) -> CGRect {
      Self.tile(fx, fy, fw, fh, in: visible, gap: windowGap)
    }
    // Thirds run along the long side, so they split a portrait screen top to bottom.
    let wide = w >= h
    func third(_ start: CGFloat, _ length: CGFloat) -> CGRect {
      wide ? part(start, 0, length, 1) : part(0, start, 1, length)
    }
    switch self {
    case .leftHalf: return part(0, 0, 0.5, 1)
    case .rightHalf: return part(0.5, 0, 0.5, 1)
    case .topHalf: return part(0, 0, 1, 0.5)
    case .bottomHalf: return part(0, 0.5, 1, 0.5)
    case .topLeftQuarter: return part(0, 0, 0.5, 0.5)
    case .topRightQuarter: return part(0.5, 0, 0.5, 0.5)
    case .bottomLeftQuarter: return part(0, 0.5, 0.5, 0.5)
    case .bottomRightQuarter: return part(0.5, 0.5, 0.5, 0.5)
    case .firstThird: return third(0, 1.0 / 3)
    case .centerThird: return third(1.0 / 3, 1.0 / 3)
    case .lastThird: return third(2.0 / 3, 1.0 / 3)
    case .firstTwoThirds: return third(0, 2.0 / 3)
    case .lastTwoThirds: return third(1.0 / 3, 2.0 / 3)
    // Fourths and the centered sizes are columns, and these thirds rows, on any screen, as
    // Raycast measured on a wide one puts them.
    case .firstFourth: return part(0, 0, 0.25, 1)
    case .secondFourth: return part(0.25, 0, 0.25, 1)
    case .thirdFourth: return part(0.5, 0, 0.25, 1)
    case .lastFourth: return part(0.75, 0, 0.25, 1)
    case .firstThreeFourths: return part(0, 0, 0.75, 1)
    case .lastThreeFourths: return part(0.25, 0, 0.75, 1)
    case .topThird: return part(0, 0, 1, 1.0 / 3)
    case .middleThird: return part(0, 1.0 / 3, 1, 1.0 / 3)
    case .bottomThird: return part(0, 2.0 / 3, 1, 1.0 / 3)
    case .topTwoThirds: return part(0, 0, 1, 2.0 / 3)
    case .bottomTwoThirds: return part(0, 1.0 / 3, 1, 2.0 / 3)
    case .centerHalf: return part(0.25, 0, 0.5, 1)
    case .centerTwoThirds: return part(1.0 / 6, 0, 2.0 / 3, 1)
    case .centerThreeFourths: return part(0.125, 0, 0.75, 1)
    case .maximizeHeight:
      return CGRect(x: window.minX, y: y, width: window.width, height: h).rounded
    case .maximizeWidth:
      return CGRect(x: x, y: window.minY, width: w, height: window.height).rounded
    case .reasonableSize:
      // 60% of the screen each way, centered, whatever the window was; Raycast rounds down.
      let size = CGSize(width: (w * 0.6).rounded(.down), height: (h * 0.6).rounded(.down))
      return CGRect(
        x: x + ((w - size.width) / 2).rounded(.down), y: y + ((h - size.height) / 2).rounded(.down),
        width: size.width, height: size.height)
    case .makeLarger, .makeSmaller:
      // 32 points each way, about the window's center, kept on the screen, as Raycast steps.
      let step: CGFloat = self == .makeLarger ? 32 : -32
      let size = CGSize(
        width: min(max(window.width + step, 1), w), height: min(max(window.height + step, 1), h))
      return Self.onScreen(
        CGRect(
          x: window.midX - size.width / 2, y: window.midY - size.height / 2, width: size.width,
          height: size.height), visible)
    case .moveTop, .moveBottom, .moveLeft, .moveRight:
      // Against that edge and centered the other way, its size kept, as Raycast moves them.
      let size = CGSize(width: min(window.width, w), height: min(window.height, h))
      let centeredX = x + (w - size.width) / 2
      let centeredY = y + (h - size.height) / 2
      let origin: CGPoint =
        switch self {
        case .moveTop: CGPoint(x: centeredX, y: y)
        case .moveBottom: CGPoint(x: centeredX, y: visible.maxY - size.height)
        case .moveLeft: CGPoint(x: x, y: centeredY)
        default: CGPoint(x: visible.maxX - size.width, y: centeredY)
        }
      return CGRect(origin: origin, size: size).rounded
    case .maximize: return visible.rounded
    // Not a tile: no neighbors to keep a gap from.
    case .almostMaximize: return Self.tile(0.05, 0.05, 0.9, 0.9, in: visible, gap: 0)
    case .center:
      // Its size kept, but never larger than the screen.
      let size = CGSize(width: min(window.width, w), height: min(window.height, h))
      return CGRect(
        x: x + (w - size.width) / 2, y: y + (h - size.height) / 2, width: size.width,
        height: size.height
      )
      .rounded
    case .nextDisplay, .previousDisplay, .restore, .minimize, .toggleFullscreen:
      return nil
    }
  }

  /// Where a half puts `window` when halves cycle: ½, or the next of ½ → ⅔ → ⅓ → ½ when the
  /// window is already at one of them on that side, as Raycast's Cycle ½, ⅔, and ⅓ does.
  public func frame(
    for window: CGRect, in screen: CGRect, cycling: Bool, windowGap: CGFloat = 0,
    screenGap: CGFloat = 0
  ) -> CGRect? {
    let visible = screen.insetBy(dx: max(screenGap, 0), dy: max(screenGap, 0))
    guard !visible.isEmpty, windowGap >= 0 else { return nil }
    guard cycling, let steps = cycleSteps(in: visible, gap: windowGap) else {
      return frame(for: window, in: screen, windowGap: windowGap, screenGap: screenGap)
    }
    // A point or two of slack: some apps round a window's size their own way.
    func near(_ a: CGRect, _ b: CGRect) -> Bool {
      abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2
        && abs(a.height - b.height) <= 2
    }
    guard let index = steps.firstIndex(where: { near($0, window) }) else { return steps[0] }
    return steps[(index + 1) % steps.count]
  }

  /// A half's ½, ⅔ and ⅓ on its side; nil for the other layouts.
  private func cycleSteps(in visible: CGRect, gap: CGFloat) -> [CGRect]? {
    let fractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]
    func rect(_ fx: CGFloat, _ fy: CGFloat, _ fw: CGFloat, _ fh: CGFloat) -> CGRect {
      Self.tile(fx, fy, fw, fh, in: visible, gap: gap)
    }
    switch self {
    case .leftHalf: return fractions.map { rect(0, 0, $0, 1) }
    case .rightHalf: return fractions.map { rect(1 - $0, 0, $0, 1) }
    case .topHalf: return fractions.map { rect(0, 0, 1, $0) }
    case .bottomHalf: return fractions.map { rect(0, 1 - $0, 1, $0) }
    default: return nil
    }
  }

  /// The part of `visible` from these fractions, each edge inside the screen pulled in by half
  /// of `gap`. As Raycast's on a 2048 × 1121 screen: its size rounded down, and its origin
  /// rounded, or, on the right or bottom edge, that edge less the size, so it ends there.
  private static func tile(
    _ fx: CGFloat, _ fy: CGFloat, _ fw: CGFloat, _ fh: CGFloat, in visible: CGRect, gap: CGFloat
  ) -> CGRect {
    let (x, y, w, h) = (visible.minX, visible.minY, visible.width, visible.height)
    // Inside the screen, with slack for fractions such as ⅓ + ⅔ that sum just short of 1.
    func inner(_ f: CGFloat) -> CGFloat { f > 0.0001 && f < 0.9999 ? gap / 2 : 0 }
    let left = x + w * fx + inner(fx)
    let top = y + h * fy + inner(fy)
    let right = x + w * (fx + fw) - inner(fx + fw)
    let bottom = y + h * (fy + fh) - inner(fy + fh)
    // A hair added first, so a size such as 504 computed as 503.99999 stays 504.
    let width = (right - left + 0.001).rounded(.down)
    let height = (bottom - top + 0.001).rounded(.down)
    return CGRect(
      x: (inner(fx + fw) == 0 && fx > 0.0001 ? right - width : left).rounded(),
      y: (inner(fy + fh) == 0 && fy > 0.0001 ? bottom - height : top).rounded(),
      width: width, height: height)
  }

  /// `frame` moved, not resized, until it's inside `visible`, when it fits.
  static func onScreen(_ frame: CGRect, _ visible: CGRect) -> CGRect {
    CGRect(
      x: min(max(frame.minX, visible.minX), visible.maxX - frame.width),
      y: min(max(frame.minY, visible.minY), visible.maxY - frame.height),
      width: frame.width, height: frame.height
    ).rounded
  }

  /// `window` carried from one screen's visible area to another's, keeping its place and size
  /// in proportion, as moving to the next display does.
  public static func frame(for window: CGRect, from: CGRect, to: CGRect) -> CGRect {
    let sx = to.width / from.width
    let sy = to.height / from.height
    return CGRect(
      x: to.minX + (window.minX - from.minX) * sx, y: to.minY + (window.minY - from.minY) * sy,
      width: window.width * sx, height: window.height * sy
    )
    .rounded
  }
}

extension CGRect {
  /// Whole points, each edge and size rounded on its own, so a window keeps its size (where
  /// `integral` would grow it to cover every partial point).
  fileprivate var rounded: CGRect {
    CGRect(
      x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
  }
}
