import Foundation

/// `ripcord config get` and `set`: the config file read whole or by one top-level key, and one
/// key replaced, refused unless the result reads back as a config with that very value.
extension Config {
  public struct EditError: LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }
  }

  /// The keys a config file can have: its properties' names, those left out by default too.
  public static var keys: Set<String> {
    Set(Mirror(reflecting: Config.default).children.compactMap(\.label))
  }

  /// The whole file's text, or one top-level key's value as JSON: the one Ripcord uses, its
  /// default when the file leaves it out.
  public static func get(_ key: String?, from data: Data) throws -> String {
    guard let key else { return String(decoding: data, as: UTF8.self) }
    guard keys.contains(key) else { throw EditError(message: "“\(key)” isn't a config key.") }
    guard let config = try? JSONDecoder().decode(Config.self, from: data),
      let object = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(config))
        as? [String: Any]
    else { throw EditError(message: "The config file can't be read.") }
    // A key with no value, as `inputSource` until one is picked, is null.
    let value = object[key] ?? NSNull()
    let encoded = try JSONSerialization.data(
      withJSONObject: value, options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys])
    return String(decoding: encoded, as: UTF8.self)
  }

  /// The config `data` holds with `key` set to the JSON value `json`.
  public static func setting(_ key: String, to json: String, in data: Data) throws -> Config {
    guard keys.contains(key) else {
      throw EditError(message: "“\(key)” isn't a config key.")
    }
    guard
      let value = try? JSONSerialization.jsonObject(
        with: Data(json.utf8), options: .fragmentsAllowed)
    else { throw EditError(message: "The value isn't JSON: \(json)") }
    guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw EditError(message: "The config file isn't a JSON object.")
    }
    object[key] = value
    let refused = EditError(
      message: "“\(key)” can't be \(json). Give its whole value, as config get \(key) prints it.")
    guard
      let config = try? JSONDecoder().decode(
        Config.self, from: JSONSerialization.data(withJSONObject: object))
    else { throw refused }
    // A value read leniently (an unknown color format reads as hex, a missing field as its
    // default) mustn't be saved as something else: it has to come back as given. Null clears a
    // key that can be left out.
    guard let written = try? JSONEncoder().encode(config),
      let back = try? JSONSerialization.jsonObject(with: written) as? [String: Any],
      NSDictionary(dictionary: [key: back[key] ?? NSNull()]).isEqual(to: [key: value])
    else { throw refused }
    return config
  }
}
