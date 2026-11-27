import Testing

@testable import RipcordCore

struct PickTests {
  @Test func listsEveryLineOrTheMatchesBestFirst() {
    let items = ["zqx alpha", "zqx beta", "zqx alpha"]
    #expect(
      Search.pickSections(for: "", items: items).first?.results.map(\.id) == [
        "pick:0", "pick:1", "pick:2",
      ])
    // Equal lines stay apart, each its own row.
    #expect(
      Search.pickSections(for: "alp", items: items).first?.results.map(\.action) == [
        .pick(0), .pick(2),
      ])
    #expect(Search.pickSections(for: "nothing", items: items).isEmpty)
  }
}
