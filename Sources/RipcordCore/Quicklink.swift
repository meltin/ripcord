import Foundation

/// A named URL; `{query}` in `url` is replaced by what follows `keyword` in the search field.
public struct Quicklink: Codable, Equatable, Sendable {
  public var name: String
  public var url: String
  public var keyword: String?

  public init(name: String, url: String, keyword: String? = nil) {
    self.name = name
    self.url = url
    self.keyword = keyword
  }

  public func url(for argument: String) -> URL? {
    // Only RFC 3986 unreserved characters pass, so "&", "#" and "+" can't break the query.
    let unreserved = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    let encoded = argument.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    return URL(string: url.replacingOccurrences(of: "{query}", with: encoded))
  }
}
