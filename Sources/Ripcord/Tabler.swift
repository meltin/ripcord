import AppKit
import SwiftUI

/// Ripcord's icons: Tabler Icons (MIT, Resources/Tabler), looked up by the SF Symbols name the
/// code and the config use, so a snippet's saved icon keeps working.
enum Tabler {
  /// SF Symbols name → Tabler's `outline/…` or `filled/…`.
  static let names: [String: String] = [
    "accessibility": "outline/accessible",
    "airplane": "outline/plane",
    "alarm": "outline/alarm",
    "ant": "outline/bug",
    "archivebox": "outline/archive",
    "arrow.clockwise": "outline/refresh",
    "arrow.triangle.branch": "outline/git-branch",
    "arrow.turn.up.right": "outline/arrow-forward-up",
    "arrow.up.forward.app": "outline/external-link",
    "arrow.up.left.and.arrow.down.right": "outline/arrows-diagonal",
    "arrow.uturn.backward": "outline/arrow-back-up",
    "at": "outline/at",
    "backward.fill": "filled/player-skip-back",
    "bag": "outline/shopping-bag",
    "bell": "outline/bell",
    "bicycle": "outline/bike",
    "bird": "outline/feather",
    "bolt": "outline/bolt",
    "book": "outline/book",
    "bookmark": "outline/bookmark",
    "bookmark.circle.fill": "outline/bookmark-plus",
    "bookmark.fill": "filled/bookmark",
    "brain": "outline/brain",
    "briefcase": "outline/briefcase",
    "building.2": "outline/building",
    "calendar": "outline/calendar",
    "camera": "outline/camera",
    "camera.viewfinder": "outline/capture",
    "car": "outline/car",
    "cart": "outline/shopping-cart",
    "checklist": "outline/list-check",
    "checkmark.circle": "outline/circle-check",
    "checkmark.circle.fill": "filled/circle-check",
    "checkmark.square.fill": "filled/square-check",
    "chevron.down": "outline/chevron-down",
    "chevron.left": "outline/chevron-left",
    "chevron.left.forwardslash.chevron.right": "outline/code",
    "chevron.up": "outline/chevron-up",
    "chevron.up.chevron.down": "outline/selector",
    "circle.lefthalf.filled": "outline/contrast",
    "clock": "outline/clock",
    "cloud": "outline/cloud",
    "command": "outline/command",
    "creditcard": "outline/credit-card",
    "cup.and.saucer": "outline/coffee",
    "cup.and.saucer.fill": "outline/coffee",
    "display": "outline/device-desktop",
    "doc": "outline/file",
    "doc.badge.plus": "outline/file-plus",
    "doc.on.doc": "outline/copy",
    "doc.plaintext.fill": "outline/file-text",
    "doc.text": "outline/file-text",
    "eject.fill": "outline/player-eject",
    "envelope": "outline/mail",
    "equal": "outline/menu-2",
    "exclamationmark.triangle": "outline/alert-triangle",
    "exclamationmark.triangle.fill": "filled/alert-triangle",
    "eye.fill": "outline/eye",
    "eye.slash.fill": "outline/eye-off",
    "eye.trianglebadge.exclamationmark": "outline/eye-exclamation",
    "eyedropper": "outline/color-picker",
    "face.smiling": "outline/mood-smile",
    "film": "outline/movie",
    "flag": "outline/flag",
    "flame": "outline/flame",
    "folder": "outline/folder",
    "folder.fill": "filled/folder",
    "fork.knife": "outline/tools-kitchen-2",
    "forward.fill": "filled/player-skip-forward",
    "gearshape": "outline/settings",
    "gearshape.fill": "filled/settings",
    "gift": "outline/gift",
    "globe": "outline/world",
    "graduationcap": "outline/school",
    "hammer": "outline/hammer",
    "hand.thumbsup": "outline/thumb-up",
    "hand.wave": "outline/hand-stop",
    "heart": "outline/heart",
    "house": "outline/home",
    "info.circle": "outline/info-circle",
    "key": "outline/key",
    "keyboard": "outline/keyboard",
    "keyboard.fill": "outline/keyboard",
    "leaf": "outline/leaf",
    "lightbulb": "outline/bulb",
    "link": "outline/link",
    "list.bullet": "outline/list",
    "list.clipboard.fill": "outline/clipboard-list",
    "lock": "outline/lock",
    "lock.fill": "filled/lock",
    "lock.shield.fill": "outline/shield-lock",
    "macwindow": "outline/app-window",
    "magnifyingglass": "outline/search",
    "mappin.and.ellipse": "outline/map-pin",
    "menubar.dock.rectangle": "outline/layout-navbar",
    "message": "outline/message",
    "mic": "outline/microphone",
    "minus.circle": "outline/circle-minus",
    "moon": "outline/moon",
    "moon.fill": "filled/moon",
    "moon.zzz": "outline/zzz",
    "moon.zzz.fill": "outline/zzz",
    "music.note": "outline/music",
    "network": "outline/network",
    "note.text": "outline/notes",
    "number": "outline/hash",
    "paperclip": "outline/paperclip",
    "paperplane": "outline/send",
    "pawprint": "outline/paw",
    "pencil": "outline/pencil",
    "person": "outline/user",
    "person.2": "outline/users",
    "phone": "outline/phone",
    "photo": "outline/photo",
    "pin": "outline/pin",
    "pin.slash": "outline/pinned-off",
    "playpause.fill": "filled/player-play",
    "plus": "outline/plus",
    "plus.forwardslash.minus": "outline/math-symbols",
    "plus.square.on.square": "outline/copy-plus",
    "power": "outline/power",
    "questionmark.circle": "outline/help-circle",
    "quote.opening": "outline/quote",
    "rectangle.bottomhalf.filled": "outline/layout-bottombar",
    "rectangle.center.inset.filled": "outline/layout-align-middle",
    "rectangle.inset.bottomleft.filled": "outline/box-align-bottom-left",
    "rectangle.inset.bottomright.filled": "outline/box-align-bottom-right",
    "rectangle.inset.filled": "outline/arrows-maximize",
    "rectangle.inset.topleft.filled": "outline/box-align-top-left",
    "rectangle.inset.topright.filled": "outline/box-align-top-right",
    "rectangle.lefthalf.filled": "outline/layout-sidebar",
    "rectangle.lefthalf.inset.filled.arrow.left": "outline/arrow-bar-left",
    "rectangle.portrait.and.arrow.right": "outline/logout",
    "rectangle.righthalf.filled": "outline/layout-sidebar-right",
    "rectangle.righthalf.inset.filled.arrow.right": "outline/arrow-bar-right",
    "rectangle.split.2x1": "outline/layout-columns",
    "rectangle.split.2x1.fill": "outline/layout-columns",
    "rectangle.split.3x1": "outline/columns-3",
    "rectangle.tophalf.filled": "outline/layout-navbar",
    "restart": "outline/rotate-clockwise",
    "return": "outline/corner-down-left",
    "safari": "outline/compass",
    "signature": "outline/signature",
    "sleep": "outline/zzz",
    "slider.horizontal.3": "outline/adjustments-horizontal",
    "sparkles": "outline/sparkles",
    "speaker.slash.fill": "outline/volume-3",
    "speaker.wave.1.fill": "outline/volume-2",
    "speaker.wave.3.fill": "outline/volume",
    "square": "outline/square",
    "square.and.arrow.down": "outline/download",
    "square.and.arrow.up": "outline/upload",
    "square.grid.2x2.fill": "outline/apps",
    "star": "outline/star",
    "sun.max": "outline/sun",
    "swatchpalette.fill": "outline/palette",
    "tag": "outline/tag",
    "terminal": "outline/terminal-2",
    "text.cursor": "outline/cursor-text",
    "trash": "outline/trash",
    "trash.fill": "filled/trash",
    "tray": "outline/inbox",
    "umbrella": "outline/umbrella",
    "wand.and.stars": "outline/wand",
    "wrench.adjustable": "outline/tool",
    "xmark.app.fill": "outline/square-x",
    "xmark.circle.fill": "filled/circle-x",
  ]

  /// The icon at `size` points as a template image, so it takes the text's color; nil when
  /// the symbol has no Tabler match or the app's resources aren't there (`swift run`).
  @MainActor static func image(_ symbol: String, size: CGFloat) -> NSImage? {
    let key = "\(symbol)@\(size)"
    if let cached = cache[key] { return cached }
    guard let name = names[symbol],
      let url = Bundle.main.url(
        forResource: (name as NSString).lastPathComponent, withExtension: "svg",
        subdirectory: "Tabler/" + (name as NSString).deletingLastPathComponent),
      var svg = try? String(contentsOf: url, encoding: .utf8)
    else { return nil }
    // Tabler's 2-unit stroke grows with the icon; big ones get a lighter line, as the light SF
    // Symbols they replace had.
    if size >= 32 { svg = svg.replacing("stroke-width=\"2\"", with: "stroke-width=\"1.25\"") }
    guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
    // An SVG scales as a vector, so setting the size draws it sharp at any size.
    image.size = NSSize(width: size, height: size)
    image.isTemplate = true
    cache[key] = image
    return image
  }

  @MainActor private static var cache: [String: NSImage] = [:]
}

/// A Tabler icon where an SF Symbol was, at about the size the symbol had at `pointSize`, in
/// the current foreground style. Falls back to the SF Symbol where there's no Tabler icon.
struct Glyph: View {
  let symbol: String
  let pointSize: CGFloat

  init(_ symbol: String, pointSize: CGFloat = 13) {
    self.symbol = symbol
    self.pointSize = pointSize
  }

  /// Tabler draws in a 24-point box with a margin, so it's set a little larger than the font.
  private var side: CGFloat { (pointSize * 1.3).rounded() }

  var body: some View {
    if let image = Tabler.image(symbol, size: side) {
      // Decoration beside text that names the thing, as SF Symbols in labels were.
      Image(nsImage: image).renderingMode(.template).frame(width: side, height: side)
        .accessibilityHidden(true)
    } else {
      Image(systemName: symbol).font(.system(size: pointSize))
    }
  }
}
