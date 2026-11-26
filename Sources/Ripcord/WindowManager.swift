import AppKit
import RipcordCore

/// Moves and resizes the frontmost app's focused window through the Accessibility API.
@MainActor
final class WindowManager {
  /// For Restore: each window's frame before Ripcord first placed it, and where it last put it,
  /// so a run of layouts still restores the frame from before them; a few windows' worth.
  private var history: [(window: AXUIElement, original: CGRect, placed: CGRect)] = []

  /// Nil when done, or a message to show.
  func apply(_ layout: WindowLayout, to app: NSRunningApplication?) -> String? {
    let permission = AccessibilityPermission.check()
    guard permission.trusted else {
      // macOS's own request is up; a message on top of it would only cover it.
      if permission.asked {
        NSSound.beep()
        return nil
      }
      return
        "Allow Ripcord under System Settings › Privacy & Security › Accessibility, then try again."
    }
    // Ripcord's own windows (Settings) aren't moved.
    guard let app, app != NSRunningApplication.current else {
      NSSound.beep()
      return nil
    }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    // Half a second, not the default six, per call: a hung app mustn't hang Ripcord with it.
    AXUIElementSetMessagingTimeout(appElement, 0.5)
    guard let window: AXUIElement = attribute(appElement, kAXFocusedWindowAttribute),
      let frame = frame(of: window)
    else { return noWindow }

    let screens = visibleFrames()
    guard !screens.isEmpty else { return nil }
    let center = CGPoint(x: frame.midX, y: frame.midY)
    let index = screens.firstIndex { $0.full.contains(center) } ?? 0
    let target: CGRect
    switch layout {
    case .restore:
      guard let saved = history.last(where: { CFEqual($0.window, window) }) else {
        NSSound.beep()
        return nil
      }
      target = saved.original
    case .nextDisplay, .previousDisplay:
      guard screens.count > 1 else {
        NSSound.beep()
        return nil
      }
      let step = layout == .nextDisplay ? 1 : screens.count - 1
      target = WindowLayout.frame(
        for: frame, from: screens[index].visible,
        to: screens[(index + step) % screens.count].visible
      )
    default:
      guard let placed = layout.frame(for: frame, in: screens[index].visible) else { return nil }
      target = placed
    }

    guard move(window, of: appElement, to: target) else {
      // Full screen, or a window that can't be moved or resized.
      NSSound.beep()
      return nil
    }
    let earlier = history.last { CFEqual($0.window, window) }
    // Still where Ripcord put it: keep the frame from before the first layout.
    let original = earlier.flatMap { $0.placed == frame ? $0.original : nil } ?? frame
    history = Array(
      (history.filter { !CFEqual($0.window, window) }
        + (layout == .restore ? [] : [(window, original, self.frame(of: window) ?? target)]))
        .suffix(20))
    return nil
  }

  private let noWindow = "There's no window in front to move."

  /// Position, then size, then position again: a window can't grow past the screen's edge from
  /// where it is, and one with a minimum size ends up a little off until it's moved back.
  /// False when the window refused the new position or size.
  private func move(_ window: AXUIElement, of app: AXUIElement, to frame: CGRect) -> Bool {
    // Apps with AXEnhancedUserInterface on (VoiceOver turns it on) animate each change and drop
    // some; it's off while moving, as Rectangle does.
    let enhanced = "AXEnhancedUserInterface" as CFString
    let wasEnhanced: Bool = attribute(app, enhanced) ?? false
    if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanFalse) }
    defer { if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanTrue) } }
    var origin = frame.origin
    var size = frame.size
    guard let position = AXValueCreate(.cgPoint, &origin),
      let dimensions = AXValueCreate(.cgSize, &size)
    else { return false }
    let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    return moved == .success || resized == .success
  }

  private func frame(of window: AXUIElement) -> CGRect? {
    guard let position: AXValue = attribute(window, kAXPositionAttribute),
      let size: AXValue = attribute(window, kAXSizeAttribute)
    else { return nil }
    var origin = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position, .cgPoint, &origin),
      AXValueGetValue(size, .cgSize, &dimensions)
    else { return nil }
    return CGRect(origin: origin, size: dimensions)
  }

  private func attribute<Value>(_ element: AXUIElement, _ name: String) -> Value? {
    attribute(element, name as CFString)
  }

  private func attribute<Value>(_ element: AXUIElement, _ name: CFString) -> Value? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value as? Value
  }

  /// Each screen's whole and usable area in the Accessibility API's coordinates: the origin at
  /// the top left of the main display, y growing downward, where NSScreen's grows upward.
  private func visibleFrames() -> [(full: CGRect, visible: CGRect)] {
    guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return [] }
    func flipped(_ rect: CGRect) -> CGRect {
      CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    // Left to right, then top to bottom, so Next Display goes the way the screens are laid out
    // rather than in the order macOS lists them.
    return NSScreen.screens.map { (flipped($0.frame), flipped($0.visibleFrame)) }
      .sorted { ($0.full.minX, $0.full.minY) < ($1.full.minX, $1.full.minY) }
  }
}
