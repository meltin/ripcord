import Foundation
import Testing

@testable import RipcordCore

struct SnippetExpansionTests {
  func run(
    _ text: String, keywords: [String] = [";addr"], mode: SnippetExpansion.Mode = .immediately,
    withinWords: Bool = false
  ) -> [KeywordMatcher.Match] {
    var matcher = KeywordMatcher()
    return text.compactMap {
      matcher.type($0, keywords: keywords, mode: mode, withinWords: withinWords)
    }
  }

  @Test func expandsAsTheLastCharacterIsTyped() {
    #expect(run("hi ;addr") == [.init(keyword: ";addr", deleting: 5, trailing: "")])
  }

  @Test func waitsForADelimiterAndKeepsOrDropsIt() {
    #expect(run(";addr", mode: .afterDelimiterKeeping).isEmpty)
    #expect(
      run(";addr ", mode: .afterDelimiterKeeping)
        == [.init(keyword: ";addr", deleting: 6, trailing: " ")])
    #expect(
      run(";addr.", mode: .afterDelimiterDiscarding)
        == [.init(keyword: ";addr", deleting: 6, trailing: "")])
  }

  @Test func expandsOnlyAsAWordOfItsOwnUnlessAskedTo() {
    #expect(run("xaddr", keywords: ["addr"]).isEmpty)
    #expect(run("xaddr", keywords: ["addr"], withinWords: true).count == 1)
    #expect(run("(addr", keywords: ["addr"]).count == 1)
  }

  @Test func prefersTheLongerKeywordEndingTheText() {
    #expect(run(";;log", keywords: [";log", ";;log"]).first?.keyword == ";;log")
  }

  @Test func ignoresEmptyKeywordsAndOnesWithSpaces() {
    #expect(run("a b", keywords: ["", "a b"]).isEmpty)
  }

  @Test func forgetsWhatWasTypedAtReturnAndBackspace() {
    #expect(run(";ad\ndr").isEmpty)
    var matcher = KeywordMatcher()
    for character in ";adx" {
      _ = matcher.type(character, keywords: [";addr"], mode: .immediately, withinWords: false)
    }
    matcher.deleteBackward()
    #expect(
      "dr".compactMap {
        matcher.type($0, keywords: [";addr"], mode: .immediately, withinWords: false)
      }.count == 1)
  }

  @Test func readsMissingSettingsAsDefaults() throws {
    let config = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"cmd+space"}"#.utf8))
    #expect(config.snippetExpansion == SnippetExpansion())
    #expect(config.snippetExpansion.disabledApps.contains("com.1password.1password"))
  }

  @Test func keepsAnEmptiedDisabledList() throws {
    let data = Data(#"{"hotkey":"cmd+space","snippetExpansion":{"disabledApps":[]}}"#.utf8)
    #expect(try JSONDecoder().decode(Config.self, from: data).snippetExpansion.disabledApps == [])
  }
}
