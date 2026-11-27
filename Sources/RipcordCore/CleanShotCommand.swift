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
    // Raycast's CleanShot X extension's titles.
    case .allInOne: "All in One"
    case .captureArea: "Capture Area"
    case .capturePreviousArea: "Capture Previous Area"
    case .captureFullscreen: "Capture Fullscreen"
    case .captureWindow: "Capture Window"
    case .selfTimer: "Self Timer"
    case .scrollingCapture: "Scrolling Capture"
    case .recordScreen: "Record Screen"
    case .captureText: "Capture Text (OCR)"
    case .pin: "Pin Screenshot"
    case .openAnnotate: "Annotate"
    case .openFromClipboard: "Open from Clipboard"
    case .openHistory: "Open History"
    case .restoreRecentlyClosed: "Restore Recently Closed"
    case .toggleDesktopIcons: "Toggle Desktop Icons"
    case .hideDesktopIcons: "Hide Desktop Icons"
    case .showDesktopIcons: "Show Desktop Icons"
    case .openSettings: "Open Settings"
    }
  }

  public var settingsKey: String { "cleanshot:\(rawValue)" }

  public var url: URL? { url(argument: "") }

  /// Its argument field beside the search bar, as Raycast's extension has it: what to do with a
  /// capture, or the settings tab to open. Left alone, CleanShot X does as it's set to.
  public var arguments: [ScriptCommand.Argument]? {
    switch self {
    case .captureArea, .capturePreviousArea, .captureFullscreen, .captureWindow, .selfTimer:
      [
        ScriptCommand.Argument(
          type: .dropdown, placeholder: "Action", optional: true,
          data: [
            ("Copy", "copy"), ("Save", "save"), ("Annotate", "annotate"),
            ("Upload", "upload"), ("Pin", "pin"),
          ].map { .init(title: $0.0, value: $0.1) })
      ]
    case .openSettings:
      [
        ScriptCommand.Argument(
          type: .dropdown, placeholder: "Tab", optional: true,
          data: [
            ("General", "general"), ("Wallpaper", "wallpaper"), ("Shortcuts", "shortcuts"),
            ("Quick Access", "quickaccess"), ("Recording", "recording"),
            ("Screenshots", "screenshots"), ("Annotate", "annotate"), ("Cloud", "cloud"),
            ("Advanced", "advanced"), ("About", "about"),
          ].map { .init(title: $0.0, value: $0.1) })
      ]
    default: nil
    }
  }

  /// The URL with `argument` as its action or tab; empty, without one.
  public func url(argument: String) -> URL? {
    var components = URLComponents(string: "cleanshot://\(rawValue)")
    if !argument.isEmpty {
      components?.queryItems = [
        URLQueryItem(name: self == .openSettings ? "tab" : "action", value: argument)
      ]
    }
    return components?.url
  }
}
