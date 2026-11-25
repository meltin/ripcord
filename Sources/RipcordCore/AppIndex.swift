import Foundation

public struct AppEntry: Equatable, Sendable {
  public let url: URL
  /// The localized name Finder shows (e.g. "システム設定") and the bundle's file name
  /// ("System Settings"), so either one finds the app.
  public let names: [String]
  public let bundleID: String?

  public init(url: URL, names: [String], bundleID: String? = nil) {
    self.url = url
    self.names = names
    self.bundleID = bundleID
  }

  /// The key its settings are stored under. The bundle ID, because one app can show up at two
  /// paths: Safari is scanned at /Applications/Safari.app but runs from a Cryptex volume.
  public var settingsKey: String { bundleID ?? url.path }
}

public enum AppIndex {
  public static let defaultRoots: [URL] = [
    "/Applications",
    "/System/Applications",
    "/System/Library/CoreServices/Finder.app",
    NSHomeDirectory() + "/Applications",
  ].map { URL(fileURLWithPath: $0) }

  // shortcut: rescans the folders on every panel show (a few ms); watch them with FSEvents if
  // that ever shows up in the hotkey latency.
  public static func scan(roots: [URL] = defaultRoots) -> [AppEntry] {
    let bundles = roots.flatMap { root -> [URL] in
      guard root.pathExtension != "app" else {
        return FileManager.default.fileExists(atPath: root.path) ? [root] : []
      }
      guard
        let enumerator = FileManager.default.enumerator(
          at: root, includingPropertiesForKeys: nil,
          options: [.skipsPackageDescendants, .skipsHiddenFiles])
      else { return [] }
      return enumerator.compactMap { item -> URL? in
        guard let url = item as? URL else { return nil }
        // Apps nest at most a few folders deep (e.g. /Applications/Utilities).
        if enumerator.level > 3 { enumerator.skipDescendants() }
        return url.pathExtension == "app" ? url : nil
      }
    }
    let unique = Dictionary(bundles.map { ($0.resolvingSymlinksInPath().path, $0) }) { a, _ in a }
    return unique.values.map { url in
      let localized = FileManager.default.displayName(atPath: url.path)
      let fileName = url.deletingPathExtension().lastPathComponent
      return AppEntry(
        url: url, names: localized == fileName ? [fileName] : [localized, fileName],
        bundleID: bundleID(of: url))
    }
  }

  /// Read from Info.plist directly: `Bundle(url:)` caches every bundle it opens for good.
  static func bundleID(of app: URL) -> String? {
    let plist = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
    return plist?["CFBundleIdentifier"] as? String
  }
}
