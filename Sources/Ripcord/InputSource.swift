import Carbon

/// Keyboard input sources (ABC, Hiragana, third-party input methods), through Text Input Sources.
enum InputSource {
  struct Option: Identifiable, Hashable {
    let id: String
    let name: String
  }

  /// The enabled sources the input menu can switch to, in its order.
  static func selectable() -> [Option] {
    list([kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource]).compactMap { source in
      guard flag(source, kTISPropertyInputSourceIsSelectCapable),
        let id = text(source, kTISPropertyInputSourceID)
      else { return nil }
      return Option(id: id, name: text(source, kTISPropertyLocalizedName) ?? id)
    }
  }

  /// Nil when `id` is no longer enabled.
  static func enabled(_ id: String) -> TISInputSource? {
    list([kTISPropertyInputSourceID: id as CFString]).first
  }

  static func current() -> TISInputSource {
    TISCopyCurrentKeyboardInputSource().takeRetainedValue()
  }

  static func id(of source: TISInputSource) -> String? {
    text(source, kTISPropertyInputSourceID)
  }

  static func select(_ source: TISInputSource) {
    TISSelectInputSource(source)
  }

  private static func list(_ filter: [CFString: CFString]) -> [TISInputSource] {
    TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue()
      as? [TISInputSource] ?? []
  }

  private static func text(_ source: TISInputSource, _ key: CFString) -> String? {
    TISGetInputSourceProperty(source, key).map {
      Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
    }
  }

  private static func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
    TISGetInputSourceProperty(source, key).map {
      CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue())
    } ?? false
  }
}
