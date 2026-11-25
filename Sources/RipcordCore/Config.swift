import Foundation

/// The user's settings, kept as JSON until the settings window exists.
public struct Config: Codable, Equatable, Sendable {
  public let hotkey: String
  public let quicklinks: [Quicklink]

  public init(hotkey: String, quicklinks: [Quicklink]) {
    self.hotkey = hotkey
    self.quicklinks = quicklinks
  }

  public static let `default` = Config(
    hotkey: "cmd+space",
    quicklinks: [
      Quicklink(
        name: "Google Search", url: "https://www.google.com/search?q={query}", keyword: "g"),
      Quicklink(name: "GitHub Search", url: "https://github.com/search?q={query}", keyword: "gh"),
    ])

  /// Reads `url`, writing the defaults there first when the file doesn't exist yet.
  public static func load(from url: URL) throws -> Config {
    guard FileManager.default.fileExists(atPath: url.path) else {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(Config.default).write(to: url)
      return .default
    }
    return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
  }
}
