import Testing

@testable import RipcordCore

struct DummyTextTests {
  /// The same text every run, so a failure can be read again.
  struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return state
    }
  }

  @Test(arguments: [0, 1, 5, 6, 40, 280, 10_000])
  func isExactlyAsLongAsAsked(length: Int) {
    for seed in 1...20 {
      var random = Seeded(state: UInt64(seed))
      #expect(DummyText.generate(.japanese, length: length, using: &random).count == length)
      #expect(DummyText.generate(.english, length: length, using: &random).count == length)
    }
  }

  @Test func endsJapaneseOnASentenceEnd() {
    for seed in 1...50 {
      var random = Seeded(state: UInt64(seed))
      let text = DummyText.generate(.japanese, length: 37, using: &random)
      #expect("。！？".contains(text.last ?? " "))
    }
  }

  @Test func startsEnglishWithACapital() {
    var random = Seeded(state: 7)
    #expect(DummyText.generate(.english, length: 200, using: &random).first?.isUppercase == true)
  }

  @Test func readsTheLengthAsRaycastDoes() {
    #expect(DummyText.length(from: "") == 1)
    #expect(DummyText.length(from: "abc") == 1)
    #expect(DummyText.length(from: " 120 ") == 120)
    #expect(DummyText.length(from: "-3") == 0)
    #expect(DummyText.length(from: "99999") == 10_000)
  }

  @Test func offersThePreferredLanguageFirst() {
    #expect(DummyText.arguments(preferred: .english)[1].initialValue == "en")
    #expect(DummyText.arguments(preferred: .japanese)[1].initialValue == "ja")
  }
}
