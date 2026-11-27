import Foundation
import Testing

@testable import RipcordControl

struct MCPTests {
  /// The answer to `message` as an object, with what the fake app was asked.
  func answer(_ message: String, reply: ControlResponse = ControlResponse())
    -> (object: [String: Any]?, asked: ControlRequest?)
  {
    var asked: ControlRequest?
    let data = MCP.respond(to: Data(message.utf8)) { request in
      asked = request
      return reply
    }
    let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    return (object, asked)
  }

  func result(_ object: [String: Any]?) -> [String: Any]? { object?["result"] as? [String: Any] }

  @Test func initializesWithTheClientsVersionOrTheLatest() {
    let known = answer(
      #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
    #expect(result(known.object)?["protocolVersion"] as? String == "2025-06-18")
    #expect(known.object?["id"] as? Int == 1)
    let unknown = answer(
      #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#
    )
    #expect(result(unknown.object)?["protocolVersion"] as? String == "2025-11-25")
  }

  @Test func listsFourToolsAndLeavesNotificationsUnanswered() {
    let list = answer(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
    let names = (result(list.object)?["tools"] as? [[String: Any]])?.compactMap {
      $0["name"] as? String
    }
    #expect(names == ["open_panel", "pick", "get_config", "set_config"])
    #expect(
      MCP.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)) {
        _ in ControlResponse()
      } == nil)
    let unknown = answer(#"{"jsonrpc":"2.0","id":3,"method":"server/discover"}"#)
    #expect((unknown.object?["error"] as? [String: Any])?["code"] as? Int == -32601)
  }

  @Test func turnsEachToolIntoItsRequest() {
    func call(_ name: String, _ arguments: String) -> ControlRequest? {
      answer(
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
      ).asked
    }
    #expect(call("open_panel", #"{"query":"zqx"}"#) == .open(query: "zqx"))
    #expect(
      call("pick", #"{"items":["zqx a","","zqx b"]}"#)
        == .pick(items: ["zqx a", "zqx b"], placeholder: nil))
    #expect(call("get_config", "{}") == .configGet(key: nil))
    #expect(
      call("set_config", #"{"key":"colorFormat","value":"rgb"}"#)
        == .configSet(key: "colorFormat", json: #""rgb""#))
    // Null clears; a value left out never reaches the app.
    #expect(
      call("set_config", #"{"key":"inputSource","value":null}"#)
        == .configSet(key: "inputSource", json: "null"))
    #expect(call("set_config", #"{"key":"inputSource"}"#) == nil)
  }

  @Test func reportsTheAppsErrorsAndACancelledPickAsToolErrors() {
    let call =
      #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"pick","arguments":{"items":["zqx"]}}}"#
    let picked = result(answer(call, reply: ControlResponse(output: "zqx")).object)
    #expect(picked?["isError"] as? Bool == false)
    #expect((picked?["content"] as? [[String: Any]])?.first?["text"] as? String == "zqx")
    #expect(
      result(answer(call, reply: ControlResponse(cancelled: true)).object)?["isError"] as? Bool
        == true)
    #expect(
      result(answer(call, reply: ControlResponse(error: "x")).object)?["isError"] as? Bool == true)
  }
}
