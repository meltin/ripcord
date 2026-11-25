import Foundation

/// An app's or a command's alias, hotkey and on/off switch, as the Shortcuts page sets them.
/// Quicklinks keep theirs on the `Quicklink` itself.
public struct ItemSettings: Codable, Equatable, Sendable {
  public var alias: String?
  public var hotkey: String?
  /// Stored only when true, so the file lists just what was changed.
  public var disabled: Bool?

  public init(alias: String? = nil, hotkey: String? = nil, disabled: Bool? = nil) {
    self.alias = alias
    self.hotkey = hotkey
    self.disabled = disabled
  }

  public var isEnabled: Bool {
    get { disabled != true }
    set { disabled = newValue ? nil : true }
  }

  /// Nothing differs from the defaults, so there's no reason to keep an entry.
  public var isEmpty: Bool { (alias ?? "").isEmpty && hotkey == nil && isEnabled }
}

/// What a registered hotkey does.
public enum HotkeyTarget: Hashable, Sendable {
  /// Shows the panel.
  case launcher
  /// An app (by settings key) or a built-in command (by `BuiltinCommand.settingsKey`).
  case item(String)
  /// The Quicklink at this index of `Config.quicklinks`.
  case quicklink(Int)
}

/// One row of the Shortcuts page.
public struct CatalogEntry: Identifiable, Equatable, Sendable {
  public let target: HotkeyTarget
  public let title: String
  public let kind: SearchResult.Kind
  /// The app bundle, for its icon; nil for Quicklinks and commands.
  public let appURL: URL?
  public var id: HotkeyTarget { target }
}

public struct CatalogSection: Identifiable, Equatable, Sendable {
  public let title: String
  public let entries: [CatalogEntry]
  public var id: String { title }
}

extension Config {
  /// Settings for `key`, or the defaults when there are none.
  public func item(_ key: String) -> ItemSettings {
    items[key] ?? ItemSettings()
  }

  /// Stores `settings` for `key`, dropping the entry once it's back to the defaults.
  public mutating func setItem(_ key: String, _ settings: ItemSettings) {
    var cleaned = settings
    // Kept as typed, so a space mid-typing ("my ap") survives; blank means none.
    if cleaned.alias?.trimmingCharacters(in: .whitespaces).isEmpty == true { cleaned.alias = nil }
    items[key] = cleaned.isEmpty ? nil : cleaned
  }

  /// Every hotkey to register, the launcher's first. Specs that don't parse and items switched
  /// off are left out, so a disabled item can't be run from its hotkey either.
  public var hotkeyAssignments: [(target: HotkeyTarget, hotkey: Hotkey)] {
    assignments(includingDisabled: false)
  }

  /// Which of Ripcord's own hotkeys already uses `hotkey`, other than `target` itself. Switched
  /// off items count too, so turning one back on can't clash. macOS lets two apps register the
  /// same keys, so only clashes inside Ripcord can be caught.
  public func owner(of hotkey: Hotkey, except target: HotkeyTarget) -> HotkeyTarget? {
    assignments(includingDisabled: true).first { $0.hotkey == hotkey && $0.target != target }?
      .target
  }

  private func assignments(includingDisabled: Bool) -> [(target: HotkeyTarget, hotkey: Hotkey)] {
    typealias Assignment = (target: HotkeyTarget, hotkey: Hotkey)
    let launcher = Hotkey(hotkey).map { [(target: HotkeyTarget.launcher, hotkey: $0)] } ?? []
    let itemKeys = items.compactMap { key, settings -> Assignment? in
      guard includingDisabled || settings.isEnabled else { return nil }
      return settings.hotkey.flatMap(Hotkey.init).map {
        (target: HotkeyTarget.item(key), hotkey: $0)
      }
    }
    .sorted { "\($0.target)" < "\($1.target)" }
    let links = quicklinks.enumerated().compactMap { index, link -> Assignment? in
      guard includingDisabled || link.isEnabled else { return nil }
      return link.hotkey.flatMap(Hotkey.init).map {
        (target: HotkeyTarget.quicklink(index), hotkey: $0)
      }
    }
    return launcher + itemKeys + links
  }
}
