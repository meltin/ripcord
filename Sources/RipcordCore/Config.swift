import Foundation

/// The user's settings. The settings window edits it and saves it back to the same JSON file.
public struct Config: Codable, Equatable, Sendable {
  public var hotkey: String
  public var launchAtLogin: Bool
  public var quicklinks: [Quicklink]
  /// Per-app and per-command settings from the Shortcuts page, by settings key.
  public var items: [String: ItemSettings]

  public init(
    hotkey: String, launchAtLogin: Bool = false, quicklinks: [Quicklink],
    items: [String: ItemSettings] = [:]
  ) {
    self.hotkey = hotkey
    self.launchAtLogin = launchAtLogin
    self.quicklinks = quicklinks
    self.items = items
  }

  // Files written before a key existed still load, with that key's default.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? Config.default.hotkey
    launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    quicklinks = try container.decodeIfPresent([Quicklink].self, forKey: .quicklinks) ?? []
    items = try container.decodeIfPresent([String: ItemSettings].self, forKey: .items) ?? [:]
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
      try Config.default.save(to: url)
      return .default
    }
    return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    // Atomic, so a crash mid-write never leaves a half-written config behind.
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
