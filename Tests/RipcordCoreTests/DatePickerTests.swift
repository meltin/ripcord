import Foundation
import Testing

@testable import RipcordCore

struct DatePickerTests {
  private static let japan = Locale(identifier: "ja_JP")
  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
    calendar.firstWeekday = 1
    return calendar
  }()

  private func day(_ month: Int, _ day: Int) throws -> Date {
    try #require(Self.calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
  }

  private func text(_ selection: DateSelection, _ settings: DatePickerSettings = .init()) -> String
  {
    settings.text(for: selection, locale: Self.japan)
  }

  @Test func writesTheDayPickedInTheFormat() throws {
    var dates = DateSelection(day: try day(11, 28), calendar: Self.calendar)
    #expect(text(dates) == "2026/11/28(土)")
    #expect(text(dates, DatePickerSettings(format: "yyyy-MM-dd")) == "2026-11-28")
    // An empty pattern writes the default rather than nothing.
    #expect(text(dates, DatePickerSettings(format: " ")) == "2026/11/28(土)")
    // Arrows: a day, then a week; the month follows into December.
    dates.move(by: 1)
    dates.move(by: 7)
    #expect(text(dates) == "2026/12/06(日)")
    #expect(dates.month == (try day(12, 1)))
  }

  @Test func joinsDaysCommandClickedEarliestFirst() throws {
    var dates = DateSelection(day: try day(11, 28), calendar: Self.calendar)
    dates.click(try day(11, 3), command: true)
    dates.click(try day(11, 10), command: true)
    #expect(text(dates) == "2026/11/03(火), 2026/11/10(火), 2026/11/28(土)")
    // Clicked again, a day comes out; the last one left stays.
    dates.click(try day(11, 10), command: true)
    dates.click(try day(11, 3), command: true)
    dates.click(try day(11, 28), command: true)
    #expect(text(dates) == "2026/11/28(土)")
    // A day taken out isn't where a range starts: it goes on from the last one added.
    dates.click(try day(11, 20), command: true)
    dates.click(try day(11, 20), command: true)
    dates.click(try day(11, 26), shift: true)
    #expect(text(dates, DatePickerSettings(format: "d")) == "26〜28")
  }

  @Test func writesAShiftClickedRangeEitherWayRound() throws {
    var dates = DateSelection(day: try day(11, 28), calendar: Self.calendar)
    dates.click(try day(11, 24), shift: true)
    #expect(text(dates) == "2026/11/24(火)〜2026/11/28(土)")
    #expect(dates.isPicked(try day(11, 26)))
    #expect(!dates.isPicked(try day(11, 29)))
    let spaced = DatePickerSettings(rangeSeparator: "-", spacesAroundRange: true)
    #expect(text(dates, spaced) == "2026/11/24(火) - 2026/11/28(土)")
    // ⌘-click after a range keeps its days and adds one.
    dates.click(try day(11, 30), command: true)
    #expect(text(dates, DatePickerSettings(format: "d")) == "24, 25, 26, 27, 28, 30")
  }

  @Test func showsSixWeeksFromTheWeekTheMonthStartsIn() throws {
    var dates = DateSelection(day: try day(11, 28), calendar: Self.calendar)
    // November 2026 starts on a Sunday, the week's first day here.
    #expect(dates.grid.count == 42)
    #expect(dates.grid.first == (try day(11, 1)))
    dates.showMonth(by: 1)
    #expect(dates.grid.first == (try day(11, 29)))
    // The header's arrows leave what's picked.
    #expect(text(dates) == "2026/11/28(土)")
  }

  @Test func ordersReturnByThePrimaryAction() throws {
    let dates = DateSelection(day: try day(11, 28), calendar: Self.calendar)
    let paste = try #require(
      Search.datePickerSections(dates, settings: .init(), locale: Self.japan).first?.results.first)
    #expect(paste.action == .pasteText("2026/11/28(土)"))
    #expect(paste.actions.map(\.shortcut) == ["↵", "⌘↵"])
    let copy = try #require(
      Search.datePickerSections(dates, settings: .init(primaryAction: .copy), locale: Self.japan)
        .first?.results.first)
    #expect(copy.action == .copy("2026/11/28(土)"))
    #expect(copy.actions.map(\.title) == ["Copy to Clipboard", "Paste to App"])
  }

  @Test func keepsSeparatorsSpacesAndAllThroughTheConfig() throws {
    let settings = DatePickerSettings(primaryAction: .copy, separator: " / ")
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(DatePickerSettings.self, from: data) == settings)
    // A config from before Pick Date reads its defaults.
    #expect(try JSONDecoder().decode(DatePickerSettings.self, from: Data("{}".utf8)) == .init())
  }
}
