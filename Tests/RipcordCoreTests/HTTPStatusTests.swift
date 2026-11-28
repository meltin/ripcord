import Foundation
import Testing

@testable import RipcordCore

@Suite struct HTTPStatusTests {
  @Test func listsEveryCodeOnceAndInOrder() {
    let codes = HTTPStatus.all.map(\.code)
    #expect(codes == codes.sorted())
    #expect(Set(codes).count == codes.count)
    #expect(codes.contains(404) && codes.contains(418) && codes.contains(511))
  }

  @Test func groupsByHundredAsRaycastDoes() {
    let sections = Search.httpStatusSections(for: "")
    #expect(
      sections.map(\.title) == [
        "1xx Informational", "2xx Success", "3xx Redirection", "4xx Client Error",
        "5xx Server Error",
      ])
    #expect(sections.flatMap(\.results).count == HTTPStatus.all.count)
  }

  @Test func digitsMatchFromTheStartOfTheCode() {
    let titles = Search.httpStatusSections(for: "40").flatMap(\.results).map(\.title)
    #expect(titles.first == "400 Bad Request")
    #expect(titles.allSatisfy { $0.hasPrefix("40") })
    #expect(
      Search.httpStatusSections(for: "404").flatMap(\.results).map(\.title) == ["404 Not Found"])
  }

  @Test func wordsMatchTheName() {
    let titles = Search.httpStatusSections(for: "not found").flatMap(\.results).map(\.title)
    #expect(titles.contains("404 Not Found"))
    #expect(
      Search.httpStatusSections(for: "teapot").flatMap(\.results).map(\.title) == [
        "418 I'm a teapot"
      ])
    #expect(Search.httpStatusSections(for: "zzzz").isEmpty)
  }

  @Test func listsTheBestMatchFirst() {
    func titles(_ query: String) -> [String] {
      Search.httpStatusSections(for: query).flatMap(\.results).map(\.title)
    }
    #expect(titles("not").prefix(3) == ["304 Not Modified", "404 Not Found", "406 Not Acceptable"])
    #expect(titles("auth").first == "407 Proxy Authentication Required")
    #expect(!titles("time").contains("501 Not Implemented"))
    // Full-width digits, and the hundreds' headings.
    #expect(titles("４０４") == ["404 Not Found"])
    #expect(titles("4xx").count == HTTPStatus.all.filter { $0.code / 100 == 4 }.count)
    #expect(titles("redirection").allSatisfy { $0.hasPrefix("3") })
  }

  @Test func opensMDNAndCopiesTheCodeOrName() throws {
    let row = try #require(Search.httpStatusSections(for: "404").first?.results.first)
    #expect(
      row.action
        == .open(
          URL(string: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/404")!))
    #expect(row.actions.map(\.title) == ["Open in Browser", "Copy Code", "Copy Name"])
    // Copy Code on ⌘↵, as Raycast's.
    #expect(row.actions.map(\.shortcut) == ["↵", "⌘↵", "⌥⌘C"])
    #expect(row.actions.map(\.action).dropFirst() == [.copy("404"), .copy("Not Found")])
    #expect(row.subtitle == "The server can't find the resource.")
  }

  /// Raycast's cat or dog person: none by default, http.cat's or http.dog's JPEG otherwise.
  @Test func picksACatOrDogPicture() throws {
    let config = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"cmd+space"}"#.utf8))
    #expect(config.httpStatusPicture == .none)
    #expect(HTTPStatusPicture.none.url(for: 404) == nil)
    #expect(HTTPStatusPicture.cat.url(for: 404)?.absoluteString == "https://http.cat/404.jpg")
    #expect(HTTPStatusPicture.dog.url(for: 418)?.absoluteString == "https://http.dog/418.jpg")
  }
}
