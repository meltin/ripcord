import Foundation

/// One HTTP status code, for the HTTP Status Codes list.
public struct HTTPStatus: Equatable, Sendable {
  public let code: Int
  public let name: String
  /// A line on what it means.
  public let summary: String

  /// Its page on MDN.
  public var page: URL? {
    URL(string: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/\(code)")
  }

  /// The heading its hundred is listed under.
  public var group: String {
    switch code / 100 {
    case 1: "1xx Informational"
    case 2: "2xx Success"
    case 3: "3xx Redirection"
    case 4: "4xx Client Error"
    default: "5xx Server Error"
    }
  }

  /// The codes in RFC 9110 and the other RFCs MDN lists, in order.
  public static let all: [HTTPStatus] = [
    .init(100, "Continue", "The request's start was fine; send the rest."),
    .init(101, "Switching Protocols", "The server is switching to the protocol asked for."),
    .init(102, "Processing", "Received and being worked on; no response yet."),
    .init(103, "Early Hints", "Headers to preload with while the response is prepared."),
    .init(200, "OK", "The request succeeded."),
    .init(201, "Created", "The request succeeded and made a new resource."),
    .init(202, "Accepted", "Received, but not acted on yet."),
    .init(203, "Non-Authoritative Information", "Succeeded, with metadata from a copy."),
    .init(204, "No Content", "Succeeded, with nothing to send back."),
    .init(205, "Reset Content", "Succeeded; reset the document that sent it."),
    .init(206, "Partial Content", "Here is the range of the resource asked for."),
    .init(207, "Multi-Status", "Statuses for several resources (WebDAV)."),
    .init(208, "Already Reported", "Members listed earlier in this response (WebDAV)."),
    .init(226, "IM Used", "The response is the result of instance manipulations."),
    .init(300, "Multiple Choices", "There is more than one possible response."),
    .init(301, "Moved Permanently", "The resource has a new URL for good."),
    .init(302, "Found", "The resource is at another URL for now."),
    .init(303, "See Other", "Get the result from another URL with GET."),
    .init(304, "Not Modified", "The cached copy is still current."),
    .init(307, "Temporary Redirect", "Repeat the request at another URL, same method."),
    .init(308, "Permanent Redirect", "Use the other URL from now on, same method."),
    .init(400, "Bad Request", "The server can't read the request."),
    .init(401, "Unauthorized", "Authentication is needed."),
    .init(402, "Payment Required", "Reserved for payment systems."),
    .init(403, "Forbidden", "Known, but not allowed to see this."),
    .init(404, "Not Found", "The server can't find the resource."),
    .init(405, "Method Not Allowed", "The resource doesn't take this method."),
    .init(406, "Not Acceptable", "Nothing matches the Accept headers sent."),
    .init(407, "Proxy Authentication Required", "Authentication is needed by a proxy."),
    .init(408, "Request Timeout", "The server gave up waiting for the request."),
    .init(409, "Conflict", "The request conflicts with the resource's state."),
    .init(410, "Gone", "The resource is gone for good."),
    .init(411, "Length Required", "A Content-Length header is needed."),
    .init(412, "Precondition Failed", "A condition in the headers wasn't met."),
    .init(413, "Content Too Large", "The request body is bigger than allowed."),
    .init(414, "URI Too Long", "The URL is longer than the server takes."),
    .init(415, "Unsupported Media Type", "The body's format isn't supported."),
    .init(416, "Range Not Satisfiable", "The range asked for is out of bounds."),
    .init(417, "Expectation Failed", "The Expect header can't be met."),
    .init(418, "I'm a teapot", "The server refuses to brew coffee with a teapot."),
    .init(421, "Misdirected Request", "This server can't answer for that URL."),
    .init(422, "Unprocessable Content", "Well formed, but its content is wrong."),
    .init(423, "Locked", "The resource is locked (WebDAV)."),
    .init(424, "Failed Dependency", "An earlier request it relied on failed (WebDAV)."),
    .init(425, "Too Early", "Won't risk processing a request that might be replayed."),
    .init(426, "Upgrade Required", "Switch to another protocol first."),
    .init(428, "Precondition Required", "The request must be conditional."),
    .init(429, "Too Many Requests", "Too many requests in too short a time."),
    .init(431, "Request Header Fields Too Large", "The headers are too large."),
    .init(451, "Unavailable For Legal Reasons", "Blocked for legal reasons."),
    .init(500, "Internal Server Error", "The server hit a problem it can't handle."),
    .init(501, "Not Implemented", "The server doesn't support this method."),
    .init(502, "Bad Gateway", "A gateway got a bad response from upstream."),
    .init(503, "Service Unavailable", "The server isn't ready, often down or overloaded."),
    .init(504, "Gateway Timeout", "A gateway didn't get a response in time."),
    .init(505, "HTTP Version Not Supported", "The HTTP version isn't supported."),
    .init(506, "Variant Also Negotiates", "Content negotiation went in a circle."),
    .init(507, "Insufficient Storage", "No room to store what's needed (WebDAV)."),
    .init(508, "Loop Detected", "An infinite loop while processing (WebDAV)."),
    .init(510, "Not Extended", "Further extensions to the request are needed."),
    .init(511, "Network Authentication Required", "Sign in to the network first."),
  ]

  private init(_ code: Int, _ name: String, _ summary: String) {
    self.code = code
    self.name = name
    self.summary = summary
  }
}

extension Search {
  /// The codes by hundred, as Raycast lists them: digits match from the start of the code,
  /// anything else the name.
  public static func httpStatusSections(for query: String) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let matches = HTTPStatus.all.filter { status in
      guard !trimmed.isEmpty else { return true }
      if trimmed.allSatisfy(\.isNumber) { return String(status.code).hasPrefix(trimmed) }
      return Fuzzy.score(trimmed, in: status.name) != nil
        || "\(status.code) \(status.name)".localizedStandardContains(trimmed)
    }
    let groups = Dictionary(grouping: matches, by: \.group)
    return groups.keys.sorted().map { group in
      SearchSection(title: group, results: (groups[group] ?? []).map(result(for:)))
    }
  }

  private static func result(for status: HTTPStatus) -> SearchResult {
    let code = String(status.code)
    let open = status.page.map {
      MenuAction(title: "Open in Browser", symbol: "safari", shortcut: "↵", action: .open($0))
    }
    let menu =
      [open].compactMap { $0 } + [
        MenuAction(title: "Copy Code", symbol: "number", shortcut: "⇧⌘C", action: .copy(code)),
        MenuAction(
          title: "Copy Name", symbol: "doc.on.doc", shortcut: "⌥⌘C", action: .copy(status.name)),
      ]
    return SearchResult(
      id: "http:\(code)", title: "\(code) \(status.name)", subtitle: status.summary,
      keyword: nil, kind: .statusCode, action: menu[0].action, menu: menu)
  }
}
