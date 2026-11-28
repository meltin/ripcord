import Foundation
import Testing

@testable import RipcordCore

@Suite struct LidAwakeTests {
  @Test func aTimeTypedAfterItsNameTurnsItOnForThatLong() throws {
    let sections = Search.sections(for: "lid awake 2h", apps: [], quicklinks: [])
    let row = try #require(sections.first?.results.first { $0.id == "lid-awake-for" })
    #expect(row.action == .lidAwake(7200))
    #expect(row.title.hasPrefix("Lid Awake for"))
  }

  @Test func whileOnARowStaysAtTheTopOfTheRootSearch() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let timed = try #require(
      Search.lidAwakeSection(LidAwakeStatus(endsAt: now.addingTimeInterval(5400)), now: now))
    #expect(timed.results.first?.action == .stopLidAwake)
    #expect(timed.results.first?.subtitle.hasSuffix("left") == true)
    let open = try #require(Search.lidAwakeSection(LidAwakeStatus(endsAt: nil), now: now))
    #expect(open.results.first?.subtitle == "Until turned off")
    #expect(Search.lidAwakeSection(nil) == nil)
    let root = Search.sections(
      for: "", apps: [], quicklinks: [], lidAwake: LidAwakeStatus(endsAt: nil))
    #expect(root.first?.title == "Lid Awake")
  }

  @Test func turnsItselfOffOnlyOnALowBattery() {
    #expect(BatteryLevel(percent: 9, onBattery: true).isLow(below: 10))
    #expect(!BatteryLevel(percent: 9, onBattery: false).isLow(below: 10))
    #expect(!BatteryLevel(percent: 50, onBattery: true).isLow(below: 10))
    #expect(!BatteryLevel(percent: 1, onBattery: true).isLow(below: 0))
  }
}
