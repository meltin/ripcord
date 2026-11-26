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

  @Test func listsItsCommandsUnderSleepTimer() {
    let row = Search.results(for: "stop sleep timer", apps: [], quicklinks: []).first
    #expect(row?.action == .run(.stopSleepTimer))
    #expect(row?.subtitle == "Sleep Timer")
  }
}
