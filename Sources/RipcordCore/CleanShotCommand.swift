import Foundation

/// CleanShot X's commands, run through its URL scheme (`cleanshot://…`), as Raycast's CleanShot
/// extension does. Add Quick Access Overlay is left out: it needs a file to open.
public enum CleanShotCommand: String, CaseIterable, Sendable {
  // Raw values are the URL scheme's commands, documented at cleanshot.com/docs-api.
  case allInOne = "all-in-one"
  case captureArea = "capture-area"
  case capturePreviousArea = "capture-previous-area"
  case captureFullscreen = "capture-fullscreen"
  case captureWindow = "capture-window"
  case selfTimer = "self-timer"
  case scrollingCapture = "scrolling-capture"
  case recordScreen = "record-screen"
  case captureText = "capture-text"
  case pin = "pin"
  case openAnnotate = "open-annotate"
  case openFromClipboard = "open-from-clipboard"
  case openHistory = "open-history"
  case restoreRecentlyClosed = "restore-recently-closed"
  case toggleDesktopIcons = "toggle-desktop-icons"
  case hideDesktopIcons = "hide-desktop-icons"
  case showDesktopIcons = "show-desktop-icons"
  case openSettings = "open-settings"

  /// CleanShot X's bundle ID, for finding the app and hiding the commands without it.
  public static let bundleID = "pl.maketheweb.cleanshotx"

  /// Whether an app is a CleanShot X: its ID, or one built on it, as a store's edition may be.
  public static func isCleanShot(bundleID: String?) -> Bool {
    bundleID.map { $0 == Self.bundleID || $0.hasPrefix(Self.bundleID + "-") } ?? false
  }

  public var title: String {
    switch self {
    case .allInOne: "All-In-One"
    case .captureArea: "Capture Area"
    case .capturePreviousArea: "Capture Previous Area"
    case .captureFullscreen: "Capture Fullscreen"
    case .captureWindow: "Capture Window"
    case .selfTimer: "Self-Timer"
    case .scrollingCapture: "Scrolling Capture"
    case .recordScreen: "Record Screen"
    case .captureText: "Capture Text"
    case .pin: "Pin Screenshot"
    case .openAnnotate: "Open Annotate"
    case .openFromClipboard: "Annotate Clipboard Image"
    case .openHistory: "Open History"
    case .restoreRecentlyClosed: "Restore Recently Closed"
    case .toggleDesktopIcons: "Toggle Desktop Icons"
    case .hideDesktopIcons: "Hide Desktop Icons"
    case .showDesktopIcons: "Show Desktop Icons"
    case .openSettings: "CleanShot Settings"
    }
  }

  public var settingsKey: String { "cleanshot:\(rawValue)" }

  public var url: URL? { URL(string: "cleanshot://\(rawValue)") }
}
