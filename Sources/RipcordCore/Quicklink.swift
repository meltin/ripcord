import Foundation

/// A named URL; `{query}` in `url` is replaced by what follows `keyword` in the search field.
/// The keyword doubles as its alias, and the link keeps its own hotkey and on/off switch, so a
/// rename never strands them.
public struct Quicklink: Codable, Equatable, Sendable {
  public var name: String
  public var url: String
  public var keyword: String?
  public var hotkey: String?
  /// Stored only when true, so untouched links stay as short as before.
  public var disabled: Bool?

  public init(
    name: String, url: String, keyword: String? = nil, hotkey: String? = nil,
    disabled: Bool? = nil
  ) {
    self.name = name
    self.url = url
    self.keyword = keyword
    self.hotkey = hotkey
    self.disabled = disabled
  }

  public var isEnabled: Bool {
    get { disabled != true }
    set { disabled = newValue ? nil : true }
  }

  public func url(for argument: String) -> URL? {
    // Only RFC 3986 unreserved characters pass, so "&", "#" and "+" can't break the query.
    let unreserved = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    let encoded = argument.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    return URL(string: url.replacingOccurrences(of: "{query}", with: encoded))
  }
}
