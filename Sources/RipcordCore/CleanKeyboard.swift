import Foundation

/// Clean Keyboard's settings, as Raycast's Clean Keyboard has them: how long it runs without
/// asking, and whether the function row and the mouse's clicks are off too.
public struct CleanKeyboardSettings: Codable, Equatable, Sendable {
  /// What Clean Keyboard runs for when it's run without a time typed after it.
  public enum Duration: String, Codable, CaseIterable, Sendable {
    case ask, seconds15, seconds30, minute1, minutes2, minutes5, hour1, hours24, forever

    public var title: String {
      switch self {
      case .ask: "Always Ask"
      case .seconds15: "15 Seconds"
      case .seconds30: "30 Seconds"
      case .minute1: "1 Minute"
      case .minutes2: "2 Minutes"
      case .minutes5: "5 Minutes"
      case .hour1: "1 Hour"
      case .hours24: "24 Hours"
      case .forever: "Forever"
      }
    }

    /// Nil for Always Ask; infinity for Forever, until ⌃⌥⌘↩ or the menu bar ends it.
    public var seconds: TimeInterval? {
      switch self {
      case .ask: nil
      case .seconds15: 15
      case .seconds30: 30
      case .minute1: 60
      case .minutes2: 120
      case .minutes5: 300
      case .hour1: 3600
      case .hours24: 86_400
      case .forever: .infinity
      }
    }
  }

  public var defaultDuration: Duration
  /// The function row's keys, media and brightness keys among them, are off too. On by default,
  /// unlike Raycast's, as Clean Keyboard always turned them off before this setting.
  public var lockFunctionKeys: Bool
  /// Clicks and drags are off too; scrolling still works.
  public var lockMouseClicks: Bool

  public init(
    defaultDuration: Duration = .ask, lockFunctionKeys: Bool = true, lockMouseClicks: Bool = false
  ) {
    self.defaultDuration = defaultDuration
    self.lockFunctionKeys = lockFunctionKeys
    self.lockMouseClicks = lockMouseClicks
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      defaultDuration: (try? container.decodeIfPresent(Duration.self, forKey: .defaultDuration))
        ?? .ask,
      lockFunctionKeys: try container.decodeIfPresent(Bool.self, forKey: .lockFunctionKeys)
        ?? true,
      lockMouseClicks: try container.decodeIfPresent(Bool.self, forKey: .lockMouseClicks) ?? false)
  }
}
