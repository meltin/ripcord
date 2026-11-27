import Foundation

/// `ripcord mcp`: a Model Context Protocol server on stdin and stdout, one JSON-RPC message a
/// line, whose tools are the `ripcord` command's own. It speaks the versions that begin with
/// `initialize`; a client of the later, stateless ones probes with `server/discover`, gets
/// "method not found", and falls back to them, as the spec has it.
public enum MCP {
  static let versions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]

  static var tools: [[String: Any]] {
    [
      [
        "name": "open_panel",
        "description": "Open Ripcord's launcher panel, optionally with a search query typed in.",
        "inputSchema": [
          "type": "object",
          "properties": [
            "query": ["type": "string", "description": "Text to type in the search."]
          ],
        ],
      ],
      [
        "name": "pick",
        "description":
          "Show lines in Ripcord's panel and wait for the user to pick one, which is returned as is. Ends as an error if the user closes the panel without picking.",
        "inputSchema": [
          "type": "object",
          "properties": [
            "items": [
              "type": "array", "items": ["type": "string"],
              "description": "The lines to choose from, up to 10,000.",
            ],
            "placeholder": ["type": "string", "description": "The search field's placeholder."],
          ],
          "required": ["items"],
        ],
      ],
      [
        "name": "get_config",
        "annotations": ["readOnlyHint": true],
        "description":
          "Read Ripcord's configuration: the whole config.json, or one top-level key's value as JSON.",
        "inputSchema": [
          "type": "object",
          "properties": ["key": ["type": "string", "description": "A top-level key."]],
        ],
      ],
      [
        "name": "set_config",
        "description":
          "Validate and apply a change to one top-level key of Ripcord's configuration. The value replaces the key's whole value; null clears a key that can be left out. A value Ripcord can't take is refused and nothing changes.",
        "inputSchema": [
          "type": "object",
          "properties": [
            "key": ["type": "string", "description": "A top-level key."],
            "value": ["description": "The key's new value, as get_config prints it."],
          ],
          "required": ["key", "value"],
        ],
      ],
    ]
  }

  /// The answer to one message, or nil for a notification or a line that's no request.
  /// `send` asks the app; a tool call blocks on it, a pick until the user picks.
  public static func respond(to line: Data, send: (ControlRequest) -> ControlResponse) -> Data? {
    guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
      return encode(["jsonrpc": "2.0", "id": NSNull(), "error": error(-32700, "Parse error")])
    }
    // A notification (no id), such as notifications/initialized or /cancelled, gets no answer.
    guard let id = message["id"], let method = message["method"] as? String else { return nil }
    let params = message["params"] as? [String: Any] ?? [:]
    let outcome: [String: Any]
    switch method {
    case "initialize":
      let requested = params["protocolVersion"] as? String
      outcome = [
        "result": [
          "protocolVersion": requested.flatMap { versions.contains($0) ? $0 : nil }
            ?? versions.last ?? "",
          "capabilities": ["tools": [:]],
          "serverInfo": ["name": "ripcord", "version": "1"],
        ]
      ]
    case "ping":
      outcome = ["result": [:]]
    case "tools/list":
      outcome = ["result": ["tools": tools]]
    case "tools/call":
      outcome = call(params, send: send)
    default:
      outcome = ["error": error(-32601, "Method not found: \(method)")]
    }
    return encode(["jsonrpc": "2.0", "id": id].merging(outcome) { $1 })
  }

  private static func call(_ params: [String: Any], send: (ControlRequest) -> ControlResponse)
    -> [String: Any]
  {
    let arguments = params["arguments"] as? [String: Any] ?? [:]
    let request: ControlRequest
    switch params["name"] as? String {
    case "open_panel":
      request = .open(query: arguments["query"] as? String)
    case "pick":
      guard let items = arguments["items"] as? [String] else {
        return toolResult("pick needs items, an array of strings.", isError: true)
      }
      request = .pick(
        items: Control.pickable(items), placeholder: arguments["placeholder"] as? String)
    case "get_config":
      request = .configGet(key: arguments["key"] as? String)
    case "set_config":
      // Null is a value (it clears the key); a value left out is a mistake.
      guard let key = arguments["key"] as? String, let value = arguments["value"],
        let json = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
      else { return toolResult("set_config needs a key and a value.", isError: true) }
      request = .configSet(key: key, json: String(decoding: json, as: UTF8.self))
    case let name:
      return ["error": error(-32602, "Unknown tool: \(name ?? "none")")]
    }
    let response = send(request)
    let text =
      response.error
      ?? (response.cancelled ? "The panel was closed without picking a line." : nil)
      ?? response.output ?? "Done."
    return toolResult(text, isError: response.error != nil || response.cancelled)
  }

  /// A tool's outcome, its failures included, so the model sees them and can try again.
  private static func toolResult(_ text: String, isError: Bool) -> [String: Any] {
    ["result": ["content": [["type": "text", "text": text]], "isError": isError]]
  }

  private static func error(_ code: Int, _ message: String) -> [String: Any] {
    ["code": code, "message": message]
  }

  /// One line: JSONSerialization never breaks lines unless asked to.
  private static func encode(_ object: [String: Any]) -> Data? {
    try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
  }
}
