import Foundation
import Testing

@testable import RipcordControl
@testable import RipcordCore

struct ConfigEditingTests {
  let file = Data(#"{"hotkey":"cmd+space","colorFormat":"hex","quicklinks":[]}"#.utf8)

  @Test func getsTheWholeFileOrOneKey() throws {
    #expect(try Config.get(nil, from: file) == String(decoding: file, as: UTF8.self))
    #expect(try Config.get("hotkey", from: file) == #""cmd+space""#)
    // Left out of the file: the default Ripcord uses, or null for one without.
    #expect(try Config.get("launchAtLogin", from: file) == "false")
    #expect(try Config.get("inputSource", from: file) == "null")
    #expect(throws: Config.EditError.self) { try Config.get("nope", from: file) }
  }

  @Test func setsAKeyToAJSONValue() throws {
    #expect(try Config.setting("colorFormat", to: #""rgb""#, in: file).colorFormat == .rgb)
    #expect(try Config.setting("launchAtLogin", to: "true", in: file).launchAtLogin)
    let abc = #""com.apple.keylayout.ABC""#
    #expect(try Config.setting("inputSource", to: abc, in: file).inputSource != nil)
    #expect(try Config.setting("inputSource", to: "null", in: file).inputSource == nil)
  }

  @Test func knowsEveryKeyEvenOnesLeftOutByDefault() {
    #expect(Config.keys.isSuperset(of: ["inputSource", "hotkey", "backdrop", "snippets"]))
  }

  @Test func refusesUnknownKeysBadJSONAndValuesThatWouldChange() {
    #expect(throws: Config.EditError.self) { try Config.setting("nope", to: "1", in: file) }
    #expect(throws: Config.EditError.self) { try Config.setting("hotkey", to: "cmd+x", in: file) }
    // Read leniently as hex, so refused rather than saved as something else.
    #expect(throws: Config.EditError.self) {
      try Config.setting("colorFormat", to: #""purple""#, in: file)
    }
    #expect(throws: Config.EditError.self) {
      try Config.setting("launchAtLogin", to: #""yes""#, in: file)
    }
  }

  @Test func parsesTheCommandsArguments() throws {
    #expect(try Control.request(from: ["open"]).get() == .open(query: nil))
    #expect(try Control.request(from: ["open", "--query", "a b"]).get() == .open(query: "a b"))
    #expect(
      try Control.request(from: ["pick"], stdin: { "one\n\ntwo\n" }).get()
        == .pick(items: ["one", "two"], placeholder: nil))
    #expect(try Control.request(from: ["config", "get"]).get() == .configGet(key: nil))
    #expect(
      try Control.request(from: ["config", "set", "hotkey", #""cmd+space""#]).get()
        == .configSet(key: "hotkey", json: #""cmd+space""#))
    #expect((try? Control.request(from: ["config"]).get()) == nil)
    #expect((try? Control.request(from: ["nope"]).get()) == nil)
    #expect(ControlResponse(cancelled: true).exitCode == 1)
    #expect(ControlResponse(error: "x").exitCode == 2)
  }
}
