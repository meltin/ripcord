import Testing

@testable import RipcordCore

struct ArgumentFieldNavigationTests {
  @Test func tabGoesThroughEveryFieldAndBackToTheSearchField() {
    #expect(ArgumentFieldNavigation.next(from: nil, count: 2, back: false) == 0)
    #expect(ArgumentFieldNavigation.next(from: 0, count: 2, back: false) == 1)
    #expect(ArgumentFieldNavigation.next(from: 1, count: 2, back: false) == nil)
    #expect(ArgumentFieldNavigation.next(from: nil, count: 2, back: true) == 1)
    #expect(ArgumentFieldNavigation.next(from: 0, count: 2, back: true) == nil)
    #expect(ArgumentFieldNavigation.next(from: nil, count: 0, back: false) == nil)
  }

  @Test func arrowsStepADropdownWithoutWrapping() {
    let values = ["ja", "en"]
    #expect(ArgumentFieldNavigation.step("", in: values, up: false) == "ja")
    #expect(ArgumentFieldNavigation.step("ja", in: values, up: false) == "en")
    #expect(ArgumentFieldNavigation.step("en", in: values, up: false) == "en")
    #expect(ArgumentFieldNavigation.step("en", in: values, up: true) == "ja")
    #expect(ArgumentFieldNavigation.step("ja", in: values, up: true) == "")
    #expect(ArgumentFieldNavigation.step("", in: values, up: true) == "")
  }

  @Test func filtersByTheStartOfAWord() {
    let titles = ["Japanese", "English", "Plain Text"]
    #expect(ArgumentFieldNavigation.matches("e", in: titles) == [1])
    #expect(ArgumentFieldNavigation.matches("TE", in: titles) == [2])
    #expect(ArgumentFieldNavigation.matches("", in: titles) == [0, 1, 2])
    #expect(ArgumentFieldNavigation.matches("x", in: titles).isEmpty)
  }

  @Test func keepsOnlyTheDropdownsChoices() {
    let arguments = [
      ScriptCommand.Argument(type: .text, placeholder: "zqx"),
      ScriptCommand.Argument(type: .password, placeholder: "zqx"),
      ScriptCommand.Argument(type: .dropdown, placeholder: "zqx"),
    ]
    #expect(
      ArgumentFieldNavigation.keepingChoices(["a", "secret", "en"], of: arguments) == [
        "", "", "en",
      ])
    #expect(ArgumentFieldNavigation.keepingChoices(["a", "secret", ""], of: arguments) == nil)
  }

  @Test func aSpaceAfterAnAliasEntersTheFields() {
    #expect(
      ArgumentFieldNavigation.spaceEntersFields(
        previous: "lorem", query: "lorem ", alias: "Lorem", takesArguments: true))
    #expect(
      !ArgumentFieldNavigation.spaceEntersFields(
        previous: "lorem", query: "lorem ", alias: "lorem", takesArguments: false))
    #expect(
      !ArgumentFieldNavigation.spaceEntersFields(
        previous: "lore", query: "lore ", alias: "lorem", takesArguments: true))
    #expect(
      !ArgumentFieldNavigation.spaceEntersFields(
        previous: "lorem", query: "lorem x", alias: "lorem", takesArguments: true))
  }
}
