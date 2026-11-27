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

  @Test func caffeinateForAddsItsFields() {
    #expect(Coffee.duration(hours: "1", minutes: "30", seconds: "") == 5400)
    #expect(Coffee.duration(hours: "", minutes: "", seconds: "45") == 45)
    #expect(Coffee.duration(hours: "", minutes: "", seconds: "") == nil)
    #expect(Coffee.duration(hours: "1.5", minutes: "", seconds: "") == nil)
    #expect(Coffee.duration(hours: "-1", minutes: "", seconds: "") == nil)
    #expect(Coffee.duration(hours: "999", minutes: "", seconds: "") == nil)
  }

  @Test func caffeinateUntilReadsATimeOfDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    // 14:00 in Tokyo.
    let now = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 14)))
    #expect(Coffee.until("5pm", now: now, calendar: calendar) == 3.0 * 3600)
    #expect(Coffee.until("5:30 PM", now: now, calendar: calendar) == 3.5 * 3600)
    #expect(Coffee.until("17:30", now: now, calendar: calendar) == 3.5 * 3600)
    #expect(Coffee.until("12am", now: now, calendar: calendar) == 10.0 * 3600)
    // A bare hour is the next of its two: 9 at 14:00 is 21:00; with a leading 0, 9 tomorrow.
    #expect(Coffee.until("9", now: now, calendar: calendar) == 7.0 * 3600)
    #expect(Coffee.until("09", now: now, calendar: calendar) == 19.0 * 3600)
    #expect(Coffee.until("5", now: now, calendar: calendar) == 3.0 * 3600)
    for text in ["", "25:00", "5:75", "noon", "5 o'clock"] {
      #expect(Coffee.until(text, now: now, calendar: calendar) == nil, "\(text)")
    }
  }

  @Test func statusSaysWhatKeepsTheMacAwake() {
    #expect(Coffee.status(isActive: false, remaining: nil, whileApp: nil) == "Not caffeinated")
    #expect(
      Coffee.status(isActive: true, remaining: nil, whileApp: nil)
        == "Caffeinated until Decaffeinate")
    #expect(
      Coffee.status(isActive: true, remaining: 4000, whileApp: nil)
        == "Caffeinated for 1h 6m more")
    #expect(
      Coffee.status(isActive: true, remaining: nil, whileApp: "Xcode")
        == "Caffeinated while Xcode is running")
  }
}
