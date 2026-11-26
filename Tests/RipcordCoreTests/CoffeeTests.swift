import Foundation
import Testing

@testable import RipcordCore

@Suite struct CoffeeTests {
  @Test func readsTheTimeTypedAfterCaffeinate() {
    #expect(Coffee.duration(from: "1h 30m") == 5400)
    #expect(Coffee.duration(from: "1h30m") == 5400)
    #expect(Coffee.duration(from: "90m") == 5400)
    #expect(Coffee.duration(from: "1.5h") == 5400)
    #expect(Coffee.duration(from: "45s") == 45)
    #expect(Coffee.duration(from: "20") == 1200)
    #expect(Coffee.duration(from: " 2H ") == 7200)
  }

  @Test func refusesWhatIsNotATime() {
    for text in [
      "", "soon", "1h 30", "h", "0m", "-5", "1x", "inf", "1e20", "0x10", "200h",
      "99999999999999999999h",
    ] {
      #expect(Coffee.duration(from: text) == nil, "\(text)")
    }
  }

  @Test func showsTheTimeAsRaycastDoes() {
    #expect(Coffee.format(5400) == "1h 30m")
    #expect(Coffee.format(3600) == "1h")
    #expect(Coffee.format(90) == "1m 30s")
    #expect(Coffee.format(3630) == "1h 30s")
    #expect(Coffee.format(30) == "30s")
    // The menu bar's countdown drops the seconds from a minute up.
    #expect(Coffee.format(5340.5, seconds: false) == "1h 29m")
    #expect(Coffee.format(42, seconds: false) == "42s")
    #expect(Coffee.format(.infinity) == "168h")
  }

  @Test func filesItsCommandsUnderCoffee() {
    #expect(
      Search.results(for: "decaffeinate", apps: [], quicklinks: []).first?.subtitle == "Coffee")
  }

  @Test func caffeinateWithATimeComesFirst() throws {
    let first = try #require(
      Search.results(for: "caffeinate 1h 30m", apps: [], quicklinks: []).first)
    #expect(first.title == "Caffeinate for 1h 30m")
    #expect(first.action == .caffeinate(5400))
    // By its alias too, and not without a time it can read.
    let items = [BuiltinCommand.caffeinate.settingsKey: ItemSettings(alias: "cof")]
    #expect(
      Search.results(for: "cof 20m", apps: [], quicklinks: [], items: items).first?.action
        == .caffeinate(1200))
    #expect(
      !Search.results(for: "caffeinate soon", apps: [], quicklinks: []).contains {
        $0.id == "caffeinate-for"
      })
    // Plain Caffeinate runs until Decaffeinate.
    #expect(
      Search.results(for: "caffeinate", apps: [], quicklinks: []).first?.action
        == .run(.caffeinate))
  }

  @Test func aSwitchedOffCaffeinateTakesNoTime() {
    let items = [BuiltinCommand.caffeinate.settingsKey: ItemSettings(disabled: true)]
    #expect(
      !Search.results(for: "caffeinate 1h", apps: [], quicklinks: [], items: items).contains {
        $0.id == "caffeinate-for"
      })
  }
}
