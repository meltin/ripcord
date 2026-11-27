import Foundation

/// Spots a modifier pressed twice on its own, as Raycast's ⇧⇧ hotkeys: each press goes down and
/// comes up with no other modifier or key, and the second starts soon after the first ends.
/// Fed the modifiers held after every change, as Carbon flags of ⌃⌥⇧⌘ only.
public struct DoubleTapDetector: Sendable {
  /// The longest a tap may be held, and the longest gap between the two.
  public static let interval: TimeInterval = 0.35

  private var held: UInt32 = 0
  /// The press in progress, if it's one modifier alone.
  private var press: (modifier: UInt32, at: TimeInterval)?
  /// The tap just finished, waiting for its second.
  private var tap: (modifier: UInt32, at: TimeInterval)?

  public init() {}

  /// The modifier whose double tap this change completes, if any.
  public mutating func modifiersChanged(to modifiers: UInt32, at time: TimeInterval) -> UInt32? {
    // Caps Lock and fn change the flags without changing these four.
    guard modifiers != held else { return nil }
    defer { held = modifiers }
    if modifiers == 0 {
      guard let press else { return nil }
      self.press = nil
      guard time - press.at <= Self.interval else {
        tap = nil
        return nil
      }
      if let tap, tap.modifier == press.modifier, press.at - tap.at <= Self.interval {
        self.tap = nil
        return press.modifier
      }
      tap = (press.modifier, time)
      return nil
    }
    // One modifier coming down from none starts a press; anything else is a chord.
    if held == 0, modifiers.nonzeroBitCount == 1 {
      press = (modifiers, time)
    } else {
      press = nil
      tap = nil
    }
    return nil
  }

  /// A key or a mouse button went down: whatever was pressed is part of a shortcut, a ⌘-click
  /// or typing, not a tap.
  public mutating func keyPressed() {
    press = nil
    tap = nil
  }
}
