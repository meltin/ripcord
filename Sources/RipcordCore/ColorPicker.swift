import Foundation

/// A color picked from the screen, in sRGB with components from 0 to 1.
public struct PickedColor: Codable, Equatable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var pickedAt: Date

  public init(red: Double, green: Double, blue: Double, pickedAt: Date = .now) {
    self.red = red
    self.green = green
    self.blue = blue
    self.pickedAt = pickedAt
  }

  /// `#RRGGBB`, which also tells two picks of the same color apart from different ones.
  public var hex: String {
    "#" + [red, green, blue].map { String(format: "%02X", Self.byte($0)) }.joined()
  }

  /// A component as 0–255, rounded and kept in range.
  static func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }

  /// Hue in degrees, saturation and lightness in percent, rounded.
  var hsl: (hue: Int, saturation: Int, lightness: Int) {
    let (r, g, b) = (min(max(red, 0), 1), min(max(green, 0), 1), min(max(blue, 0), 1))
    let high = max(r, g, b)
    let low = min(r, g, b)
    let lightness = (high + low) / 2
    let delta = high - low
    guard delta > 0 else { return (0, 0, Int((lightness * 100).rounded())) }
    let saturation = delta / (1 - abs(2 * lightness - 1))
    let sector: Double =
      switch high {
      case r: ((g - b) / delta).truncatingRemainder(dividingBy: 6)
      case g: (b - r) / delta + 2
      default: (r - g) / delta + 4
      }
    let hue = (sector * 60 + 360).truncatingRemainder(dividingBy: 360)
    return (
      Int(hue.rounded()) % 360, Int((saturation * 100).rounded()), Int((lightness * 100).rounded())
    )
  }
}

/// The ways a picked color is copied, as Raycast's Color Picker offers them.
public enum ColorFormat: String, Codable, CaseIterable, Sendable {
  case hex, rgb, hsl
  case swiftUI = "swiftui"
  case nsColor = "nscolor"

  public var title: String {
    switch self {
    case .hex: "HEX"
    case .rgb: "RGB"
    case .hsl: "HSL"
    case .swiftUI: "SwiftUI"
    case .nsColor: "NSColor"
    }
  }

  public func string(for color: PickedColor) -> String {
    let components = [color.red, color.green, color.blue]
    // Three decimals, without trailing zeros, for code.
    let code = components.map {
      String(format: "%.3f", min(max($0, 0), 1))
        .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
    switch self {
    case .hex: return color.hex
    case .rgb:
      let bytes = components.map(PickedColor.byte)
      return "rgb(\(bytes[0]), \(bytes[1]), \(bytes[2]))"
    case .hsl:
      let (hue, saturation, lightness) = color.hsl
      return "hsl(\(hue), \(saturation)%, \(lightness)%)"
    case .swiftUI:
      return "Color(red: \(code[0]), green: \(code[1]), blue: \(code[2]))"
    case .nsColor:
      return "NSColor(srgbRed: \(code[0]), green: \(code[1]), blue: \(code[2]), alpha: 1)"
    }
  }
}

/// The colors picked, newest first, kept in `colors.json`.
public struct ColorHistory: Sendable {
  public private(set) var colors: [PickedColor] = []
  public let fileURL: URL
  /// Older picks beyond this are dropped.
  public static let limit = 100

  /// Reads `fileURL`, or starts empty. A file that can't be read is moved aside rather than
  /// overwritten by the next pick, as Clipboard History does.
  public init(fileURL: URL) {
    self.fileURL = fileURL
    guard let data = try? Data(contentsOf: fileURL) else { return }
    do {
      colors = try JSONDecoder().decode([PickedColor].self, from: data)
    } catch {
      try? FileManager.default.moveItem(
        at: fileURL,
        to: fileURL.deletingLastPathComponent().appending(
          path: "colors-unreadable-\(UUID().uuidString).json"))
    }
  }

  /// Puts `color` first; picking the same color again moves it up instead of listing it twice.
  public mutating func add(_ color: PickedColor) throws {
    try save(Array(([color] + colors.filter { $0.hex != color.hex }).prefix(Self.limit)))
  }

  public mutating func delete(hex: String) throws {
    try save(colors.filter { $0.hex != hex })
  }

  /// Writes `new`, and only then shows it, so the list never differs from the file.
  private mutating func save(_ new: [PickedColor]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(new).write(to: fileURL, options: .atomic)
    colors = new
  }

}

extension Search {
  /// Picked colors, newest first: a query matches any of their formats.
  public static func colorSections(
    for query: String, history: ColorHistory, format: ColorFormat
  ) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    // HEX, RGB and HSL only: the code formats' labels ("red:", "Color") would match every color.
    let searched: [ColorFormat] = [.hex, .rgb, .hsl]
    let results = history.colors.filter { color in
      trimmed.isEmpty
        || searched.contains { $0.string(for: color).localizedStandardContains(trimmed) }
    }
    .map { color in
      // The default format first, on Return; the others after it.
      let copies = ([format] + ColorFormat.allCases.filter { $0 != format }).enumerated().map {
        index, each in
        MenuAction(
          title: "Copy \(each.title)", symbol: "doc.on.doc", shortcut: index == 0 ? "↵" : "",
          action: .copy(each.string(for: color)))
      }
      let menu =
        copies + [
          MenuAction(
            title: "Delete Color", symbol: "trash", shortcut: "⌃X",
            action: .deleteColor(color.hex), isDestructive: true, startsSection: true)
        ]
      return SearchResult(
        id: "color:\(color.hex)", title: format.string(for: color),
        subtitle: format == .hex ? ColorFormat.rgb.string(for: color) : color.hex, keyword: nil,
        kind: .color, action: menu[0].action, menu: menu)
    }
    return results.isEmpty ? [] : [SearchSection(title: "", results: results)]
  }
}
