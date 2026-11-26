import Foundation
import Testing

@testable import RipcordCore

@Suite struct CleanShotTests {
  let cleanShot = AppEntry(
    url: URL(fileURLWithPath: "/Applications/CleanShot X.app"), names: ["CleanShot X"],
    bundleID: CleanShotCommand.bundleID)

  @Test func opensItsURLScheme() {
    #expect(CleanShotCommand.captureArea.url?.absoluteString == "cleanshot://capture-area")
    #expect(CleanShotCommand.allCases.allSatisfy { $0.url?.scheme == "cleanshot" })
    #expect(
      Set(CleanShotCommand.allCases.map(\.settingsKey)).count == CleanShotCommand.allCases.count)
  }

  @Test func listsItsCommandsOnlyWithCleanShotInstalled() {
    #expect(
      Search.results(for: "capture area", apps: [cleanShot], quicklinks: []).first?.action
        == .cleanShot(.captureArea))
    #expect(
      !Search.results(for: "capture area", apps: [], quicklinks: []).contains {
        $0.action == .cleanShot(.captureArea)
      })
  }

  @Test func takesAnAliasAndConfigureCommand() throws {
    let key = CleanShotCommand.captureText.settingsKey
    let items = [key: ItemSettings(alias: "ocr")]
    let row = try #require(
      Search.results(for: "ocr", apps: [cleanShot], quicklinks: [], items: items).first)
    #expect(row.action == .cleanShot(.captureText))
    #expect(row.subtitle == "CleanShot X")
    #expect(row.itemKey == key)
    #expect(row.actions.last?.action == .configureMenu(key))
    // Switched off, it's gone.
    let off = [key: ItemSettings(disabled: true)]
    #expect(
      !Search.results(for: "capture text", apps: [cleanShot], quicklinks: [], items: off).contains {
        $0.action == .cleanShot(.captureText)
      })
  }

  @Test func showsOnTheSettingsCatalog() {
    let section = Search.catalog(apps: [], quicklinks: []).first { $0.title == "CleanShot X" }
    #expect(section?.entries.count == CleanShotCommand.allCases.count)
  }
}
