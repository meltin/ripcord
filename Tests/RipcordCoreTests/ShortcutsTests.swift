import Carbon.HIToolbox
import Foundation
import Testing

@testable import RipcordCore

@Suite struct ItemSettingsTests {
  @Test func dropsEntriesThatAreBackToDefaults() {
    var config = Config.default
    config.setItem("com.example.app", ItemSettings(alias: "my ap"))
    #expect(config.item("com.example.app").alias == "my ap")
    config.setItem("com.example.app", ItemSettings(alias: "   "))
    #expect(config.items.isEmpty)
    var off = ItemSettings()
    off.isEnabled = false
    config.setItem("com.example.app", off)
    #expect(config.items["com.example.app"]?.disabled == true)
    off.isEnabled = true
    config.setItem("com.example.app", off)
    #expect(config.items.isEmpty)
  }

  @Test func clearedItemsLeaveNoTraceInTheSavedFile() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var config = Config.default
    config.setItem("com.example.app", ItemSettings(alias: "ex", hotkey: "cmd+shift+e"))
    config.setItem("com.example.app", ItemSettings())
    try config.save(to: url)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(!text.contains("com.example.app"))
    #expect(!text.contains("disabled"))
  }

  @Test func readsFilesWrittenBeforeShortcutsExisted() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(
      #"{"hotkey": "ctrl+space", "quicklinks": [{"name": "G", "url": "https://g.co/?q={query}"}]}"#
        .utf8
    ).write(to: url)
    let config = try Config.load(from: url)
    #expect(config.items.isEmpty)
    #expect(config.quicklinks[0].hotkey == nil)
    #expect(config.quicklinks[0].isEnabled)
  }
}

@Suite struct HotkeyAssignmentTests {
  let config = Config(
    hotkey: "cmd+space",
    quicklinks: [
      Quicklink(name: "Google", url: "https://g.co/?q={query}", hotkey: "cmd+shift+g"),
      Quicklink(name: "Broken", url: "https://b.co", hotkey: "cmd+f13"),
    ],
    items: [
      "com.apple.Safari": ItemSettings(hotkey: "cmd+shift+s"),
      "command:quit": ItemSettings(alias: "q"),
    ])

  @Test func listsTheLauncherFirstAndSkipsSpecsThatDontParse() {
    let targets = config.hotkeyAssignments.map(\.target)
    #expect(targets == [.launcher, .item("com.apple.Safari"), .quicklink(0)])
  }

  @Test func switchedOffItemsKeepTheirHotkeyReservedButUnregistered() throws {
    var config = config
    config.items["com.apple.Safari"]?.isEnabled = false
    config.quicklinks[0].isEnabled = false
    #expect(config.hotkeyAssignments.map(\.target) == [.launcher])
    let safari = try #require(Hotkey("shift+cmd+s"))
    #expect(config.owner(of: safari, except: .launcher) == .item("com.apple.Safari"))
  }

  @Test func refusesShiftOnlyKeyPresses() {
    #expect(Hotkey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(shiftKey)) == nil)
    #expect(Hotkey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(shiftKey | optionKey)) != nil)
  }

  @Test func findsClashesWithinRipcordButNotWithItself() throws {
    let safari = try #require(Hotkey("shift+cmd+s"))
    #expect(
      config.owner(of: safari, except: .item("com.example.other")) == .item("com.apple.Safari"))
    #expect(config.owner(of: safari, except: .item("com.apple.Safari")) == nil)
    let launcher = try #require(Hotkey("cmd+space"))
    #expect(config.owner(of: launcher, except: .quicklink(0)) == .launcher)
    let free = try #require(Hotkey("cmd+shift+x"))
    #expect(config.owner(of: free, except: .launcher) == nil)
  }
}

@Suite struct ShortcutSearchTests {
  let photoshop = AppEntry(
    url: URL(fileURLWithPath: "/Applications/Adobe Photoshop 2026.app"),
    names: ["Adobe Photoshop 2026"], bundleID: "com.adobe.Photoshop")
  let remotePlay = AppEntry(
    url: URL(fileURLWithPath: "/Applications/PS Remote Play.app"), names: ["PS Remote Play"],
    bundleID: "com.playstation.RemotePlay")
  let links = [
    Quicklink(name: "Google", url: "https://g.co/?q={query}", keyword: "g", disabled: true),
    Quicklink(name: "GitHub", url: "https://github.com/search?q={query}", keyword: "gh"),
  ]

  @Test func anExactAliasBeatsANameThatStartsWithIt() {
    let items = ["com.adobe.Photoshop": ItemSettings(alias: "ps")]
    let results = Search.results(
      for: "ps", apps: [remotePlay, photoshop], quicklinks: [], items: items)
    #expect(results.first?.title == "Adobe Photoshop 2026")
    #expect(results.first?.keyword == "ps")
  }

  @Test func anExactQuicklinkKeywordActsAsItsAlias() {
    // A Quicklink's keyword is its alias, so typing it exactly puts the link first, as Raycast
    // does, even above an app whose name starts with the same letter.
    let chrome = AppEntry(
      url: URL(fileURLWithPath: "/Applications/Google Chrome.app"), names: ["Google Chrome"])
    let google = [Quicklink(name: "Google Search", url: "https://g.co/?q={query}", keyword: "g")]
    let results = Search.results(for: "g", apps: [chrome], quicklinks: google)
    #expect(results.first?.title == "Google Search")
  }

  @Test func aStrayTrailingSpaceDoesNotBreakAnAliasOrKeyword() {
    let items = ["com.adobe.Photoshop": ItemSettings(alias: "ps ")]
    let aliased = Search.results(
      for: "ps", apps: [remotePlay, photoshop], quicklinks: [], items: items)
    #expect(aliased.first?.title == "Adobe Photoshop 2026")
    let spaced = [
      Quicklink(name: "GitHub", url: "https://github.com/search?q={query}", keyword: "gh ")
    ]
    let expanded = Search.results(for: "gh cats", apps: [], quicklinks: spaced)
    #expect(expanded.first?.action == .open(URL(string: "https://github.com/search?q=cats")!))
  }

  @Test func disabledAppsAndCommandsDisappearEverywhere() {
    let items = [
      "com.adobe.Photoshop": ItemSettings(disabled: true),
      "command:quit": ItemSettings(disabled: true),
    ]
    #expect(
      Search.results(for: "photoshop", apps: [photoshop], quicklinks: [], items: items).isEmpty)
    #expect(
      !Search.results(for: "quit", apps: [], quicklinks: [], items: items)
        .contains { $0.action == .run(.quit) })
    let start = Search.sections(
      for: "", apps: [], running: [photoshop, remotePlay], quicklinks: [], items: items)
    #expect(start.first?.results.map(\.title) == ["PS Remote Play"])
  }

  @Test func disabledQuicklinksDisappearEverywhere() {
    let start = Search.sections(for: "", apps: [], running: [], quicklinks: links)
    #expect(start.flatMap(\.results).map(\.title) == ["GitHub"])
    let expanded = Search.results(for: "g cats", apps: [], quicklinks: links)
    #expect(!expanded.contains { $0.subtitle == "Google" })
    let fallback = Search.sections(for: "zzqq", apps: [], running: [], quicklinks: links)
    #expect(fallback.flatMap(\.results).map(\.title) == ["GitHub"])
  }

  @Test func catalogListsEveryItemInThreeSections() {
    let catalog = Search.catalog(apps: [remotePlay, photoshop], quicklinks: links)
    #expect(catalog.map(\.title) == ["Applications", "Quicklinks", "Ripcord"])
    #expect(catalog[0].entries.map(\.title) == ["Adobe Photoshop 2026", "PS Remote Play"])
    #expect(catalog[0].entries[0].target == .item("com.adobe.Photoshop"))
    // The Shortcuts page lists disabled Quicklinks too, so they can be turned back on.
    #expect(catalog[1].entries.map(\.target) == [.quicklink(0), .quicklink(1)])
    #expect(catalog[2].entries.map(\.target).contains(.item("command:quit")))
  }

  @Test func catalogListsAnAppFoundAtTwoPathsOnce() {
    let copy = AppEntry(
      url: URL(fileURLWithPath: "/Users/me/Applications/Adobe Photoshop 2026.app"),
      names: ["Adobe Photoshop 2026"], bundleID: "com.adobe.Photoshop")
    let catalog = Search.catalog(apps: [photoshop, copy], quicklinks: [])
    #expect(catalog[0].entries.count == 1)
  }

  @Test func commandSettingsKeysAreFixed() {
    // Saved in config.json: changing one strands the user's alias and hotkey.
    #expect(BuiltinCommand.clipboardHistory.settingsKey == "command:clipboard-history")
    #expect(BuiltinCommand.searchSnippets.settingsKey == "command:search-snippets")
    #expect(BuiltinCommand.createSnippet.settingsKey == "command:create-snippet")
    #expect(BuiltinCommand.exportSnippets.settingsKey == "command:export-snippets")
    #expect(BuiltinCommand.importSnippets.settingsKey == "command:import-snippets")
    #expect(BuiltinCommand.settings.settingsKey == "command:settings")
    #expect(BuiltinCommand.resetWindowPosition.settingsKey == "command:reset-window-position")
    #expect(BuiltinCommand.quit.settingsKey == "command:quit")
  }

  @Test func appsAreKeyedByBundleID() {
    #expect(photoshop.settingsKey == "com.adobe.Photoshop")
    let unbundled = AppEntry(url: URL(fileURLWithPath: "/Applications/Odd.app"), names: ["Odd"])
    #expect(unbundled.settingsKey == "/Applications/Odd.app")
    let finder = AppIndex.scan().first { $0.names.contains("Finder") }
    #expect(finder?.bundleID == "com.apple.finder")
  }
}
