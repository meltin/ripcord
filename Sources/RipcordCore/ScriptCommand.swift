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
  /// Up to three, typed into fields beside the search bar and passed as $1, $2 and $3.
  public var arguments: [Argument] = []
  /// Asks before it runs, as `needsConfirmation` says.
  public var needsConfirmation = false

  /// An `argumentN` field, as Raycast's ARGUMENTS.md documents it.
  public struct Argument: Equatable, Sendable, Decodable {
    public let type: Kind
    public let placeholder: String
    public var optional: Bool? = nil
    public var percentEncoded: Bool? = nil
    /// A dropdown's items.
    public var data: [Option]? = nil

    public enum Kind: String, Equatable, Sendable, Decodable {
      case text, password, dropdown
    }

    public struct Option: Equatable, Sendable, Decodable, Hashable {
      public let title: String
      public let value: String
    }

    public var isRequired: Bool { optional != true }

    /// What a field left alone holds: a dropdown's first item, as a menu always shows one.
    public var initialValue: String { type == .dropdown ? data?.first?.value ?? "" : "" }
  }

  /// `values` with each one left alone at its field's initial value.
  private func resolved(_ values: [String]) -> [String] {
    arguments.indices.map { index in
      let value = values.indices.contains(index) ? values[index] : ""
      return value.isEmpty ? arguments[index].initialValue : value
    }
  }

  /// The index of the first required argument left empty in `values`; nil when it can run.
  public func firstMissing(in values: [String]) -> Int? {
    let values = resolved(values)
    return arguments.indices.first { arguments[$0].isRequired && values[$0].isEmpty }
  }

  /// What the process gets as $1…: each value, percent-encoded where asked; an optional one
  /// left empty is "" so the later ones keep their places.
  public func processArguments(_ values: [String]) -> [String] {
    let values = resolved(values)
    return arguments.indices.map { index in
      let value = values[index]
      guard arguments[index].percentEncoded == true else { return value }
      // What JavaScript's encodeURIComponent keeps, as Raycast encodes: a space is %20, & is %26.
      let kept = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
      return value.addingPercentEncoding(withAllowedCharacters: kept) ?? value
    }
  }

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
  /// Command, or one using what Ripcord doesn't run yet (inline with a refresh time), which is
  /// left out rather than run differently.
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
    guard let mode else { return nil }
    // argument1 to 3 in order; one that doesn't decode (broken JSON, an unknown type) or a gap
    // leaves the script out.
    let given = values.keys.filter { $0.hasPrefix("argument") }
    let arguments = (1...3).prefix { values["argument\($0)"] != nil }.compactMap { number in
      values["argument\(number)"].flatMap {
        try? JSONDecoder().decode(Argument.self, from: Data($0.utf8))
      }
    }
    // A dropdown with nothing to pick could never run.
    guard arguments.count == given.count,
      !arguments.contains(where: { $0.type == .dropdown && ($0.data ?? []).isEmpty })
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
      directory: directory ?? folder, arguments: arguments,
      needsConfirmation: values["needsConfirmation"] == "true")
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
