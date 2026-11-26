import Foundation

/// A local Git repository found under one of the folders Search Repositories scans.
public struct Repository: Equatable, Sendable {
  public let url: URL
  /// The web page of its `origin` remote, for Open on GitHub; nil without one.
  public let remote: URL?

  public var name: String { url.lastPathComponent }
}

/// Git Repositories' settings: where to look and which app each Return opens a repository in.
public struct RepositorySettings: Codable, Equatable, Sendable {
  /// Folders to scan, `~` allowed.
  public var folders: [String]
  /// How many folders down from each one a repository may sit.
  public var depth: Int
  /// The app (a path) each of ↵, ⌘↵, ⌥↵, ⌃↵ and ⇧↵ opens a repository in, keyed by
  /// `OpenKey.rawValue`; ↵ without one shows it in Finder.
  public var openWith: [String: String]

  public init(
    folders: [String] = ["~/dev", "~/Developer", "~/src", "~/Projects"], depth: Int = 3,
    openWith: [String: String] = [:]
  ) {
    self.folders = folders
    self.depth = depth
    self.openWith = openWith
  }

  /// The Return variants an app can be assigned to, in the order the settings list them.
  public enum OpenKey: String, CaseIterable, Sendable {
    case plain = "return"
    case command = "cmd"
    case option = "option"
    case control = "ctrl"
    case shift = "shift"

    /// As the panel's menus write it.
    public var shortcut: String {
      switch self {
      case .plain: "↵"
      case .command: "⌘↵"
      case .option: "⌥↵"
      case .control: "⌃↵"
      case .shift: "⇧↵"
      }
    }
  }
}

public enum RepositoryIndex {
  /// Every folder holding a `.git` under `roots`, at most `depth` folders down; a repository's
  /// own folders aren't searched further, and hidden folders and node_modules are skipped.
  /// A repository reached from two folders (`~/dev` and `~/dev/oss`) is listed once.
  public static func scan(roots: [URL], depth: Int) -> [Repository] {
    var seen = Set<String>()
    return roots.flatMap { root -> [Repository] in
      var found: [Repository] = []
      func walk(_ folder: URL, level: Int) {
        if isRepository(folder) {
          found.append(Repository(url: folder, remote: remote(of: folder)))
          return
        }
        guard level < depth,
          let children = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return }
        for child in children
        where child.lastPathComponent != "node_modules"
          && (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        {
          walk(child, level: level + 1)
        }
      }
      walk(root, level: 0)
      return found
    }
    .filter { seen.insert($0.url.resolvingSymlinksInPath().path).inserted }
  }

  /// `~/dev` and the like as folder URLs, the ones that exist.
  public static func roots(_ folders: [String]) -> [URL] {
    folders.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  private static func isRepository(_ folder: URL) -> Bool {
    // A file for worktrees and submodules, a folder otherwise.
    FileManager.default.fileExists(atPath: folder.appending(path: ".git").path)
  }

  private static func remote(of repository: URL) -> URL? {
    guard let config = try? String(contentsOf: configFile(of: repository), encoding: .utf8)
    else { return nil }
    return originPage(config: config)
  }

  /// `.git/config`, or for a worktree or submodule, whose `.git` is a file naming its git
  /// folder, that folder's config, or the main repository's for a worktree (`commondir`).
  private static func configFile(of repository: URL) -> URL {
    let dotGit = repository.appending(path: ".git")
    guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
      pointer.hasPrefix("gitdir:")
    else { return dotGit.appending(path: "config") }
    let gitDir = resolve(pointer.dropFirst("gitdir:".count), against: repository)
    let common = (try? String(contentsOf: gitDir.appending(path: "commondir"), encoding: .utf8))
      .map { resolve(Substring($0), against: gitDir) }
    return (common ?? gitDir).appending(path: "config")
  }

  /// A path as git writes it in those files: absolute, or relative to `base`.
  private static func resolve(_ path: Substring, against base: URL) -> URL {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("/")
      ? URL(fileURLWithPath: trimmed) : base.appending(path: trimmed).standardizedFileURL
  }

  /// The web page of the `origin` remote in a `.git/config`'s text: an SSH address such as
  /// `git@github.com:owner/repo.git` or an https one, without `.git` or credentials.
  public static func originPage(config: String) -> URL? {
    var inOrigin = false
    for line in config.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("[") {
        inOrigin = trimmed == #"[remote "origin"]"#
        continue
      }
      guard inOrigin, trimmed.hasPrefix("url") else { continue }
      let value = trimmed.split(separator: "=", maxSplits: 1).last.map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      return value.flatMap(webPage)
    }
    return nil
  }

  private static func webPage(_ address: String) -> URL? {
    let path = address.hasSuffix(".git") ? String(address.dropLast(4)) : address
    if path.hasPrefix("git@"), let colon = path.firstIndex(of: ":") {
      // git@host:owner/repo
      let host = path[path.index(path.startIndex, offsetBy: 4)..<colon]
      return URL(string: "https://\(host)/\(path[path.index(after: colon)...])")
    }
    guard var components = URLComponents(string: path),
      ["https", "http", "ssh"].contains(components.scheme)
    else { return nil }
    components.scheme = "https"
    components.user = nil
    components.password = nil
    components.port = nil
    return components.url
  }
}
