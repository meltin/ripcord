import Foundation
import Testing

@testable import RipcordCore

@Suite struct CleanKeyboardTests {
  @Test func offersTheUsualTimesBeforeOneIsTyped() {
    let rows = Search.results(for: "clean keyboard", apps: [], quicklinks: []).prefix(4)
    #expect(
      rows.map(\.title) == [
        "Clean Keyboard for 15s", "Clean Keyboard for 30s", "Clean Keyboard for 1m",
        "Clean Keyboard for 2m",
      ])
    #expect(rows.first?.action == .cleanKeyboard(15))
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
