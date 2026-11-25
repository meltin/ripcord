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

  @Test(arguments: ["space", "cmd+", "cmd+f1", "hyper+space", ""])
  func rejects(spec: String) {
    #expect(Hotkey(spec) == nil)
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
    #expect(app.actions.map(\.shortcut) == ["↵", "⇧⌘F", "⇧⌘C"])
    #expect(app.actions[2].action == .copy("/Applications/Safari.app"))
    let link = try #require(Search.results(for: "google", apps: [], quicklinks: links).first)
    #expect(link.actions.map(\.title) == ["Open Command", "Copy URL"])
  }

  @Test func typedQueryShowsOneResultsSection() {
    let sections = Search.sections(for: "quit", apps: apps, running: [], quicklinks: links)
    #expect(sections.map(\.title) == ["Results"])
    #expect(sections[0].results.first?.action == .run(.quit))
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

  @Test func calculatorComesFirst() {
    let results = Search.results(for: "2+2", apps: apps, quicklinks: links)
    #expect(results.first?.action == .copy("4"))
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
}

@Suite struct AppIndexTests {
  @Test func findsSystemApps() {
    let names = AppIndex.scan().flatMap(\.names)
    #expect(names.contains("Finder"))
    #expect(names.contains("System Settings"))
  }
}
