import Foundation

/// A color picked from the screen, in sRGB with components from 0 to 1.
public struct PickedColor: Codable, Equatable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var pickedAt: Date
  /// In Favorite Colors; optional, so colors.json from before favorites still reads.
  public var isFavorite: Bool?

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

/// The ways a picked color is copied: Raycast's Color Picker's formats, written as its colorjs.io
/// writes them, then Ripcord's own HSL and code ones.
public enum ColorFormat: String, Codable, CaseIterable, Sendable {
  case hex
  case hexLowerCase = "hex-lower-case"
  case hexNoPrefix = "hex-no-prefix"
  case rgb
  case rgbPercentage = "rgb-percentage"
  case rgba
  case rgbaPercentage = "rgba-percentage"
  case hsla, hsva, oklch, lch, p3
  case hsl
  case swiftUI = "swiftui"
  case nsColor = "nscolor"

  public var title: String {
    switch self {
    case .hex: "HEX"
    case .hexLowerCase: "HEX Lower Case"
    case .hexNoPrefix: "HEX No Prefix"
    case .rgb: "RGB"
    case .rgbPercentage: "RGB %"
    case .rgba: "RGBA"
    case .rgbaPercentage: "RGBA %"
    case .hsla: "HSLA"
    case .hsva: "HSVA"
    case .oklch: "OKLCH"
    case .lch: "LCH"
    case .p3: "P3"
    case .hsl: "HSL"
    case .swiftUI: "SwiftUI"
    case .nsColor: "NSColor"
    }
  }

  public func string(for color: PickedColor) -> String {
    let components = [color.red, color.green, color.blue].map { min(max($0, 0), 1) }
    // As colorjs.io 0.7.1 writes them, which Raycast's Color Picker calls: five significant
    // digits, percentages for <percentage> channels, and alpha only where the format asks.
    let numbers = components.map { Self.serialize($0 * 255) }
    let percents = components.map { Self.serialize($0 * 100) + "%" }
    // Three decimals, without trailing zeros, for code.
    let code = components.map { Self.number($0, places: 3) }
    switch self {
    case .hex: return Self.collapsedHex(color).uppercased()
    case .hexLowerCase: return Self.collapsedHex(color).lowercased()
    // Raycast drops the # from colorjs.io's lower case, so this one stays lower case.
    case .hexNoPrefix: return String(Self.collapsedHex(color).lowercased().dropFirst())
    case .rgb: return "rgb(\(numbers.joined(separator: ", ")))"
    case .rgbPercentage: return "rgb(\(percents.joined(separator: " ")))"
    case .rgba: return "rgba(\(numbers.joined(separator: ", ")))"
    case .rgbaPercentage: return "rgba(\(percents.joined(separator: ", ")), 1)"
    case .hsla:
      let (hue, saturation, lightness) = color.hslPrecise
      return
        "hsla(\(hue.map(Self.serialize) ?? "none"), \(Self.serialize(saturation))%, \(Self.serialize(lightness))%, 1)"
    case .hsva:
      let (hue, saturation, value) = color.hsv
      return
        "color(hsv \(hue.map(Self.serialize) ?? "none") \(Self.serialize(saturation)) \(Self.serialize(value)))"
    case .oklch:
      let (lightness, chroma, hue) = color.oklch
      return
        "oklch(\(Self.serialize(lightness * 100))% \(Self.serialize(chroma)) \(hue.map(Self.serialize) ?? "none"))"
    case .lch:
      // Raycast writes this one itself: lightness to two places, the rest unrounded.
      let (lightness, chroma, hue) = color.lch
      return
        "lch(\(String(format: "%.2f", lightness))% \(Self.unrounded(chroma)) \(hue.map(Self.unrounded) ?? "none"))"
    case .p3:
      return "color(display-p3 \(color.displayP3.map(Self.serialize).joined(separator: " ")))"
    case .hsl:
      let (hue, saturation, lightness) = color.hsl
      return "hsl(\(hue), \(saturation)%, \(lightness)%)"
    case .swiftUI:
      return "Color(red: \(code[0]), green: \(code[1]), blue: \(code[2]))"
    case .nsColor:
      return "NSColor(srgbRed: \(code[0]), green: \(code[1]), blue: \(code[2]), alpha: 1)"
    }
  }

  /// `#RRGGBB`, or `#RGB` when each pair repeats a digit, as colorjs.io collapses it.
  private static func collapsedHex(_ color: PickedColor) -> String {
    let bytes = [color.red, color.green, color.blue].map(PickedColor.byte)
    guard bytes.allSatisfy({ $0 % 17 == 0 }) else { return color.hex }
    return "#" + bytes.map { String($0 / 17, radix: 16) }.joined()
  }

  /// colorjs.io's toPrecision with its default of five significant digits, written as
  /// JavaScript writes the number.
  static func serialize(_ value: Double) -> String {
    guard value != 0 else { return "0" }
    let integer = Int(value)
    let digits = integer == 0 ? 0 : Int(log10(Double(abs(integer)))) + 1
    let multiplier = pow(10.0, Double(5 - digits))
    return unrounded((value * multiplier + 0.5).rounded(.down) / multiplier)
  }

  /// As JavaScript writes a number: no ".0" on whole ones.
  static func unrounded(_ value: Double) -> String {
    value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : "\(value)"
  }

  /// `value` to at most `places` decimals, without trailing zeros.
  static func number(_ value: Double, places: Int) -> String {
    let text = String(format: "%.\(places)f", value)
      .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    return text == "-0" ? "0" : text
  }
}

extension PickedColor {
  /// The components without sRGB's gamma.
  private var linear: [Double] {
    [red, green, blue].map { component in
      let c = min(max(component, 0), 1)
      return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
  }

  /// Hue in degrees, nil for a grey, as colorjs.io leaves it; saturation and value in percent.
  var hsv: (hue: Double?, saturation: Double, value: Double) {
    let (r, g, b) = (min(max(red, 0), 1), min(max(green, 0), 1), min(max(blue, 0), 1))
    let high = max(r, g, b)
    let delta = high - min(r, g, b)
    guard delta > 1e-7 else { return (nil, 0, high * 100) }
    let sector: Double =
      switch high {
      case r: ((g - b) / delta).truncatingRemainder(dividingBy: 6)
      case g: (b - r) / delta + 2
      default: (r - g) / delta + 4
      }
    return (
      (sector * 60 + 360).truncatingRemainder(dividingBy: 360), delta / high * 100, high * 100
    )
  }

  /// Björn Ottosson's OKLab: lightness 0–1 and the a and b axes.
  var oklab: (Double, Double, Double) {
    let (r, g, b) = (linear[0], linear[1], linear[2])
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return (
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    )
  }

  /// OKLab as lightness 0–1, chroma and hue in degrees; no hue, and no chroma, for a grey, as
  /// colorjs.io decides it.
  public var oklch: (lightness: Double, chroma: Double, hue: Double?) {
    let (lightness, a, b) = oklab
    guard abs(a) >= 0.8e-5 || abs(b) >= 0.8e-5 else { return (lightness, 0, nil) }
    return (lightness, hypot(a, b), Self.degrees(atan2(b, a)))
  }

  /// HSL unrounded: hue in degrees, nil for a grey, saturation and lightness in percent.
  var hslPrecise: (hue: Double?, saturation: Double, lightness: Double) {
    let (r, g, b) = (min(max(red, 0), 1), min(max(green, 0), 1), min(max(blue, 0), 1))
    let high = max(r, g, b)
    let low = min(r, g, b)
    let lightness = (high + low) / 2
    let delta = high - low
    guard delta > 1e-7 else { return (nil, 0, lightness * 100) }
    let saturation = delta / (1 - abs(2 * lightness - 1))
    return (hsv.hue, saturation * 100, lightness * 100)
  }

  /// CIE LCH under D50, as CSS's lch() is: lightness 0–100, chroma, hue in degrees.
  var lch: (lightness: Double, chroma: Double, hue: Double?) {
    let (r, g, b) = (linear[0], linear[1], linear[2])
    // sRGB to XYZ (D65), then Bradford to D50.
    let x65 = 0.4123907992659595 * r + 0.357584339383878 * g + 0.1804807884018343 * b
    let y65 = 0.21263900587151036 * r + 0.715168678767756 * g + 0.07219231536073371 * b
    let z65 = 0.01933081871559185 * r + 0.11919477979462598 * g + 0.9505321522496606 * b
    let x = 1.0479298208405488 * x65 + 0.022946793341019088 * y65 - 0.05019222954313557 * z65
    let y = 0.029627815688159344 * x65 + 0.990434484573249 * y65 - 0.01707382502938514 * z65
    let z = -0.009243058152591178 * x65 + 0.015055144896577895 * y65 + 0.7518742899580008 * z65
    func f(_ t: Double) -> Double {
      t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116
    }
    let (fx, fy, fz) = (f(x / 0.9642956764295677), f(y), f(z / 0.8251046025104602))
    let (a, bb) = (500 * (fx - fy), 200 * (fy - fz))
    // colorjs.io's grey: both axes within 250 / 100,000 of zero.
    guard abs(a) >= 0.0025 || abs(bb) >= 0.0025 else { return (116 * fy - 16, 0, nil) }
    return (116 * fy - 16, hypot(a, bb), Self.degrees(atan2(bb, a)))
  }

  /// The same color in Display P3, gamma and all.
  var displayP3: [Double] {
    let (r, g, b) = (linear[0], linear[1], linear[2])
    let x = 0.4123907992659595 * r + 0.357584339383878 * g + 0.1804807884018343 * b
    let y = 0.21263900587151036 * r + 0.715168678767756 * g + 0.07219231536073371 * b
    let z = 0.01933081871559185 * r + 0.11919477979462598 * g + 0.9505321522496606 * b
    return [
      2.493496911941425 * x - 0.9313836179191239 * y - 0.40271078445071684 * z,
      -0.8294889695615747 * x + 1.7626640603183463 * y + 0.023624685841943577 * z,
      0.03584583024378447 * x - 0.07617238926804182 * y + 0.9568845240076872 * z,
    ].map { c in
      let c = min(max(c, 0), 1)
      return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
  }

  private static func degrees(_ radians: Double) -> Double {
    (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
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

  /// Puts `color` first; picking the same color again moves it up instead of listing it twice,
  /// still a favorite if it was. Past the limit the oldest go, but never a favorite.
  public mutating func add(_ color: PickedColor) throws {
    var picked = color
    picked.isFavorite = colors.first { $0.hex == color.hex }?.isFavorite
    let all = [picked] + colors.filter { $0.hex != color.hex }
    var kept = 0
    try save(
      all.filter { each in
        if each.isFavorite == true { return true }
        kept += 1
        return kept <= Self.limit
      })
  }

  /// Adds the color `hex` to Favorite Colors, or takes it out.
  public mutating func toggleFavorite(hex: String) throws {
    try save(
      colors.map { color in
        var color = color
        if color.hex == hex { color.isFavorite = color.isFavorite == true ? nil : true }
        return color
      })
  }

  public mutating func delete(hex: String) throws {
    try save(colors.filter { $0.hex != hex })
  }

  /// Delete All Colors: every picked color but the favorites, as Clipboard History's Delete All
  /// Entries keeps the pinned ones.
  public mutating func deleteAll() throws {
    try save(colors.filter { $0.isFavorite == true })
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
    for query: String, history: ColorHistory, format: ColorFormat, favoritesOnly: Bool = false
  ) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    // Six-digit hex (#FFFFFF, though HEX writes #FFF), RGB and HSL only: the code formats'
    // labels ("red:", "Color") would match every color.
    let searched: [ColorFormat] = [.rgb, .hsl]
    let results = history.colors.filter { color in
      (!favoritesOnly || color.isFavorite == true)
        && (trimmed.isEmpty || color.hex.localizedStandardContains(trimmed)
          || searched.contains { $0.string(for: color).localizedStandardContains(trimmed) })
    }
    .map { color in
      // Raycast's Organize Colors: the default format copied on Return, pasted on ⌘↵, and the
      // others under Copy as…; its Edit Title and groups are left out.
      let shown = format.string(for: color)
      let copyAs = ColorFormat.allCases.map {
        MenuAction(
          title: $0.title, symbol: "doc.on.doc", shortcut: "", action: .copy($0.string(for: color)))
      }
      let isFavorite = color.isFavorite == true
      let menu =
        [
          MenuAction(
            title: "Copy to Clipboard", symbol: "doc.on.doc", shortcut: "↵", action: .copy(shown)),
          MenuAction(title: "Paste", symbol: "return", shortcut: "⌘↵", action: .pasteText(shown)),
          MenuAction(
            title: "Copy as…", symbol: "doc.on.doc", shortcut: "⇧⌘C",
            action: .submenu(title: "Copy as", items: copyAs)),
          // ⇧⌘F, as Raycast's Organize Colors has it.
          MenuAction(
            title: isFavorite ? "Remove from Favorites" : "Add to Favorites",
            symbol: "star", shortcut: "⇧⌘F",
            action: .toggleFavoriteColor(color.hex), startsSection: true),
          MenuAction(
            title: "Delete Color", symbol: "trash", shortcut: "⌃X",
            action: .deleteColor(color.hex), isDestructive: true, startsSection: true),
        ]
        // Not in Favorite Colors, whose colors it keeps: it would delete only what's not shown.
        + (favoritesOnly
          ? []
          : [
            MenuAction(
              title: "Delete All Colors", symbol: "trash", shortcut: "⌃⇧X",
              action: .deleteAllColors(confirmed: false), isDestructive: true)
          ])
      return SearchResult(
        id: "color:\(color.hex)", title: format.string(for: color),
        subtitle: format == .hex ? ColorFormat.rgb.string(for: color) : color.hex, keyword: nil,
        kind: .color, action: menu[0].action, menu: menu)
    }
    // Favorites first, as Raycast's Organize Colors lists them; Favorite Colors only them.
    let favorites = results.filter { result in
      history.colors.contains { "color:\($0.hex)" == result.id && $0.isFavorite == true }
    }
    let rest = results.filter { !favorites.map(\.id).contains($0.id) }
    return [
      SearchSection(title: favoritesOnly || rest.isEmpty ? "" : "Favorites", results: favorites),
      SearchSection(title: favorites.isEmpty ? "" : "History", results: rest),
    ].filter { !$0.results.isEmpty }
  }
}
