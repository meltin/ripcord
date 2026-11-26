import Testing

@testable import RipcordCore

@Suite struct BrowserTabTests {
  @Test func speaksEachBrowsersTerms() throws {
    let safari = try #require(BrowserTab.script(forBundleID: "com.apple.Safari"))
    #expect(safari.contains("current tab of front window"))
    #expect(safari.contains("(name of theTab)"))
    let arc = try #require(BrowserTab.script(forBundleID: "company.thebrowser.Browser"))
    #expect(arc.contains("active tab of front window"))
    #expect(arc.contains("(title of theTab)"))
    #expect(BrowserTab.script(forBundleID: "com.apple.finder") == nil)
  }

  @Test func readsTheURLAndTitle() {
    let tab = BrowserTab.parse("https://tabler.io/icons\nTabler Icons: 6550+ free icons\n")
    #expect(tab?.url == "https://tabler.io/icons")
    #expect(tab?.title == "Tabler Icons: 6550+ free icons")
    #expect(BrowserTab.parse("") == nil)
    #expect(BrowserTab.parse("not a url\nTitle") == nil)
    #expect(BrowserTab.parse("chrome://newtab/\nNew Tab") == nil)
  }
}
