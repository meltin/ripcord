import Foundation

/// The front browser window's current tab, read with AppleScript to fill Add Bookmark, as
/// Raycast's does. Only browsers whose scripting dictionary was checked are listed.
public enum BrowserTab {
  /// The AppleScript returning the tab's URL, a line feed, then its title; nil for an app that
  /// isn't a browser listed here.
  public static func script(forBundleID bundleID: String) -> String? {
    let terms: (tab: String, title: String)? =
      switch bundleID {
      // Safari.sdef: "current tab" of a window, a tab's "name".
      case "com.apple.Safari": ("current tab", "name")
      // Chromium's dictionary, which Arc's follows: "active tab", a tab's "title".
      case "com.google.Chrome", "company.thebrowser.Browser": ("active tab", "title")
      default: nil
      }
    guard let terms else { return nil }
    return """
      with timeout of 5 seconds
        tell application id "\(bundleID)"
          if (count of windows) is 0 then return ""
          set theTab to \(terms.tab) of front window
          return (URL of theTab) & linefeed & (\(terms.title) of theTab)
        end tell
      end timeout
      """
  }

  /// The URL and title from the script's output; nil for none, or an empty window.
  public static func parse(_ output: String) -> (url: String, title: String)? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let url = trimmed.prefix { !$0.isNewline }
    let title = trimmed.dropFirst(url.count).trimmingCharacters(in: .whitespacesAndNewlines)
    // Web pages and files only: a new tab's chrome://newtab or about:blank isn't a bookmark.
    guard let scheme = URL(string: String(url))?.scheme?.lowercased(),
      ["http", "https", "file"].contains(scheme)
    else { return nil }
    return (String(url), title)
  }
}
