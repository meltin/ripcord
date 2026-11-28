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

  @Test func listsARepositoryReachedFromTwoFoldersOnce() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root.appending(path: "oss/ripcord/.git"), withIntermediateDirectories: true)
    let found = RepositoryIndex.scan(roots: [root, root.appending(path: "oss")], depth: 3)
    #expect(found.map(\.name) == ["ripcord"])
  }

  @Test func readsAWorktreesRemoteFromItsMainRepository() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let main = root.appending(path: "ripcord")
    let gitDir = main.appending(path: ".git/worktrees/feature")
    try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
    try "[remote \"origin\"]\n\turl = git@github.com:meltin/ripcord.git\n".write(
      to: main.appending(path: ".git/config"), atomically: true, encoding: .utf8)
    try "../..\n".write(to: gitDir.appending(path: "commondir"), atomically: true, encoding: .utf8)
    let worktree = root.appending(path: "feature")
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
    try "gitdir: \(gitDir.path)\n".write(
      to: worktree.appending(path: ".git"), atomically: true, encoding: .utf8)
    let found = RepositoryIndex.scan(roots: [root], depth: 1)
    #expect(
      found.first { $0.name == "feature" }?.remote?.absoluteString
        == "https://github.com/meltin/ripcord")
  }

  @Test func writesTheHomeFolderAsTildeOnlyForItsOwnPaths() {
    #expect(Search.tildePath("/Users/al/dev", home: "/Users/al") == "~/dev")
    #expect(Search.tildePath("/Users/al", home: "/Users/al") == "~")
    #expect(Search.tildePath("/Users/alex/dev", home: "/Users/al") == "/Users/alex/dev")
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
    // Git Repos' keys: Open on GitHub ⇧⌘O, Copy Path ⌘.
    #expect(result.actions.map(\.shortcut) == ["↵", "⌘↵", "⌥↵", "⇧⌘O", "⇧⌘F", "⌘.", "⇧⌘,"])
    #expect(
      result.actions.map(\.title).prefix(4) == [
        "Open in Finder", "Open in Visual Studio Code", "Open in Ghostty", "Open on GitHub",
      ])
    #expect(result.action == .open(repository.url))
    #expect(
      Search.repositorySections(for: "zzz", repositories: [repository], settings: settings).isEmpty)
    // The home folder's own path isn't something to search by, but a pasted full path is.
    let inHome = Repository(url: URL(fileURLWithPath: "/Users/al/dev/ripcord"), remote: nil)
    func names(_ query: String) -> [String] {
      Search.repositorySections(
        for: query, repositories: [inHome], settings: settings, home: "/Users/al"
      ).flatMap(\.results).map(\.title)
    }
    #expect(names("Users").isEmpty)
    #expect(names("/Users/al/dev") == ["ripcord"])
  }

  /// Clone Repo hands git the URL after "--", and never text git would read as an option.
  @Test func clonesOnlyARepositoryURL() {
    #expect(
      CloneRepo.gitArguments(url: " https://github.com/o/r.git ") == [
        "clone", "--", "https://github.com/o/r.git",
      ])
    #expect(CloneRepo.gitArguments(url: "") == nil)
    #expect(CloneRepo.gitArguments(url: "--upload-pack=touch /tmp/x") == nil)
    #expect(CloneRepo.gitArguments(url: "a b") == nil)
    #expect(CloneRepo.folderName(for: "https://github.com/o/repo.git") == "repo")
    #expect(CloneRepo.folderName(for: "git@github.com:o/tool") == "tool")
  }

  /// Remove Repo's list: Return removes, ⇧⌘D force-removes, as Raycast's does.
  @Test func removeRepoOffersRemoveAndForceRemove() {
    let repository = Repository(url: URL(fileURLWithPath: "/Users/al/dev/ripcord"), remote: nil)
    let row = Search.repositorySections(
      for: "", repositories: [repository], settings: RepositorySettings(), removing: true
    ).first?.results.first
    #expect(row?.actions.map(\.title) == ["Remove Repository", "Force Remove Repository"])
    #expect(row?.action == .removeRepository(repository.url, force: false))
    #expect(row?.actions.last?.shortcut == "⇧⌘D")
  }

  /// Clone Repo's error: git's `fatal:` line over the hint that follows it.
  @Test func showsGitsFatalLine() {
    let ssh = """
      git@github.com: Permission denied (publickey).
      fatal: Could not read from remote repository.

      Please make sure you have the correct access rights
      and the repository exists.
      """
    #expect(CloneRepo.failure(ssh) == "fatal: Could not read from remote repository.")
    #expect(CloneRepo.failure("error: something\n") == "error: something")
    #expect(CloneRepo.failure("") == "git clone failed.")
  }

  /// Remove Repo refuses what isn't safe elsewhere: uncommitted or untracked work, commits not
  /// pushed, or a folder git can't read.
  @Test func removeRepoChecksForUnsavedWork() throws {
    let base = FileManager.default.temporaryDirectory.appending(
      path: "ripcord-remove-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    func git(_ arguments: String..., in folder: URL) throws {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      process.arguments = ["-c", "user.name=t", "-c", "user.email=t@example.invalid"] + arguments
      process.currentDirectoryURL = folder
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      process.waitUntilExit()
      #expect(process.terminationStatus == 0, "git \(arguments)")
    }
    let remote = base.appending(path: "remote.git")
    let repo = base.appending(path: "repo")
    let plain = base.appending(path: "plain")
    for folder in [remote, repo, plain] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    try git("init", "-q", "--bare", in: remote)
    try git("init", "-q", in: repo)
    try Data("a".utf8).write(to: repo.appending(path: "a.txt"))
    #expect(RepositoryCheck.unsaved(in: repo) == "There are uncommitted changes or untracked files")
    try git("add", "a.txt", in: repo)
    try git("commit", "-q", "-m", "a", in: repo)
    #expect(RepositoryCheck.unsaved(in: repo) == nil)
    try git("remote", "add", "origin", remote.path, in: repo)
    #expect(RepositoryCheck.unsaved(in: repo) == "There are local commits that haven't been pushed")
    try git("push", "-q", "origin", "HEAD", in: repo)
    #expect(RepositoryCheck.unsaved(in: repo) == nil)
    #expect(RepositoryCheck.unsaved(in: plain) != nil)
  }

  /// A worktree or submodule, its `.git` a file, is told apart for Remove Repo to leave out.
  @Test func marksWorktreesAndSubmodules() throws {
    let base = FileManager.default.temporaryDirectory.appending(
      path: "ripcord-linked-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    let own = base.appending(path: "own/.git")
    let linked = base.appending(path: "linked")
    try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
    try Data("gitdir: /nowhere\n".utf8).write(to: linked.appending(path: ".git"))
    let found = RepositoryIndex.scan(roots: [base], depth: 1)
    #expect(found.map(\.name).sorted() == ["linked", "own"])
    #expect(found.filter(\.isLinkedCheckout).map(\.name) == ["linked"])
  }
}
