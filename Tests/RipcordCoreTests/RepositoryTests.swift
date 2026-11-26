import Foundation
import Testing

@testable import RipcordCore

@Suite struct RepositoryTests {
  @Test func readsTheOriginsWebPage() {
    let config = """
      [core]
      \tbare = false
      [remote "upstream"]
      \turl = git@github.com:apple/swift.git
      [remote "origin"]
      \turl = git@github.com:meltin/ripcord.git
      \tfetch = +refs/heads/*:refs/remotes/origin/*
      """
    #expect(
      RepositoryIndex.originPage(config: config)?.absoluteString
        == "https://github.com/meltin/ripcord")
    #expect(
      RepositoryIndex.originPage(
        config: "[remote \"origin\"]\n url = https://user:token@gitlab.com/a/b.git")?
        .absoluteString == "https://gitlab.com/a/b")
    #expect(RepositoryIndex.originPage(config: "[core]\n bare = false") == nil)
  }

  @Test func findsRepositoriesWithinTheDepth() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for path in [
      "a/.git", "b/c/.git", "b/c/vendor/inner/.git", "d/e/f/g/.git", ".hidden/x/.git",
      "node_modules/y/.git",
    ] {
      try FileManager.default.createDirectory(
        at: root.appending(path: path), withIntermediateDirectories: true)
    }
    let names = RepositoryIndex.scan(roots: [root], depth: 3).map(\.name).sorted()
    // A repository's own folders aren't searched, and d/e/f/g is four folders down.
    #expect(names == ["a", "c"])
  }

  @Test func settingsReadFromOlderConfigs() throws {
    let data = Data(#"{"hotkey": "ctrl+space", "quicklinks": []}"#.utf8)
    #expect(try JSONDecoder().decode(Config.self, from: data).repositories == RepositorySettings())
  }

  @Test func opensInTheAppForEachReturn() throws {
    let repository = Repository(
      url: URL(fileURLWithPath: "/tmp/dev/ripcord"),
      remote: URL(string: "https://github.com/meltin/ripcord"))
    let settings = RepositorySettings(
      openWith: [
        "cmd": "/Applications/Visual Studio Code.app", "option": "/Applications/Ghostty.app",
      ])
    let result = try #require(
      Search.repositorySections(for: "rip", repositories: [repository], settings: settings)
        .first?.results.first)
    #expect(result.actions.map(\.shortcut) == ["↵", "⌘↵", "⌥↵", "⌘O", "⇧⌘F", "⇧⌘C"])
    #expect(
      result.actions.map(\.title).prefix(4) == [
        "Open in Finder", "Open in Visual Studio Code", "Open in Ghostty", "Open on GitHub",
      ])
    #expect(result.action == .open(repository.url))
    #expect(
      Search.repositorySections(for: "zzz", repositories: [repository], settings: settings).isEmpty)
  }
}
