import Carbon.HIToolbox
import Foundation
import Testing

@testable import RipcordCore

@Suite struct FuzzyTests {
  @Test func rejectsNonSubsequence() {
    #expect(Fuzzy.score("xyz", in: "Safari") == nil)
  }

  @Test func isCaseInsensitive() {
    #expect(Fuzzy.score("SAF", in: "safari") != nil)
  }

  @Test func prefersWordStarts() throws {
    let wordStart = try #require(Fuzzy.score("code", in: "Visual Studio Code"))
    let midWord = try #require(Fuzzy.score("code", in: "Xcode"))
    #expect(wordStart > midWord)
  }
}

@Suite struct CalculatorTests {
  @Test(arguments: [
    ("1+2*3", 7.0), ("(1+2)*3", 9), ("2^3^2", 512), ("-2^2", -4), ("10%3", 1),
    ("2*-3", -6), ("１＋１", 2), ("6÷4", 1.5),
  ])
  func evaluates(input: String, expected: Double) {
    #expect(Calculator.evaluate(input) == expected)
  }

  @Test(arguments: ["1+", "2**", "abc", "42", "-5", "(3)", "1/0", "1..2+1", "Safari"])
  func rejects(input: String) {
    #expect(Calculator.evaluate(input) == nil)
  }

  @Test func formatsWithoutFloatNoise() throws {
    #expect(Calculator.format(try #require(Calculator.evaluate("0.1+0.2"))) == "0.3")
    #expect(Calculator.format(1_000_000) == "1000000")
  }
}

@Suite struct QuicklinkTests {
  let link = Quicklink(name: "Search", url: "https://example.com/?q={query}", keyword: "s")

  @Test func encodesReservedCharacters() {
    #expect(
      link.url(for: "a b&c#d+e")?.absoluteString == "https://example.com/?q=a%20b%26c%23d%2Be")
  }

  @Test func encodesJapanese() {
    #expect(link.url(for: "日本")?.absoluteString == "https://example.com/?q=%E6%97%A5%E6%9C%AC")
  }
}

@Suite struct HotkeyTests {
  @Test func parsesModifiersAndKey() throws {
    let hotkey = try #require(Hotkey("cmd + Shift + K"))
    #expect(hotkey.keyCode == UInt32(kVK_ANSI_K))
    #expect(hotkey.modifiers == UInt32(cmdKey | shiftKey))
    #expect(Hotkey("option+space")?.keyCode == UInt32(kVK_Space))
  }

  // Shift alone would steal a capital letter from every app.
  @Test(arguments: ["space", "cmd+", "cmd+f1", "hyper+space", "", "shift+k", "shift+space"])
  func rejects(spec: String) {
    #expect(Hotkey(spec) == nil)
  }

  @Test func recordsAKeyPressAsASpec() throws {
    let hotkey = try #require(
      Hotkey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey | alphaLock)))
    #expect(hotkey.spec == "shift+cmd+k")
    #expect(Hotkey(hotkey.spec) == hotkey)
    #expect(hotkey.keycaps == ["⇧", "⌘", "K"])
    #expect(Hotkey("cmd+space")?.keycaps == ["⌘", "Space"])
  }

  @Test func rejectsKeyPressesASpecCantName() {
    #expect(Hotkey(keyCode: UInt32(kVK_ANSI_K), modifiers: 0) == nil)
    #expect(Hotkey(keyCode: UInt32(kVK_F1), modifiers: UInt32(cmdKey)) == nil)
  }
}

@Suite struct SearchTests {
  let apps = [
    AppEntry(url: URL(fileURLWithPath: "/Applications/Safari.app"), names: ["Safari"]),
    AppEntry(
      url: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
      names: ["システム設定", "System Settings"]),
  ]
  let links = [Quicklink(name: "Google", url: "https://google.com/?q={query}", keyword: "g")]

  @Test func emptyQueryShowsStartSections() {
    let sections = Search.sections(for: "", apps: apps, running: [apps[0]], quicklinks: links)
    #expect(sections.map(\.title) == ["Running", "Quicklinks"])
    #expect(sections[0].results.map(\.title) == ["Safari"])
    #expect(Search.sections(for: " ", apps: apps, running: [], quicklinks: []).isEmpty)
  }

  @Test func actionsPutPrimaryFirst() throws {
    let app = try #require(Search.results(for: "safari", apps: apps, quicklinks: []).first)
    // Raycast's actions, keys and order. Copy Bundle Identifier is there only when the app's
    // bundle can be read, as on a Mac with Safari.
    let hasBundle = Bundle(url: URL(fileURLWithPath: "/Applications/Safari.app")) != nil
    #expect(
      app.actions.map(\.title) == [
        "Open Application", "Show in Finder", "Show Info in Finder", "Show Package Contents",
        "Add to Favorites", "Copy Path", "Copy Name",
      ] + (hasBundle ? ["Copy Bundle Identifier"] : []) + ["Configure Command…", "Disable Command"])
    #expect(
      app.actions.map(\.shortcut)
        == ["↵", "⌘↵", "⌘I", "⌥⌘I", "⇧⌘F", "⌥⌘C", "⌃⌘C"] + (hasBundle ? ["⇧⌘C"] : []) + [
          "⇧⌘,", "⌃⇧⌘D",
        ])
    #expect(
      app.actions[3].action
        == .open(URL(fileURLWithPath: "/Applications/Safari.app").appending(path: "Contents")))
    #expect(app.actions[5].action == .copy("/Applications/Safari.app"))
    #expect(app.actions[6].action == .copy("Safari"))
    // An app is configured by its settings key, as the Applications page lists it.
    #expect(app.actions.dropLast().last?.action == .configureMenu(apps[0].settingsKey))
    let link = try #require(Search.results(for: "google", apps: [], quicklinks: links).first)
    #expect(
      link.actions.map(\.title) == [
        "Open Command", "Copy URL", "Add to Favorites", "Disable Command",
      ])
    // A Quicklink's is found by its row's key, as its switch is on the Quicklink itself.
    #expect(link.actions.last?.action == .disableCommand(link.id))
  }

  @Test func typedQueryShowsOneResultsSection() {
    let sections = Search.sections(for: "quit", apps: apps, running: [], quicklinks: links)
    #expect(sections.map(\.title) == ["Results"])
    #expect(sections[0].results.first?.action == .run(.quit))
    let reset = Search.results(for: "reset window", apps: apps, quicklinks: links)
    #expect(reset.first?.action == .run(.resetWindowPosition))
  }

  @Test func noMatchFallsBackToQuicklinks() {
    let sections = Search.sections(for: "zz zz", apps: apps, running: [], quicklinks: links)
    #expect(sections.map(\.title) == ["Use “zz zz” with…"])
    #expect(
      sections[0].results.first?.action == .open(URL(string: "https://google.com/?q=zz%20zz")!))
    #expect(Search.sections(for: "zzzz", apps: apps, running: [], quicklinks: []).isEmpty)
  }

  @Test func emptyQueryShowsNothing() {
    #expect(Search.results(for: "  ", apps: apps, quicklinks: links).isEmpty)
  }

  @Test func matchesLocalizedAndFileNames() {
    #expect(Search.results(for: "システム", apps: apps, quicklinks: []).first?.title == "システム設定")
    #expect(Search.results(for: "settings", apps: apps, quicklinks: []).first?.title == "システム設定")
  }

  @Test func calculatorComesFirst() throws {
    let results = Search.results(for: "2+2", apps: apps, quicklinks: links)
    #expect(results.first?.action == .copy("4"))
    // Raycast's ⌘K, without its calculation history.
    let answer = try #require(results.first)
    #expect(
      answer.actions.map(\.title) == [
        "Copy Answer", "Paste Answer", "Copy Question and Answer", "Put Answer in Search Bar",
      ])
    #expect(answer.actions.map(\.shortcut) == ["↵", "⌘↵", "⌥⇧⌘C", "⇧⌘↵"])
    #expect(
      answer.actions.map(\.action) == [
        .copy("4"), .pasteText("4"), .copy("2+2 = 4"), .setQuery("4"),
      ])
  }

  /// Put Answer in Search Bar: the answer as written reads back, so the sum can go on.
  @Test func answersReadBack() throws {
    for value in [1234.5, -7, 0.1, 1e20, 2.0 / 3] {
      let next = try #require(Calculator.evaluate(Calculator.format(value) + "+1"))
      #expect(abs(next - (value + 1)) <= abs(value) * 1e-9 + 1e-9)
    }
  }

  @Test func keywordExpandsQuicklink() {
    let results = Search.results(for: "g swift testing", apps: apps, quicklinks: links)
    #expect(
      results.first?.action == .open(URL(string: "https://google.com/?q=swift%20testing")!))
  }
}

@Suite struct ConfigTests {
  @Test func writesDefaultsWhenMissingThenReadsThem() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString).appending(path: "config.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(try Config.load(from: url) == .default)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(try Config.load(from: url) == .default)
  }

  @Test func reportsInvalidJSON() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("{".utf8).write(to: url)
    #expect(throws: (any Error).self) { try Config.load(from: url) }
  }

  @Test func readsFilesWrittenBeforeLaunchAtLoginExisted() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"hotkey": "ctrl+space", "quicklinks": []}"#.utf8).write(to: url)
    let config = try Config.load(from: url)
    #expect(config.hotkey == "ctrl+space")
    #expect(config.launchAtLogin == false)
  }

  @Test func savesTheInputSourceOnlyWhenOneIsChosen() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString).appending(path: "config.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Config.default.save(to: url)
    // Off writes no key, so a config saved before this setting existed stays byte-identical.
    #expect(try !String(contentsOf: url, encoding: .utf8).contains("inputSource"))
    #expect(try Config.load(from: url).inputSource == nil)
    var config = Config.default
    config.inputSource = "com.apple.keylayout.ABC"
    try config.save(to: url)
    #expect(try Config.load(from: url).inputSource == "com.apple.keylayout.ABC")
  }

  @Test func savesEditsAndReadsThemBack() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString).appending(path: "config.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var config = Config.default
    config.launchAtLogin = true
    config.quicklinks.append(
      Quicklink(name: "MDN", url: "https://developer.mozilla.org/search?q={query}"))
    try config.save(to: url)
    #expect(try Config.load(from: url) == config)
  }
}

@Suite struct AppIndexTests {
  @Test func findsSystemApps() {
    let names = AppIndex.scan().flatMap(\.names)
    #expect(names.contains("Finder"))
    #expect(names.contains("System Settings"))
  }
}
