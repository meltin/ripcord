import Foundation
import Testing

@testable import RipcordCore

@Suite struct ScriptCommandTests {
  let url = URL(fileURLWithPath: "/tmp/Tools/hello.sh")

  func script(_ lines: String...) -> ScriptCommand? {
    ScriptCommand.parse((["#!/bin/bash"] + lines).joined(separator: "\n"), url: url)
  }

  @Test func readsRaycastsMetadata() throws {
    let hello = try #require(
      script(
        "# @raycast.schemaVersion 1", "# @raycast.title Say Hello", "# @raycast.mode silent",
        "# @raycast.icon 👋", "echo hi"))
    #expect(hello.title == "Say Hello")
    #expect(hello.mode == .silent)
    #expect(hello.icon == "👋")
    // No packageName: the folder's name, as Raycast infers it.
    #expect(hello.packageName == "Tools")
    #expect(hello.directory.path == "/tmp/Tools")
    #expect(hello.settingsKey == "script:/tmp/Tools/hello.sh")
    // `//` comments too, and inline without a refresh time runs as compact.
    let js = ScriptCommand.parse(
      "// @raycast.schemaVersion 1\n// @raycast.title JS\n// @raycast.mode inline\n// @raycast.packageName Dev",
      url: url)
    #expect(js?.mode == .compact)
    #expect(js?.packageName == "Dev")
  }

  @Test func takesOnlyEmojiForIcons() {
    let base = ["# @raycast.schemaVersion 1", "# @raycast.title T", "# @raycast.mode silent"]
    #expect(script(base[0], base[1], base[2], "# @raycast.icon 1password.png")?.icon == nil)
    #expect(script(base[0], base[1], base[2], "# @raycast.icon images/x.png")?.icon == nil)
    #expect(script(base[0], base[1], base[2], "# @raycast.icon 🛩")?.icon == "🛩")
  }

  @Test func leavesOutWhatItDoesntRunYet() {
    let base = ["# @raycast.schemaVersion 1", "# @raycast.title T"]
    #expect(script(base[0], base[1]) == nil)  // no mode
    #expect(script(base[0], base[1], "# @raycast.mode fullOutput")?.mode == .fullOutput)
    #expect(
      script(base[0], base[1], "# @raycast.mode inline", "# @raycast.refreshTime 1m") == nil)
    #expect(
      script(base[0], base[1], "# @raycast.mode silent", "# @raycast.needsConfirmation true")
        == nil)
    #expect(
      script(
        base[0], base[1], "# @raycast.mode silent",
        #"# @raycast.argument1 { "type": "text", "placeholder": "q" }"#) == nil)
    #expect(script("# @raycast.schemaVersion 2", base[1], "# @raycast.mode silent") == nil)
  }

  @Test func scansExecutableScriptsInTheFolderOnly() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(
      at: folder.appending(path: "sub"), withIntermediateDirectories: true)
    let body =
      "#!/bin/sh\n# @raycast.schemaVersion 1\n# @raycast.title %@\n# @raycast.mode silent\n"
    func write(_ name: String, executable: Bool) throws {
      let file = folder.appending(path: name)
      try String(format: body, name).write(to: file, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes(
        [.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
    }
    try write("b.sh", executable: true)
    try write("a.sh", executable: true)
    try write("plain.sh", executable: false)
    try write("x.template.sh", executable: true)
    try write("sub/deep.sh", executable: true)
    // A symlink to a script counts, as one linked in from a checkout.
    try FileManager.default.createSymbolicLink(
      at: folder.appending(path: "c.sh"), withDestinationURL: folder.appending(path: "a.sh"))
    #expect(ScriptCommand.scan([folder]).map(\.title) == ["a.sh", "b.sh", "a.sh"])
  }

  @Test func listsScriptsInTheRootSearch() throws {
    let hello = try #require(
      script("# @raycast.schemaVersion 1", "# @raycast.title Say Hello", "# @raycast.mode silent"))
    let row = try #require(
      Search.results(for: "say hello", apps: [], quicklinks: [], scripts: [hello]).first)
    #expect(row.kind == .script)
    #expect(row.action == .runScript("/tmp/Tools/hello.sh"))
    #expect(row.subtitle == "Tools")
    #expect(row.itemKey == hello.settingsKey)
  }

  @Test func dropsColorCodes() {
    #expect(ScriptCommand.plain("\u{1B}[31;42mred\u{1B}[0m plain") == "red plain")
    #expect(ScriptCommand.plain("\u{1B}]8;;https://a.b\u{1B}\\link\u{1B}]8;;\u{07}") == "link")
  }

  @Test func findsTheLastLineWithText() {
    #expect(ScriptCommand.lastLine(of: "one\ntwo\n\n") == "two")
    #expect(ScriptCommand.lastLine(of: "  \n") == nil)
  }
}
