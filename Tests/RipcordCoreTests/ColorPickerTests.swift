import Foundation
import Testing

@testable import RipcordCore

@Suite struct ColorPickerTests {
  let orange = PickedColor(red: 1, green: 0.5, blue: 0)

  @Test func copiesInEachFormat() {
    #expect(ColorFormat.hex.string(for: orange) == "#FF8000")
    #expect(ColorFormat.rgb.string(for: orange) == "rgb(255, 127.5, 0)")
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
    #expect(row.title == "rgb(255, 127.5, 0)")
    #expect(row.action == .copy("rgb(255, 127.5, 0)"))
    // The default format first, then every other, then Delete Color.
    #expect(
      row.actions.map(\.title)
        == ["Copy RGB"]
        + ColorFormat.allCases.filter { $0 != .rgb }.map { "Copy \($0.title)" } + ["Delete Color"])
    #expect(row.actions.last?.action == .deleteColor("#FF8000"))
    // Any format matches the search.
    #expect(!Search.colorSections(for: "ff80", history: history, format: .rgb).isEmpty)
    #expect(!Search.colorSections(for: "255, 127", history: history, format: .hex).isEmpty)
    // The code formats' labels don't match every color.
    #expect(Search.colorSections(for: "red", history: history, format: .rgb).isEmpty)
    #expect(Search.colorSections(for: "zzz", history: history, format: .rgb).isEmpty)
  }

  /// Raycast's formats as colorjs.io 0.7.1, which it calls, writes them: five significant
  /// digits, #RGB when it can, and "none" for a grey's hue.
  @Test func writesRaycastsFormats() {
    let coral = PickedColor(red: 1, green: 99.0 / 255, blue: 99.0 / 255)
    let red = PickedColor(red: 1, green: 0, blue: 0)
    let white = PickedColor(red: 1, green: 1, blue: 1)
    let expected: [(ColorFormat, PickedColor, String)] = [
      (.hex, coral, "#FF6363"), (.hex, red, "#F00"), (.hexLowerCase, coral, "#ff6363"),
      (.hexNoPrefix, coral, "ff6363"), (.rgb, coral, "rgb(255, 99, 99)"),
      (.rgbPercentage, coral, "rgb(100% 38.824% 38.824%)"), (.rgba, coral, "rgba(255, 99, 99)"),
      (.rgbaPercentage, coral, "rgba(100%, 38.824%, 38.824%, 1)"),
      (.hsla, coral, "hsla(0, 100%, 69.412%, 1)"), (.hsla, white, "hsla(none, 0%, 100%, 1)"),
      (.hsva, coral, "color(hsv 0 61.176 100)"),
      // CSS's red is oklch(62.8% 0.2577 29.23) and display-p3 0.9175 0.2003 0.1386.
      (.oklch, red, "oklch(62.796% 0.25768 29.234)"), (.oklch, white, "oklch(100% 0 none)"),
      (.p3, red, "color(display-p3 0.91749 0.20029 0.13856)"), (.lch, white, "lch(100.00% 0 none)"),
    ]
    for (format, color, text) in expected {
      #expect(format.string(for: color) == text, "\(format.title) \(color.hex)")
    }
    // CSS's example is lch(54.29 106.84 40.85); Raycast writes chroma and hue unrounded.
    #expect(ColorFormat.lch.string(for: red).hasPrefix("lch(54.29% 106.83"))
    let lch = red.lch
    #expect(abs(lch.chroma - 106.84) < 0.01 && abs((lch.hue ?? 0) - 40.85) < 0.01)
  }

  @Test func namesTheNearestColor() {
    #expect(ColorNames.css.count == 148)
    #expect(ColorNames.nearest(to: PickedColor(rgb: 0xFF6347), count: 1).first?.name == "tomato")
    #expect(ColorNames.nearest(to: PickedColor(rgb: 0xFE6448), count: 1).first?.name == "tomato")
    let sections = Search.colorNameSections(for: "#00ff00")
    #expect(sections.first?.results.first?.title == "lime")
    #expect(sections.first?.results.first?.actions.map(\.shortcut).prefix(2) == ["↵", "⌘↵"])
    #expect(
      Search.colorNameSections(for: "rebecca").first?.results.map(\.title) == ["rebeccapurple"])
    #expect(PickedColor(hex: "0f0")?.hex == "#00FF00")
    #expect(PickedColor(hex: "#12345") == nil)
  }
}
