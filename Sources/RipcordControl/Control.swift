import Foundation

/// What the `ripcord` command asks the running app over its socket, one JSON line each way.
/// It can only do what the same user could already do by hand: show the panel with a query,
/// ask them to pick a line, and read or write the config file.
public enum ControlRequest: Codable, Equatable, Sendable {
  case open(query: String?)
  case pick(items: [String], placeholder: String?)
  case configGet(key: String?)
  case configSet(key: String, json: String)
}

public struct ControlResponse: Codable, Equatable, Sendable {
  /// What to print on stdout.
  public var output: String?
  /// What went wrong, for stderr.
  public var error: String?
  /// A pick left without choosing, as Esc does.
  public var cancelled: Bool

  public init(output: String? = nil, error: String? = nil, cancelled: Bool = false) {
    self.output = output
    self.error = error
    self.cancelled = cancelled
  }

  /// 0 done, 1 a pick cancelled, 2 an error, as the README lists.
  public var exitCode: Int32 { error != nil ? 2 : cancelled ? 1 : 0 }
}

public enum Control {
  /// The socket, in this user's own temporary folder: read from the system rather than
  /// `TMPDIR`, which a Nix shell or ssh session may change, so the command always finds the app.
  public static var socketPath: String {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
    let folder =
      length > 0
      ? String(decoding: buffer.prefix(length - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
      : NSTemporaryDirectory()
    return (folder as NSString).appendingPathComponent("ripcord.sock")
  }

  /// The most a pick takes, so a runaway pipe can't fill the panel or the app's memory.
  public static let maxPickItems = 10_000

  public static let usage = """
    usage: ripcord open [--query TEXT]
           ripcord pick [--placeholder TEXT] < lines
           ripcord config get [KEY]
           ripcord config set KEY JSON
    """

  /// The request `arguments` (without the command's own name) ask for; `stdin` gives a pick's
  /// lines. Nil with a usage error when they don't parse.
  public static func request(
    from arguments: [String], stdin: () -> String = { "" }
  ) -> Result<ControlRequest, UsageError> {
    switch arguments.first {
    case "open":
      let rest = Array(arguments.dropFirst())
      if rest.isEmpty { return .success(.open(query: nil)) }
      guard rest.count == 2, rest[0] == "--query" else { return .failure(UsageError()) }
      return .success(.open(query: rest[1]))
    case "pick":
      let rest = Array(arguments.dropFirst())
      let placeholder: String?
      if rest.isEmpty {
        placeholder = nil
      } else if rest.count == 2, rest[0] == "--placeholder" {
        placeholder = rest[1]
      } else {
        return .failure(UsageError())
      }
      let items = stdin().split(separator: "\n", omittingEmptySubsequences: true)
        .prefix(maxPickItems).map(String.init)
      return .success(.pick(items: items, placeholder: placeholder))
    case "config":
      let rest = Array(arguments.dropFirst())
      switch (rest.first, rest.count) {
      case ("get", 1): return .success(.configGet(key: nil))
      case ("get", 2): return .success(.configGet(key: rest[1]))
      case ("set", 3): return .success(.configSet(key: rest[1], json: rest[2]))
      default: return .failure(UsageError())
      }
    default:
      return .failure(UsageError())
    }
  }

  public struct UsageError: Error, Equatable {}
}
