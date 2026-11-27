import Testing

@testable import RipcordCore

struct SettingsSearchTests {
  let pages = [
    SettingsSearch.Page(
      name: "General",
      settings: [
        .init(title: "Ripcord Hotkey", detail: "Shows the panel from any app."),
        .init(title: "Launch at Login", detail: "Start Ripcord when you log in."),
      ]),
    SettingsSearch.Page(
      name: "Clipboard History", commands: [.init(title: "Clipboard History")]),
    SettingsSearch.Page(name: "Shortcuts"),
  ]

  @Test func listsEveryPageWhileBlank() {
    #expect(SettingsSearch.results("  ", in: pages) == nil)
  }

  @Test func findsAPageByASettingWithOnlyThatSetting() {
    #expect(
      SettingsSearch.results("hot", in: pages)
        == [
          .init(
            name: "General",
            settings: [.init(title: "Ripcord Hotkey", detail: "Shows the panel from any app.")])
        ])
  }

  @Test func findsASettingByItsDescription() {
    #expect(
      SettingsSearch.results("log in", in: pages)?.first?.settings.map(\.title) == [
        "Launch at Login"
      ])
  }

  @Test func findsAPageByItsNameAlone() {
    #expect(SettingsSearch.results("short", in: pages) == [.init(name: "Shortcuts")])
  }

  @Test func findsAPageAndItsCommand() {
    let found = SettingsSearch.results("clip", in: pages)
    #expect(found?.map(\.name) == ["Clipboard History"])
    #expect(found?.first?.commands.map(\.title) == ["Clipboard History"])
  }

  @Test func findsNothing() {
    #expect(SettingsSearch.results("zzz", in: pages) == [])
  }
}
