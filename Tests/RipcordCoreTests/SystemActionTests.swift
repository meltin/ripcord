import Foundation
import Testing

@testable import RipcordCore

@Suite struct SystemActionTests {
  @Test func keysAreUniqueAndApartFromCommands() {
    let keys = SystemAction.allCases.map(\.settingsKey)
    #expect(Set(keys).count == keys.count)
    #expect(Set(keys).isDisjoint(with: BuiltinCommand.allCases.map(\.settingsKey)))
    // Spelled out, so renaming a case never strands its alias or hotkey.
    #expect(SystemAction.lockScreen.settingsKey == "system:lock-screen")
    #expect(SystemAction.restartFrontmostApp.settingsKey == "system:restart-frontmost-app")
  }

  @Test func foundByTypingAndHiddenWhenOff() {
    #expect(
      Search.results(for: "lock screen", apps: [], quicklinks: []).first?.action
        == .system(.lockScreen))
    let off = [SystemAction.lockScreen.settingsKey: ItemSettings(disabled: true)]
    #expect(
      !Search.results(for: "lock screen", apps: [], quicklinks: [], items: off).contains {
        $0.action == .system(.lockScreen)
      })
  }

  @Test func anAliasFindsIt() {
    let items = [SystemAction.lockScreen.settingsKey: ItemSettings(alias: "lk")]
    #expect(
      Search.results(for: "lk", apps: [], quicklinks: [], items: items).first?.action
        == .system(.lockScreen))
  }

  @Test func onlyWhatLosesWorkAsksFirst() {
    let asking = Set(SystemAction.allCases.filter { $0.warning != nil })
    #expect(
      asking == [.logOut, .restart, .shutDown, .emptyTrash, .quitAllApps, .quitOtherApps])
  }

  @Test func listedOnTheShortcutsPage() {
    let section = Search.catalog(apps: [], quicklinks: []).first { $0.title == "System Actions" }
    #expect(section?.entries.count == SystemAction.allCases.count)
  }

  /// Raycast's names, so the words typed there find the same commands; the settings keys stay.
  @Test func takesRaycastsNames() {
    #expect(SystemAction.volumeUp.title == "Turn Volume Up")
    #expect(SystemAction.volumeDown.title == "Turn Volume Down")
    #expect(SystemAction.unhideAllApps.title == "Unhide All Hidden Apps")
    #expect(SystemAction.volumeUp.rawValue == "volume-up")
    #expect(SystemAction.unhideAllApps.rawValue == "unhide-all-apps")
    // The old words still find them first.
    func top(_ query: String) -> String? {
      Search.sections(for: query, apps: [], running: [], quicklinks: [], items: [:])
        .flatMap(\.results).first?.title
    }
    #expect(top("volume up") == "Turn Volume Up")
    #expect(top("volume down") == "Turn Volume Down")
    #expect(top("unhide") == "Unhide All Hidden Apps")
  }
}
