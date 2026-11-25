import AppKit
import RipcordCore
import SwiftUI

/// The ⌘K actions of a row, or the root menu behind the footer's left button.
struct OpenMenu {
  let title: String
  let items: [MenuAction]
  let isRoot: Bool
  var selection = 0
}

@MainActor
@Observable
final class LauncherModel {
  var query = ""
  var sections: [SearchSection] = []
  var selection = 0
  var menu: OpenMenu?

  /// Every row in display order; `selection` indexes into this.
  var results: [SearchResult] { sections.flatMap(\.results) }
  var selected: SearchResult? { results.indices.contains(selection) ? results[selection] : nil }
}

enum SearchCommand {
  case up, down, submit, cancel
  case activate(String)
  case toggleMenu(root: Bool)
  case runMenuItem(Int)
  case selectMenuItem(Int)
}

/// A panel that takes keys without activating Ripcord, so the previous app stays frontmost.
final class LauncherPanel: NSPanel {
  var keyEquivalentHandler: ((NSEvent) -> Bool)?

  override var canBecomeKey: Bool { true }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    keyEquivalentHandler?(event) == true || super.performKeyEquivalent(with: event)
  }
}

@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
  static let size = NSSize(width: 750, height: 474)
  static let fieldHeight: CGFloat = 56
  static let rowHeight: CGFloat = 40
  static let footerHeight: CGFloat = 48

  var quicklinks: [Quicklink] = [] {
    didSet { update(model.query) }
  }
  var onEditConfig: () -> Void = {}
  var isVisible: Bool { panel.isVisible }

  private let model = LauncherModel()
  private let panel = LauncherPanel(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  private var apps: [AppEntry] = []

  override init() {
    super.init()
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.delegate = self
    panel.keyEquivalentHandler = { [weak self] in self?.handleKeyEquivalent($0) ?? false }

    let glass = NSGlassEffectView()
    glass.cornerRadius = 22
    glass.contentView = NSHostingView(
      rootView: SearchView(
        model: model,
        onQueryChange: { [weak self] in self?.update($0) },
        onCommand: { [weak self] in self?.handle($0) }))
    panel.contentView = glass
  }

  func toggle() {
    panel.isVisible ? hide() : show()
  }

  func windowDidResignKey(_ notification: Notification) {
    hide()
  }

  private func show() {
    refreshApps()
    update("")
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    if let visible = screen?.visibleFrame {
      let top = visible.maxY - visible.height * 0.15
      panel.setFrameTopLeftPoint(NSPoint(x: visible.midX - Self.size.width / 2, y: top))
    }
    panel.makeKeyAndOrderFront(nil)
  }

  private func hide() {
    panel.orderOut(nil)
    update("")
  }

  private func refreshApps() {
    Task {
      apps = await Task.detached(priority: .userInitiated) { AppIndex.scan() }.value
      // Refresh the rows only: a ↓ or ⌘K pressed while the scan ran must survive it.
      model.sections = sections(for: model.query)
      model.selection = min(model.selection, max(model.results.count - 1, 0))
    }
  }

  private func update(_ query: String) {
    model.query = query
    model.sections = sections(for: query)
    model.selection = 0
    model.menu = nil
  }

  private func sections(for query: String) -> [SearchSection] {
    let running = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .compactMap { app in
        app.bundleURL.map { AppEntry(url: $0, names: [app.localizedName ?? $0.lastPathComponent]) }
      }
    return Search.sections(for: query, apps: apps, running: running, quicklinks: quicklinks)
  }

  private func handle(_ command: SearchCommand) {
    // An open menu takes the arrows, Return and Esc.
    if let menu = model.menu {
      switch command {
      case .up:
        model.menu?.selection = max(menu.selection - 1, 0)
        return
      case .down:
        model.menu?.selection = min(menu.selection + 1, menu.items.count - 1)
        return
      case .submit:
        return perform(menu.items[menu.selection].action)
      case .cancel:
        model.menu = nil
        return
      default: break
      }
    }
    let count = model.results.count
    switch command {
    case .up: model.selection = max(model.selection - 1, 0)
    case .down: model.selection = min(model.selection + 1, max(count - 1, 0))
    case .submit: model.selected.map { perform($0.action) } ?? NSSound.beep()
    case .cancel: hide()
    case .activate(let id): model.results.first { $0.id == id }.map { perform($0.action) }
    case .toggleMenu(let root): toggleMenu(root: root)
    case .runMenuItem(let index):
      if let items = model.menu?.items, items.indices.contains(index) {
        perform(items[index].action)
      }
    case .selectMenuItem(let index): model.menu?.selection = index
    }
  }

  private func toggleMenu(root: Bool) {
    let wantsRoot = root || model.selected == nil
    guard model.menu?.isRoot != wantsRoot else {
      model.menu = nil
      return
    }
    if !wantsRoot, let selected = model.selected {
      model.menu = OpenMenu(title: selected.title, items: selected.actions, isRoot: false)
    } else {
      let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      model.menu = OpenMenu(
        title: ["Ripcord", version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " "),
        items: BuiltinCommand.rootMenu, isRoot: true)
    }
  }

  private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
    guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased()
    else { return false }
    // An accessory app has no Edit menu, so ⌘X/C/V/A never reach the search field otherwise.
    let editing = [
      "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
      "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
    ]
    if flags == .command, let selector = editing[key] {
      return NSApp.sendAction(selector, to: nil, from: panel)
    }
    if flags == .command, key == "k" {
      toggleMenu(root: false)
      return true
    }
    let symbols: [(NSEvent.ModifierFlags, String)] = [
      (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]
    let shortcut = symbols.filter { flags.contains($0.0) }.map(\.1).joined() + key.uppercased()
    let candidates = (model.selected?.actions ?? []) + BuiltinCommand.rootMenu
    guard let match = candidates.first(where: { $0.shortcut == shortcut }) else { return false }
    perform(match.action)
    return true
  }

  private func perform(_ action: SearchResult.Action) {
    hide()
    switch action {
    case .open(let url):
      if !NSWorkspace.shared.open(url) { NSSound.beep() }
    case .copy(let text):
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    case .reveal(let url):
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .run(.editConfig):
      onEditConfig()
    case .run(.quit):
      NSApp.terminate(nil)
    }
  }
}
