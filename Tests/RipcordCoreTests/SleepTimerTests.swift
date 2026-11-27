import Foundation
import Testing

@testable import RipcordCore

@Suite struct SleepTimerTests {
  @Test func offersSleepAndDisplayOffForATypedTime() {
    let rows = Search.results(for: "sleep timer 30m", apps: [], quicklinks: []).prefix(2)
    #expect(rows.map(\.title) == ["Sleep in 30m", "Turn Off Display in 30m"])
    #expect(
      rows.map(\.action) == [
        .sleepTimer(1800, displayOnly: false), .sleepTimer(1800, displayOnly: true),
      ])
  }

  @Test func takesItsAliasAndRefusesWhatIsNotATime() {
    let items = [BuiltinCommand.sleepTimer.settingsKey: ItemSettings(alias: "zz")]
    #expect(
      Search.results(for: "zz 1h", apps: [], quicklinks: [], items: items).first?.action
        == .sleepTimer(3600, displayOnly: false))
    #expect(
      !Search.results(for: "sleep timer soon", apps: [], quicklinks: []).contains {
        $0.id == "sleep-in"
      })
    let off = [BuiltinCommand.sleepTimer.settingsKey: ItemSettings(disabled: true)]
    #expect(
      !Search.results(for: "sleep timer 30m", apps: [], quicklinks: [], items: off).contains {
        $0.id == "sleep-in"
      })
  }

  @Test func aQuicklinkKeywordStillComesFirst() {
    let items = [BuiltinCommand.caffeinate.settingsKey: ItemSettings(alias: "g")]
    let links = [Quicklink(name: "Google", url: "https://g.co/?q={query}", keyword: "g")]
    #expect(
      Search.results(for: "g 5", apps: [], quicklinks: links, items: items).first?.id
        == "quicklink-query:Google")
  }

  @Test func listsItsCommandsUnderSleepTimer() {
    let row = Search.results(for: "stop sleep timer", apps: [], quicklinks: []).first
    #expect(row?.action == .run(.stopSleepTimer))
    #expect(row?.subtitle == "Sleep Timer")
  }

  /// Raycast's Start 15, 30, 45, 60 and 90 Minute Sleep Timer, each its own command.
  @Test func hasRaycastsPresets() {
    let presets = BuiltinCommand.allCases.filter { $0.sleepTimerMinutes != nil }
    #expect(presets.compactMap(\.sleepTimerMinutes) == [15, 30, 45, 60, 90])
    #expect(presets.map(\.title).first == "Start 15 Minute Sleep Timer")
    #expect(Set(presets.map(\.settingsKey)).count == 5)
    #expect(BuiltinCommand.sleepTimer.sleepTimerMinutes == nil)
  }
}
