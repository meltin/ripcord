import Foundation
import Testing

@testable import RipcordCore

@Suite struct EmojiTests {
  /// The data the app bundles.
  let catalog: EmojiCatalog = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "../../Resources/Emoji/emoji.json").standardized
    // The file ships with the repo; a test can't run without it.
    return try! EmojiCatalog(data: Data(contentsOf: url))
  }()

  func history() -> EmojiHistory {
    EmojiHistory(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json"))
  }

  func characters(_ query: String, category: Int? = nil) -> [String] {
    Search.emojiSections(for: query, catalog: catalog, history: history(), category: category)
      .flatMap(\.results).compactMap(\.subtitle)
  }

  @Test func findsByEnglishAndJapaneseKanaEitherWay() {
    #expect(characters("cat").prefix(3).contains("🐱"))
    #expect(characters("ねこ").contains("🐱"))
    #expect(characters("ネコ").contains("🐱"))
    #expect(characters("猫").contains("🐱"))
    #expect(characters("ＣＡＴ").contains("🐱"))
    #expect(characters("zzzzqq").isEmpty)
  }

  @Test func includesSymbolsAndMacKeys() {
    #expect(characters("right-pointing arrow").first == "→")
    #expect(characters("command key").first == "⌘")
    #expect(characters("degree").contains("°"))
  }

  @Test func listsCategoriesAndFrequentlyUsedFirst() throws {
    var used = history()
    try used.use("🐱")
    let sections = Search.emojiSections(for: "", catalog: catalog, history: used)
    #expect(sections.map(\.title).first == "Frequently Used")
    #expect(sections.first?.results.first?.subtitle == "🐱")
    #expect(Array(sections.map(\.title).dropFirst()) == catalog.groups)
    // A category shows only itself, without Frequently Used.
    let flags = try #require(catalog.groups.firstIndex(of: "Flags"))
    let only = Search.emojiSections(for: "", catalog: catalog, history: used, category: flags)
    #expect(only.map(\.title) == ["Flags"])
  }

  @Test func remembersRecentAndSkinTone() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    var saved = EmojiHistory(fileURL: file)
    for emoji in ["😀", "🐱", "😀"] { try saved.use(emoji) }
    try saved.setSkinTone(3)
    let read = EmojiHistory(fileURL: file)
    #expect(read.recent == ["😀", "🐱"])
    #expect(read.skinTone == 3)
    let thumbs = Search.emojiSections(for: "thumbs up", catalog: catalog, history: read)
      .flatMap(\.results).first
    #expect(thumbs?.subtitle == "👍🏽")
    #expect(thumbs?.action == .emoji("👍🏽", base: "👍", .paste))
  }

  @Test func offersRaycastsActions() throws {
    let cat = try #require(
      Search.emojiSections(for: "cat face", catalog: catalog, history: history())
        .first?.results.first)
    #expect(cat.title == "Cat Face")
    #expect(
      cat.actions.map(\.title) == [
        "Paste", "Copy to Clipboard", "Paste and Keep Window Open", "Copy Unicode",
        "Copy All Emojis from Section",
      ])
    #expect(cat.actions[3].action == .copy("U+1F431"))
    // In the skin tone picked.
    var toned = history()
    try toned.setSkinTone(3)
    let thumbs = try #require(
      Search.emojiSections(for: "thumbs up", catalog: catalog, history: toned).first?.results
        .first)
    #expect(thumbs.actions[3].action == .copy("U+1F44D U+1F3FD"))
  }

  @Test func searchesQuickly() {
    let clock = ContinuousClock()
    let took = clock.measure {
      for query in ["c", "ca", "cat", "ね", "ねこ"] { _ = characters(query) }
    }
    // Loose, for a busy machine and a debug build: folding on every key press took seconds.
    #expect(took < .seconds(2))
  }

  /// Raycast's Emoji & Symbols settings: eight columns, kept within 6 to 10, and Return
  /// copying with Copy to Clipboard as the Primary Action.
  @Test func takesRaycastsSettings() throws {
    let config = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"cmd+space"}"#.utf8))
    #expect(config.emoji == EmojiSettings())
    #expect(config.emoji.columns == 8)
    let wide = try JSONDecoder().decode(EmojiSettings.self, from: Data(#"{"columns":42}"#.utf8))
    #expect(wide.columns == 10)
    let copying = Search.emojiSections(
      for: "cat", catalog: catalog, history: history(), primaryAction: .copy)
    let first = try #require(copying.first?.results.first)
    #expect(first.actions.prefix(2).map(\.title) == ["Copy to Clipboard", "Paste"])
    #expect(first.actions.prefix(2).map(\.shortcut) == ["↵", "⌘↵"])
  }
}
