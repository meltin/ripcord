import Foundation

/// A Raycast Script Command: an executable file whose comments carry `@raycast.*` metadata, as
/// github.com/raycast/script-commands documents it.
public struct ScriptCommand: Equatable, Sendable {
  public let url: URL
  public let title: String
  public let mode: Mode
  /// An emoji, or nil for the default icon. A file path or URL icon isn't drawn yet.
  public let icon: String?
  /// The subtitle; the folder's name when the script names none, as Raycast does.
  public let packageName: String
  /// Where the script runs; its own folder unless `currentDirectoryPath` says otherwise.
  public let directory: URL

  public enum Mode: String, Equatable, Sendable {
    /// The last line of output in a toast, the panel kept open.
    case compact
    /// The last line of output over the screen after the panel closes.
    case silent
    /// All of the output in the panel, as a terminal shows it.
    case fullOutput
  }

  /// The settings key for its alias, hotkey and favorite: its path.
  public var settingsKey: String { "script:\(url.path)" }

  /// Reads the metadata from the first lines of `text`; nil for a file that isn't a Script
  /// Command, or one using what Ripcord doesn't run yet (arguments, inline with a refresh time,
  /// a confirmation), which is left out rather than run differently.
  public static func parse(_ text: String, url: URL) -> ScriptCommand? {
    var values: [String: String] = [:]
    // Comments starting `#` or `//`, as Raycast's README requires.
    for line in text.split(whereSeparator: \.isNewline).prefix(Self.headLines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let comment =
        trimmed.hasPrefix("//")
        ? trimmed.dropFirst(2) : trimmed.hasPrefix("#") ? trimmed.dropFirst(1) : nil
      guard let body = comment?.trimmingCharacters(in: .whitespaces),
        body.hasPrefix("@raycast.")
      else { continue }
      let pair = body.dropFirst("@raycast.".count)
      let key = String(pair.prefix { !$0.isWhitespace })
      let value = pair.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
      if values[key] == nil { values[key] = value }
    }
    guard values["schemaVersion"] == "1", let title = values["title"], !title.isEmpty,
      let modeText = values["mode"]
    else { return nil }
    // inline without a refresh time runs as compact, as Raycast's docs say.
    let mode: Mode? =
      switch modeText {
      case "compact": .compact
      case "silent": .silent
      case "fullOutput": .fullOutput
      case "inline" where values["refreshTime"] == nil: .compact
      default: nil
      }
    guard let mode, values["needsConfirmation"] != "true",
      !values.keys.contains(where: { $0.hasPrefix("argument") })
    else { return nil }
    let folder = url.deletingLastPathComponent()
    let directory = values["currentDirectoryPath"].map { path in
      URL(
        fileURLWithPath: (path as NSString).expandingTildeInPath,
        relativeTo: folder
      ).standardizedFileURL
    }
    // An emoji, not a file name: digits and # count as emoji too, so a picture is required.
    let icon = values["icon"].flatMap { icon in
      icon.unicodeScalars.first.map { $0.properties.isEmojiPresentation || $0.value > 0x2000 }
        == true && !icon.contains(".") && !icon.contains("/") ? icon : nil
    }
    return ScriptCommand(
      url: url, title: title, mode: mode, icon: icon,
      packageName: values["packageName"] ?? folder.lastPathComponent,
      directory: directory ?? folder)
  }

  /// How far into a file the metadata is looked for.
  static let headLines = 40

  /// The Script Commands in `folders` (not their subfolders): executable files, `.template.`
  /// ones left out as Raycast leaves them, read only for their first lines.
  public static func scan(_ folders: [URL]) -> [ScriptCommand] {
    let fileManager = FileManager.default
    return folders.flatMap { folder in
      let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
      return names.sorted().compactMap { name -> ScriptCommand? in
        let url = folder.appending(path: name)
        var isFolder: ObjCBool = false
        guard !name.contains(".template."), !name.hasPrefix("."),
          // Following a symlink, as scripts are often linked in from a checkout.
          fileManager.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue,
          fileManager.isExecutableFile(atPath: url.path),
          let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 8192)) ?? Data()
        return parse(String(decoding: head, as: UTF8.self), url: url)
      }
    }
  }

  /// `output` without terminal color codes, which fullOutput would show as junk: colors aren't
  /// drawn yet.
  public static func plain(_ output: String) -> String {
    output
      .replacing(/\u{1B}\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\)/, with: "")  // OSC, as links
      .replacing(/\u{1B}\[[0-?]*[ -\/]*[@-~]/, with: "")
  }

  /// The last line of `output` with text, for a toast; nil for none.
  public static func lastLine(of output: String) -> String? {
    output.split(whereSeparator: \.isNewline).last {
      !$0.trimmingCharacters(in: .whitespaces).isEmpty
    }
    .map { String($0).trimmingCharacters(in: .whitespaces) }
  }
}
