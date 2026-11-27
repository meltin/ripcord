import AppKit
import Foundation
import Testing

@testable import RipcordCore

struct ClipboardSettingsTests {
  func temporaryHistory() -> (ClipboardHistory, URL) {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "ripcord-clip-settings-\(UUID().uuidString)")
    return (ClipboardHistory(directory: directory), directory)
  }

  @Test func tellsLinksEmailsAndColorsInText() {
    #expect(ClipType.links.matches(.text(" https://example.com/a?b=1\n")))
    #expect(!ClipType.links.matches(.text("see https://example.com")))
    #expect(ClipType.emails.matches(.text("me@example.com")))
    #expect(!ClipType.emails.matches(.text("me at example.com")))
    #expect(ClipType.colors.matches(.text("#FF8000")))
    #expect(ClipType.colors.matches(.text("rgb(255, 128, 0)")))
    #expect(!ClipType.colors.matches(.text("FF8000 is orange")))
    #expect(ClipType.text.matches(.text("anything")))
    #expect(!ClipType.text.matches(.files(["/tmp/a"])))
  }

  @Test func listsOnlyTheChosenType() throws {
    var (history, directory) = temporaryHistory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try history.add(.text("hello"))
    try history.add(.text("https://example.com"))
    try history.add(.files([URL(fileURLWithPath: "/tmp/a.txt")]))
    let titles = { (type: ClipType?) in
      Search.clipboardSections(for: "", history: history, type: type).flatMap(\.results).map(
        \.title)
    }
    #expect(titles(nil).count == 3)
    #expect(titles(.links) == ["https://example.com"])
    #expect(titles(.files) == ["a.txt"])
  }

  @Test func dropsWhatsOlderThanItKeeps() throws {
    var (history, directory) = temporaryHistory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    try history.add(.text("old"), at: now.addingTimeInterval(-10 * 86_400))
    try history.add(.text("pinned old"), at: now.addingTimeInterval(-10 * 86_400))
    try history.togglePin(history.items[0].id)
    try history.add(.text("new"), at: now)
    history.settings.keepFor = .week
    try history.prune(at: now)
    #expect(history.items.map(\.content) == [.text("new"), .text("pinned old")])
  }

  @Test func keepsAsManyAsItsSetTo() throws {
    var (history, directory) = temporaryHistory()
    defer { try? FileManager.default.removeItem(at: directory) }
    history.settings.maxEntries = 2
    for text in ["a", "b", "c"] { try history.add(.text(text)) }
    #expect(history.items.map(\.content) == [.text("c"), .text("b")])
  }

  @Test func deletesAllButPinned() throws {
    var (history, directory) = temporaryHistory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try history.add(.text("a"))
    try history.togglePin(history.items[0].id)
    try history.add(.text("b"))
    try history.deleteAll()
    #expect(history.items.map(\.content) == [.text("a")])
  }

  @Test func readsMissingSettingsAsUnlimited() throws {
    let config = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"cmd+space"}"#.utf8))
    #expect(config.clipboardHistory == ClipboardSettings(keepFor: .unlimited, maxEntries: 300))
    // Raycast's defaults for the settings added since.
    #expect(
      config.clipboardHistory.disabledApps == ["com.apple.Passwords", "com.apple.keychainaccess"])
    #expect(config.clipboardHistory.primaryAction == .paste)
    #expect(config.clipboardHistory.updateAfterAction)
  }

  @Test func unlimitedKeepsEveryEntry() throws {
    var (history, directory) = temporaryHistory()
    defer { try? FileManager.default.removeItem(at: directory) }
    history.settings.maxEntries = ClipboardSettings.unlimitedEntries
    for text in ["a", "b", "c"] { try history.add(.text(text)) }
    try history.prune()
    #expect(history.items.count == 3)
    // Saved and read back, as a build from before Unlimited reads it too.
    let saved = try JSONEncoder().encode(history.settings)
    let read = try JSONDecoder().decode(ClipboardSettings.self, from: saved)
    #expect(read.maxEntries == .max)
  }

  /// An image is found by the text read from it, once read; until then it's waiting to be.
  @Test func findsAnImageByItsRecognizedText() throws {
    var (history, directory) = temporaryHistory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)?.representation(using: .png, properties: [:]))
    try history.add(.image(png, fileExtension: "png", width: 2, height: 2))
    let id = history.items[0].id
    let found = { (query: String) in
      Search.clipboardSections(for: query, history: history).flatMap(\.results).count
    }
    #expect(history.unreadImages.map(\.id) == [id])
    #expect(found("invoice") == 0)
    try history.setRecognizedText("Invoice 2026-11", for: id)
    #expect(history.unreadImages.isEmpty)
    #expect(found("invoice") == 1)
    // Read back from disk too.
    #expect(ClipboardHistory(directory: directory).items[0].recognizedText == "Invoice 2026-11")
  }

  /// A text's formatting is kept in its own file, and goes with the entry.
  @Test func keepsATextsFormatting() throws {
    var (history, directory) = temporaryHistory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let rtf = Data(#"{\rtf1 {\b bold} text}"#.utf8)
    try history.add(.text("bold text"), formatting: (rtf, "rtf"))
    try history.add(.text("plain"))
    let formatted = history.items[1]
    let url = try #require(history.formatURL(of: formatted))
    #expect(try Data(contentsOf: url) == rtf)
    #expect(history.formatURL(of: history.items[0]) == nil)
    #expect(ClipboardSettings().preferPlainText)
    try history.delete(formatted.id)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  /// Copied again, a text takes that copy's formatting, or none.
  @Test func theLatestCopysFormattingWins() throws {
    var (history, directory) = temporaryHistory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let rtf = Data(#"{\rtf1 {\b same}}"#.utf8)
    try history.add(.text("same"))
    #expect(history.formatURL(of: history.items[0]) == nil)
    try history.add(.text("same"), formatting: (rtf, "rtf"))
    #expect(history.items.count == 1)
    let url = try #require(history.formatURL(of: history.items[0]))
    #expect(try Data(contentsOf: url) == rtf)
    try history.add(.text("same"))
    #expect(history.formatURL(of: history.items[0]) == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  /// Copy to Clipboard as the Primary Action puts copy on Return and paste on ⌘↵.
  @Test func primaryActionSwapsPasteAndCopy() throws {
    var (history, directory) = temporaryHistory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try history.add(.text("hello"))
    let id = history.items[0].id
    func firstTwo() -> [(String, String, SearchResult.Action)] {
      let row = Search.clipboardSections(for: "", history: history).flatMap(\.results)[0]
      return row.actions.prefix(2).map { ($0.title, $0.shortcut, $0.action) }
    }
    #expect(firstTwo().map(\.2) == [.clip(id, .paste), .clip(id, .copy)])
    history.settings.primaryAction = .copy
    let swapped = firstTwo()
    #expect(swapped.map(\.0) == ["Copy to Clipboard", "Paste to App"])
    #expect(swapped.map(\.1) == ["↵", "⌘↵"])
    #expect(swapped.map(\.2) == [.clip(id, .copy), .clip(id, .paste)])
  }
}
