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
    case .maximize: "Maximize"
    case .almostMaximize: "Almost Maximize"
    case .center: "Center"
    case .nextDisplay: "Next Display"
    case .previousDisplay: "Previous Display"
    case .restore: "Restore"
    }
  }

  public var settingsKey: String { "window:\(rawValue)" }

  /// Where `window` goes on a screen whose usable area is `visible`; nil for the ones that
  /// need more than one screen or the window's history (next and previous display, restore).
  public func frame(for window: CGRect, in visible: CGRect) -> CGRect? {
    let (x, y, w, h) = (visible.minX, visible.minY, visible.width, visible.height)
    // Edges rounded, sizes taken from them, so neighbors meet and none ends past the screen.
    func part(_ fx: CGFloat, _ fy: CGFloat, _ fw: CGFloat, _ fh: CGFloat) -> CGRect {
      let left = (x + w * fx).rounded()
      let top = (y + h * fy).rounded()
      let right = (x + w * (fx + fw)).rounded()
      let bottom = (y + h * (fy + fh)).rounded()
      return CGRect(x: left, y: top, width: right - left, height: bottom - top)
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
    case .maximize: return visible.rounded
    case .almostMaximize: return part(0.05, 0.05, 0.9, 0.9)
    case .center:
      // Its size kept, but never larger than the screen.
      let size = CGSize(width: min(window.width, w), height: min(window.height, h))
      return CGRect(
        x: x + (w - size.width) / 2, y: y + (h - size.height) / 2, width: size.width,
        height: size.height
      )
      .rounded
    case .nextDisplay, .previousDisplay, .restore:
      return nil
    }
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
