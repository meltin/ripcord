import Foundation
import Testing

@testable import RipcordCore

@Suite struct ColorPickerTests {
  let orange = PickedColor(red: 1, green: 0.5, blue: 0)

  @Test func copiesInEachFormat() {
    #expect(ColorFormat.hex.string(for: orange) == "#FF8000")
    #expect(ColorFormat.rgb.string(for: orange) == "rgb(255, 128, 0)")
    #expect(ColorFormat.hsl.string(for: orange) == "hsl(30, 100%, 50%)")
    #expect(ColorFormat.swiftUI.string(for: orange) == "Color(red: 1, green: 0.5, blue: 0)")
    #expect(
      ColorFormat.nsColor.string(for: orange)
        == "NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)")
  }

  @Test func readsGraysAndOtherHuesInHSL() {
    #expect(
      ColorFormat.hsl.string(for: PickedColor(red: 0.5, green: 0.5, blue: 0.5)) == "hsl(0, 0%, 50%)"
    )
    #expect(
      ColorFormat.hsl.string(for: PickedColor(red: 0, green: 0, blue: 1)) == "hsl(240, 100%, 50%)")
    #expect(
      ColorFormat.hsl.string(for: PickedColor(red: 1, green: 0, blue: 0.5)) == "hsl(330, 100%, 50%)"
    )
  }

  @Test func keepsTheNewestFirstOnceEach() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    var history = ColorHistory(fileURL: file)
    try history.add(orange)
    try history.add(PickedColor(red: 0, green: 0, blue: 0))
    try history.add(orange)
    #expect(history.colors.map(\.hex) == ["#FF8000", "#000000"])
    // Kept across launches.
    #expect(ColorHistory(fileURL: file).colors.map(\.hex) == ["#FF8000", "#000000"])
    try history.delete(hex: "#FF8000")
    #expect(ColorHistory(fileURL: file).colors.map(\.hex) == ["#000000"])
  }

  @Test func movesAnUnreadableHistoryAsideRatherThanOverwritingIt() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "colors.json")
    try Data("not json".utf8).write(to: file)
    var history = ColorHistory(fileURL: file)
    try history.add(orange)
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(names.contains { $0.hasPrefix("colors-unreadable-") })
  }

  @Test func readsAnUnknownFormatAsHex() throws {
    let data = Data(#"{"hotkey": "ctrl+space", "quicklinks": [], "colorFormat": "SwiftUI"}"#.utf8)
    #expect(try JSONDecoder().decode(Config.self, from: data).colorFormat == .hex)
  }

  @Test func listsInTheDefaultFormatAndCopiesTheRest() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    var history = ColorHistory(fileURL: file)
    try history.add(orange)
    let row = try #require(
      Search.colorSections(for: "", history: history, format: .rgb).first?.results.first)
    #expect(row.title == "rgb(255, 128, 0)")
    #expect(row.action == .copy("rgb(255, 128, 0)"))
    #expect(
      row.actions.map(\.title) == [
        "Copy RGB", "Copy HEX", "Copy HSL", "Copy SwiftUI", "Copy NSColor", "Delete Color",
      ])
    #expect(row.actions.last?.action == .deleteColor("#FF8000"))
    // Any format matches the search.
    #expect(!Search.colorSections(for: "ff80", history: history, format: .rgb).isEmpty)
    // The code formats' labels don't match every color.
    #expect(Search.colorSections(for: "red", history: history, format: .rgb).isEmpty)
    #expect(Search.colorSections(for: "zzz", history: history, format: .rgb).isEmpty)
  }
}
