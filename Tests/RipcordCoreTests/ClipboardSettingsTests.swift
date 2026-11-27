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
  }
}
