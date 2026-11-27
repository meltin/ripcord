import Foundation

/// CSS's 148 named colors, for Color Names and the name shown after a pick. Raycast's Color
/// Picker names colors from color-namer's several lists; this is the one browsers know.
public enum ColorNames {
  public static let css: [(name: String, rgb: UInt32)] = [
    ("aliceblue", 0xF0F8FF),
    ("antiquewhite", 0xFAEBD7),
    ("aqua", 0x00FFFF),
    ("aquamarine", 0x7FFFD4),
    ("azure", 0xF0FFFF),
    ("beige", 0xF5F5DC),
    ("bisque", 0xFFE4C4),
    ("black", 0x000000),
    ("blanchedalmond", 0xFFEBCD),
    ("blue", 0x0000FF),
    ("blueviolet", 0x8A2BE2),
    ("brown", 0xA52A2A),
    ("burlywood", 0xDEB887),
    ("cadetblue", 0x5F9EA0),
    ("chartreuse", 0x7FFF00),
    ("chocolate", 0xD2691E),
    ("coral", 0xFF7F50),
    ("cornflowerblue", 0x6495ED),
    ("cornsilk", 0xFFF8DC),
    ("crimson", 0xDC143C),
    ("cyan", 0x00FFFF),
    ("darkblue", 0x00008B),
    ("darkcyan", 0x008B8B),
    ("darkgoldenrod", 0xB8860B),
    ("darkgray", 0xA9A9A9),
    ("darkgreen", 0x006400),
    ("darkgrey", 0xA9A9A9),
    ("darkkhaki", 0xBDB76B),
    ("darkmagenta", 0x8B008B),
    ("darkolivegreen", 0x556B2F),
    ("darkorange", 0xFF8C00),
    ("darkorchid", 0x9932CC),
    ("darkred", 0x8B0000),
    ("darksalmon", 0xE9967A),
    ("darkseagreen", 0x8FBC8F),
    ("darkslateblue", 0x483D8B),
    ("darkslategray", 0x2F4F4F),
    ("darkslategrey", 0x2F4F4F),
    ("darkturquoise", 0x00CED1),
    ("darkviolet", 0x9400D3),
    ("deeppink", 0xFF1493),
    ("deepskyblue", 0x00BFFF),
    ("dimgray", 0x696969),
    ("dimgrey", 0x696969),
    ("dodgerblue", 0x1E90FF),
    ("firebrick", 0xB22222),
    ("floralwhite", 0xFFFAF0),
    ("forestgreen", 0x228B22),
    ("fuchsia", 0xFF00FF),
    ("gainsboro", 0xDCDCDC),
    ("ghostwhite", 0xF8F8FF),
    ("gold", 0xFFD700),
    ("goldenrod", 0xDAA520),
    ("gray", 0x808080),
    ("green", 0x008000),
    ("greenyellow", 0xADFF2F),
    ("grey", 0x808080),
    ("honeydew", 0xF0FFF0),
    ("hotpink", 0xFF69B4),
    ("indianred", 0xCD5C5C),
    ("indigo", 0x4B0082),
    ("ivory", 0xFFFFF0),
    ("khaki", 0xF0E68C),
    ("lavender", 0xE6E6FA),
    ("lavenderblush", 0xFFF0F5),
    ("lawngreen", 0x7CFC00),
    ("lemonchiffon", 0xFFFACD),
    ("lightblue", 0xADD8E6),
    ("lightcoral", 0xF08080),
    ("lightcyan", 0xE0FFFF),
    ("lightgoldenrodyellow", 0xFAFAD2),
    ("lightgray", 0xD3D3D3),
    ("lightgreen", 0x90EE90),
    ("lightgrey", 0xD3D3D3),
    ("lightpink", 0xFFB6C1),
    ("lightsalmon", 0xFFA07A),
    ("lightseagreen", 0x20B2AA),
    ("lightskyblue", 0x87CEFA),
    ("lightslategray", 0x778899),
    ("lightslategrey", 0x778899),
    ("lightsteelblue", 0xB0C4DE),
    ("lightyellow", 0xFFFFE0),
    ("lime", 0x00FF00),
    ("limegreen", 0x32CD32),
    ("linen", 0xFAF0E6),
    ("magenta", 0xFF00FF),
    ("maroon", 0x800000),
    ("mediumaquamarine", 0x66CDAA),
    ("mediumblue", 0x0000CD),
    ("mediumorchid", 0xBA55D3),
    ("mediumpurple", 0x9370DB),
    ("mediumseagreen", 0x3CB371),
    ("mediumslateblue", 0x7B68EE),
    ("mediumspringgreen", 0x00FA9A),
    ("mediumturquoise", 0x48D1CC),
    ("mediumvioletred", 0xC71585),
    ("midnightblue", 0x191970),
    ("mintcream", 0xF5FFFA),
    ("mistyrose", 0xFFE4E1),
    ("moccasin", 0xFFE4B5),
    ("navajowhite", 0xFFDEAD),
    ("navy", 0x000080),
    ("oldlace", 0xFDF5E6),
    ("olive", 0x808000),
    ("olivedrab", 0x6B8E23),
    ("orange", 0xFFA500),
    ("orangered", 0xFF4500),
    ("orchid", 0xDA70D6),
    ("palegoldenrod", 0xEEE8AA),
    ("palegreen", 0x98FB98),
    ("paleturquoise", 0xAFEEEE),
    ("palevioletred", 0xDB7093),
    ("papayawhip", 0xFFEFD5),
    ("peachpuff", 0xFFDAB9),
    ("peru", 0xCD853F),
    ("pink", 0xFFC0CB),
    ("plum", 0xDDA0DD),
    ("powderblue", 0xB0E0E6),
    ("purple", 0x800080),
    ("rebeccapurple", 0x663399),
    ("red", 0xFF0000),
    ("rosybrown", 0xBC8F8F),
    ("royalblue", 0x4169E1),
    ("saddlebrown", 0x8B4513),
    ("salmon", 0xFA8072),
    ("sandybrown", 0xF4A460),
    ("seagreen", 0x2E8B57),
    ("seashell", 0xFFF5EE),
    ("sienna", 0xA0522D),
    ("silver", 0xC0C0C0),
    ("skyblue", 0x87CEEB),
    ("slateblue", 0x6A5ACD),
    ("slategray", 0x708090),
    ("slategrey", 0x708090),
    ("snow", 0xFFFAFA),
    ("springgreen", 0x00FF7F),
    ("steelblue", 0x4682B4),
    ("tan", 0xD2B48C),
    ("teal", 0x008080),
    ("thistle", 0xD8BFD8),
    ("tomato", 0xFF6347),
    ("turquoise", 0x40E0D0),
    ("violet", 0xEE82EE),
    ("wheat", 0xF5DEB3),
    ("white", 0xFFFFFF),
    ("whitesmoke", 0xF5F5F5),
    ("yellow", 0xFFFF00),
    ("yellowgreen", 0x9ACD32),
  ]

  /// The named colors nearest `color`, nearest first, by distance in OKLab, where equal
  /// distances look about equally different. Names spelled two ways (gray and grey) once.
  public static func nearest(to color: PickedColor, count: Int = 25) -> [(
    name: String, hex: String
  )] {
    let target = color.oklab
    var seen = Set<UInt32>()
    return css.filter { seen.insert($0.rgb).inserted }
      .map { entry -> (name: String, hex: String, distance: Double) in
        let named = PickedColor(rgb: entry.rgb)
        let lab = named.oklab
        let distance =
          pow(lab.0 - target.0, 2) + pow(lab.1 - target.1, 2) + pow(lab.2 - target.2, 2)
        return (entry.name, named.hex, distance)
      }
      .sorted { $0.distance < $1.distance }
      .prefix(count)
      .map { ($0.name, $0.hex) }
  }
}

extension Search {
  /// Color Names: the names nearest a color typed as hex (#00ff00), or the names containing
  /// what's typed, all of them alphabetically when nothing is. Return copies the name and ⌘↵
  /// the hex, as Raycast's Color Names does.
  public static func colorNameSections(for query: String) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let named = ColorNames.css
      .filter { trimmed.isEmpty || $0.name.localizedStandardContains(trimmed) }
      .map { ($0.name, PickedColor(rgb: $0.rgb).hex) }
    // Hex with its #, or hex no name contains: "dee" is deeppink before it's #DDEEEE.
    let color = trimmed.hasPrefix("#") || named.isEmpty ? PickedColor(hex: trimmed) : nil
    let names: [(name: String, hex: String)] = color.map { ColorNames.nearest(to: $0) } ?? named
    let results = names.map { entry in
      SearchResult(
        id: "color:\(entry.hex):\(entry.name)", title: entry.name, subtitle: entry.hex,
        keyword: nil, kind: .color, action: .copy(entry.name),
        menu: [
          MenuAction(
            title: "Copy Name", symbol: "doc.on.doc", shortcut: "↵", action: .copy(entry.name)),
          MenuAction(
            title: "Copy Hex", symbol: "doc.on.doc", shortcut: "⌘↵", action: .copy(entry.hex)),
        ])
    }
    return results.isEmpty ? [] : [SearchSection(title: "", results: results)]
  }
}

extension PickedColor {
  /// From `0xRRGGBB`.
  public init(rgb: UInt32) {
    self.init(
      red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255)
  }

  /// `#RGB` or `#RRGGBB`, the # optional; nil for anything else.
  public init?(hex text: String) {
    var digits = text.trimmingCharacters(in: .whitespaces)
    if digits.hasPrefix("#") { digits.removeFirst() }
    if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
    guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16)
    else { return nil }
    self.init(rgb: value)
  }
}

extension PickedColor {
  /// A CSS color as typed or pasted: hex (the # optional), a CSS name, rgb() or rgba(), hsl()
  /// or hsla(), oklch(), or color(srgb …) or color(display-p3 …), with commas or spaces and
  /// `none` as 0. Display P3 outside sRGB is clipped to it. Nil for anything else, and for a
  /// color that isn't opaque, which every format would write as opaque.
  public init?(css text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let named = ColorNames.css.first(where: { $0.name == trimmed }) {
      self.init(rgb: named.rgb)
      return
    }
    if let color = PickedColor(hex: trimmed) {
      self = color
      return
    }
    guard let match = trimmed.wholeMatch(of: /([a-z-]+)\((.*)\)/) else { return nil }
    let halves = String(match.2).split(separator: "/", omittingEmptySubsequences: false)
    var parts = halves[0].split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
    // Alpha after "/", or as a fourth comma-separated argument; only opaque is taken.
    let alpha = halves.count > 1 ? halves[1].trimmingCharacters(in: .whitespaces) : nil
    let isColorFunction = match.1 == "color"
    let fourth = !isColorFunction && parts.count == 4 ? parts.removeLast() : nil
    if let given = alpha ?? fourth, !["1", "100%", "1.0"].contains(given) { return nil }
    func value(_ part: String, percentOf full: Double) -> Double? {
      if part == "none" { return 0 }
      return part.hasSuffix("%") ? Double(part.dropLast()).map { $0 / 100 * full } : Double(part)
    }
    func hue(_ part: String) -> Double? {
      guard
        let degrees = part == "none" ? 0 : Double(part.replacingOccurrences(of: "deg", with: ""))
      else { return nil }
      // -120 is 240.
      return (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(
        dividingBy: 360)
    }
    switch String(match.1) {
    case "rgb", "rgba":
      guard parts.count == 3, let r = value(parts[0], percentOf: 255),
        let g = value(parts[1], percentOf: 255), let b = value(parts[2], percentOf: 255)
      else { return nil }
      self.init(red: r / 255, green: g / 255, blue: b / 255)
    case "hsl", "hsla":
      // Saturation and lightness as percentages, with or without the %.
      guard parts.count == 3, let h = hue(parts[0]),
        let s = value(parts[1].replacingOccurrences(of: "%", with: ""), percentOf: 1),
        let l = value(parts[2].replacingOccurrences(of: "%", with: ""), percentOf: 1)
      else { return nil }
      let (saturation, lightness) = (s / 100, l / 100)
      // CSS's hsl() to sRGB.
      func channel(_ n: Double) -> Double {
        let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
        let a = saturation * min(lightness, 1 - lightness)
        return lightness - a * max(-1, min(k - 3, 9 - k, 1))
      }
      self.init(red: channel(0), green: channel(8), blue: channel(4))
    case "oklch":
      guard parts.count == 3, let l = value(parts[0], percentOf: 1),
        let c = value(parts[1], percentOf: 0.4), let h = hue(parts[2])
      else { return nil }
      let (a, b) = (c * cos(h * .pi / 180), c * sin(h * .pi / 180))
      // Björn Ottosson's OKLab back to linear sRGB.
      let lms = [
        l + 0.3963377774 * a + 0.2158037573 * b, l - 0.1055613458 * a - 0.0638541728 * b,
        l - 0.0894841775 * a - 1.2914855480 * b,
      ].map { $0 * $0 * $0 }
      self.init(
        linear: [
          4.0767416621 * lms[0] - 3.3077115913 * lms[1] + 0.2309699292 * lms[2],
          -1.2684380046 * lms[0] + 2.6097574011 * lms[1] - 0.3413193965 * lms[2],
          -0.0041960863 * lms[0] - 0.7034186147 * lms[1] + 1.7076147010 * lms[2],
        ])
    case "color":
      guard parts.count == 4, parts[0] == "display-p3" || parts[0] == "srgb",
        let r = value(parts[1], percentOf: 1), let g = value(parts[2], percentOf: 1),
        let b = value(parts[3], percentOf: 1)
      else { return nil }
      guard parts[0] == "display-p3" else {
        self.init(red: r, green: g, blue: b)
        return
      }
      // Display P3 to XYZ to linear sRGB.
      let p3 = [r, g, b].map { c in c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
      let x = 0.4865709486482162 * p3[0] + 0.26566769316909306 * p3[1] + 0.1982172852343625 * p3[2]
      let y = 0.2289745640697488 * p3[0] + 0.6917385218365064 * p3[1] + 0.079286914093745 * p3[2]
      let z = 0.04511338185890264 * p3[1] + 1.043944368900976 * p3[2]
      self.init(
        linear: [
          3.2409699419045226 * x - 1.537383177570094 * y - 0.4986107602930034 * z,
          -0.9692436362808796 * x + 1.8759675015077202 * y + 0.04155505740717559 * z,
          0.05563007969699366 * x - 0.20397695888897652 * y + 1.0569715142428786 * z,
        ])
    default:
      return nil
    }
  }

  /// From linear-light sRGB, clipped to sRGB.
  init(linear: [Double]) {
    let encoded = linear.map { c in
      let c = min(max(c, 0), 1)
      return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
    self.init(red: encoded[0], green: encoded[1], blue: encoded[2])
  }
}

extension Search {
  /// Convert Color: the color typed in every format, the one copied last first, as Raycast's
  /// Convert Color lists them; nothing until what's typed is a color.
  public static func convertColorSections(for query: String, lastFormat: ColorFormat?)
    -> [SearchSection]
  {
    guard let color = PickedColor(css: query) else { return [] }
    let formats = [lastFormat].compactMap { $0 } + ColorFormat.allCases.filter { $0 != lastFormat }
    let results = formats.map { format in
      let converted = format.string(for: color)
      return SearchResult(
        // The color's swatch for its icon, as Color History's rows have.
        id: "color:\(color.hex):convert:\(format.rawValue)", title: format.title,
        subtitle: converted, keyword: nil, kind: .color, action: .copy(converted),
        menu: [
          MenuAction(
            title: "Copy Converted Color", symbol: "doc.on.doc", shortcut: "↵",
            action: .copy(converted))
        ])
    }
    return [SearchSection(title: "", results: results)]
  }
}
