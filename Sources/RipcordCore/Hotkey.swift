import Carbon.HIToolbox

/// A global shortcut such as "option+space", in the form Carbon's RegisterEventHotKey takes.
public struct Hotkey: Equatable, Sendable {
  public let keyCode: UInt32
  public let modifiers: UInt32

  /// Nil unless `spec` is modifiers including ⌘, ⌥ or ⌃, then "space", "return", an arrow
  /// ("left", "right", "up", "down"), a letter or a digit.
  public init?(_ spec: String) {
    let parts = spec.lowercased().split(separator: "+").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    guard let key = parts.last, let code = Self.keyCodes[key] else { return nil }
    let flags = parts.dropLast().map { Self.modifierFlags[$0] }
    guard flags.allSatisfy({ $0 != nil }) else { return nil }
    self.init(keyCode: code, modifiers: flags.compactMap { $0 }.reduce(0, |))
  }

  /// A recorded key press; nil for keys a spec can't name or a press without ⌘, ⌥ or ⌃.
  public init?(keyCode: UInt32, modifiers: UInt32) {
    let known = Self.ordered.map(\.flag).reduce(0, |)
    // Shift alone would take a capital letter away from every app on the Mac.
    let required = UInt32(cmdKey | optionKey | controlKey)
    guard Self.keyCodes.values.contains(keyCode), modifiers & required != 0 else { return nil }
    self.keyCode = keyCode
    self.modifiers = modifiers & known
  }

  /// The form the config file stores, e.g. "cmd+shift+k".
  public var spec: String {
    let key = Self.keyCodes.first { $0.value == keyCode }?.key ?? ""
    return (Self.ordered.filter { modifiers & $0.flag != 0 }.map(\.name) + [key])
      .joined(separator: "+")
  }

  /// Keycaps as macOS menus show them, e.g. ["⇧", "⌘", "K"] or ["⌘", "Space"].
  public var keycaps: [String] {
    let key = Self.keyCodes.first { $0.value == keyCode }?.key ?? ""
    return Self.ordered.filter { modifiers & $0.flag != 0 }.map(\.symbol)
      + [Self.keycapNames[key] ?? key.uppercased()]
  }

  // ⌃⌥⇧⌘ is the order macOS menus print modifiers in.
  private static let ordered: [(flag: UInt32, name: String, symbol: String)] = [
    (UInt32(controlKey), "ctrl", "⌃"), (UInt32(optionKey), "option", "⌥"),
    (UInt32(shiftKey), "shift", "⇧"), (UInt32(cmdKey), "cmd", "⌘"),
  ]

  private static let modifierFlags: [String: UInt32] = [
    "cmd": UInt32(cmdKey), "command": UInt32(cmdKey),
    "option": UInt32(optionKey), "opt": UInt32(optionKey), "alt": UInt32(optionKey),
    "ctrl": UInt32(controlKey), "control": UInt32(controlKey),
    "shift": UInt32(shiftKey),
  ]

  private static let keycapNames = [
    "space": "Space", "return": "↩", "left": "←", "right": "→", "up": "↑", "down": "↓",
  ]

  private static let keyCodes: [String: UInt32] = [
    "space": kVK_Space, "return": kVK_Return,
    // For window layouts, which Rectangle and Raycast put on ⌃⌥ and the arrows.
    "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
    "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
    "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
    "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
    "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
    "z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
    "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
  ].mapValues { UInt32($0) }
}
