import Foundation
import Testing

@testable import RipcordCore

@Suite struct CleanKeyboardTests {
  @Test func offersTheUsualTimesBeforeOneIsTyped() {
    // As the command leaves it in the field: its title and a space.
    let rows = Search.results(for: "Clean Keyboard ", apps: [], quicklinks: []).prefix(4)
    #expect(
      rows.map(\.title) == [
        "Clean Keyboard for 15s", "Clean Keyboard for 30s", "Clean Keyboard for 1m",
        "Clean Keyboard for 2m",
      ])
    #expect(rows.first?.action == .cleanKeyboard(15))
    // Through the root sections too, as the panel lists them.
    #expect(
      Search.sections(for: "Clean Keyboard ", apps: [], running: [], quicklinks: [])
        .flatMap(\.results).first?.action == .cleanKeyboard(15))
  }

  @Test func neverTurnsTheKeyboardOffFromTheTitleOrAliasAlone() {
    func offersClean(_ query: String, _ items: [String: ItemSettings] = [:]) -> Bool {
      Search.results(for: query, apps: [], quicklinks: [], items: items).contains {
        if case .cleanKeyboard = $0.action { true } else { false }
      }
    }
    #expect(!offersClean("clean keyboard"))
    #expect(
      !offersClean("ck", [BuiltinCommand.cleanKeyboard.settingsKey: ItemSettings(alias: "ck")]))
  }

  @Test func readsABareNumberAsSeconds() {
    #expect(
      Search.results(for: "clean keyboard 30", apps: [], quicklinks: []).first?.action
        == .cleanKeyboard(30))
    #expect(
      !Search.results(for: "clean keyboard 0", apps: [], quicklinks: []).contains {
        if case .cleanKeyboard = $0.action { true } else { false }
      })
  }

  @Test func takesATypedTimeUpToFiveMinutes() {
    #expect(
      Search.results(for: "clean keyboard 45s", apps: [], quicklinks: []).first?.action
        == .cleanKeyboard(45))
    // Past five minutes, no keyboard-off row at all.
    #expect(
      !Search.results(for: "clean keyboard 10m", apps: [], quicklinks: []).contains {
        if case .cleanKeyboard = $0.action { true } else { false }
      })
  }

  @Test func plainCaffeinateAndSleepTimerStillNeedATime() {
    #expect(
      !Search.results(for: "caffeinate", apps: [], quicklinks: []).contains {
        $0.id == "caffeinate-for"
      })
    #expect(
      !Search.results(for: "sleep timer", apps: [], quicklinks: []).contains { $0.id == "sleep-in" }
    )
  }
}
