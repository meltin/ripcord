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

/// What the panel lists: apps and commands, or one command's own list.
enum LauncherMode {
  case root, clipboard
}

@MainActor
@Observable
final class LauncherModel {
  var mode = LauncherMode.root
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
  private static let positionKey = "panelTopLeft"

  var quicklinks: [Quicklink] = [] {
    didSet { if quicklinks != oldValue { update(model.query) } }
  }
  var items: [String: ItemSettings] = [:] {
    didSet {
      guard items != oldValue else { return }
      clipboard.isEnabled = items[BuiltinCommand.clipboardHistory.settingsKey]?.isEnabled ?? true
      update(model.query)
    }
  }
  var onOpenSettings: () -> Void = {}
  var isVisible: Bool { panel.isVisible }

  private let model = LauncherModel()
  private let panel = LauncherPanel(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  private var apps: [AppEntry] = []
  private var isPlacing = false
  private let clipboard = ClipboardMonitor(
    directory: URL.applicationSupportDirectory.appending(path: "Ripcord/Clipboard"))
  /// Opened straight into a command by its hotkey, so Esc closes the panel instead of going
  /// back to the root search.
  private var closesOnCancel = false

  override init() {
    super.init()
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = true
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

    clipboard.onChange = { [weak self] in
      guard let self, model.mode == .clipboard else { return }
      refreshRows(selecting: model.selected?.id)
    }
    clipboard.start()
  }

  func toggle() {
    panel.isVisible ? hide() : show()
  }

  func windowDidResignKey(_ notification: Notification) {
    hide()
  }

  private func show(_ mode: LauncherMode = .root) {
    refreshApps()
    model.mode = mode
    update("")
    isPlacing = true
    panel.setFrameTopLeftPoint(savedTopLeft() ?? defaultTopLeft())
    isPlacing = false
    panel.makeKeyAndOrderFront(nil)
  }

  /// Saves where the user dragged the panel; moves made by `show()` itself don't count.
  func windowDidMove(_ notification: Notification) {
    guard !isPlacing else { return }
    let frame = panel.frame
    UserDefaults.standard.set(
      NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: Self.positionKey)
  }

  private func resetPosition() {
    UserDefaults.standard.removeObject(forKey: Self.positionKey)
    // From a hotkey with the panel hidden: open it at home so the reset can be seen.
    guard panel.isVisible else { return show() }
    let topLeft = defaultTopLeft()
    isPlacing = true
    // Animated setFrame returns once the move finishes, so windowDidMove stays ignored meanwhile.
    panel.setFrame(
      NSRect(
        x: topLeft.x, y: topLeft.y - Self.size.height, width: Self.size.width,
        height: Self.size.height),
      display: true, animate: true)
    isPlacing = false
    update("")
  }

  private func defaultTopLeft() -> NSPoint {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return .zero }
    return NSPoint(x: visible.midX - Self.size.width / 2, y: visible.maxY - visible.height * 0.15)
  }

  /// Nil when nothing is saved or the saved spot is off every screen (a display was unplugged).
  private func savedTopLeft() -> NSPoint? {
    guard let saved = UserDefaults.standard.string(forKey: Self.positionKey) else { return nil }
    let point = NSPointFromString(saved)
    let frame = NSRect(
      x: point.x, y: point.y - Self.size.height, width: Self.size.width, height: Self.size.height)
    return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) } ? point : nil
  }

  private func hide() {
    panel.orderOut(nil)
    model.mode = .root
    update("")
  }

  private func refreshApps() {
    Task {
      apps = await Task.detached(priority: .userInitiated) { AppIndex.scan() }.value
      // Refresh the rows only: a ↓ or ⌘K pressed while the scan ran must survive it.
      refreshRows()
    }
  }

  /// New rows for the same query. The selection follows the row `id` when it's still listed,
  /// since a pinned or newly copied clip reorders the rows; otherwise it keeps its place.
  private func refreshRows(selecting id: String? = nil) {
    model.sections = sections(for: model.query)
    model.selection =
      id.flatMap { id in model.results.firstIndex { $0.id == id } }
      ?? min(model.selection, max(model.results.count - 1, 0))
  }

  private func update(_ query: String) {
    model.query = query
    model.sections = sections(for: query)
    model.selection = 0
    model.menu = nil
  }

  private func sections(for query: String) -> [SearchSection] {
    if model.mode == .clipboard {
      return Search.clipboardSections(for: query, history: clipboard.history)
    }
    let running = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .compactMap { app in
        app.bundleURL.map {
          AppEntry(
            url: $0, names: [app.localizedName ?? $0.lastPathComponent],
            bundleID: app.bundleIdentifier)
        }
      }
    return Search.sections(
      for: query, apps: apps, running: running, quicklinks: quicklinks, items: items)
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
    case .cancel:
      // Like Raycast: Esc leaves a command's list for the root search first.
      guard model.mode != .root, !closesOnCancel else { return hide() }
      model.mode = .root
      update("")
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
    // ⌃ too, for Raycast's ⌃X Delete.
    guard !flags.isDisjoint(with: [.command, .control]),
      let key = event.charactersIgnoringModifiers?.lowercased()
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

  /// Runs a result's action; also what app, command and Quicklink hotkeys call.
  func perform(_ action: SearchResult.Action) {
    // Like Raycast, the panel stays open and glides home, so the reset is visible at once.
    if action == .run(.resetWindowPosition) { return resetPosition() }
    if action == .run(.clipboardHistory) { return openClipboardHistory() }
    if case .clip(let id, let clipAction) = action { return perform(clipAction, on: id) }
    // Open Settings while the panel still holds the key press, so macOS treats it as the
    // user's request to bring Ripcord forward.
    if action == .run(.settings) { onOpenSettings() }
    hide()
    switch action {
    case .open(let url):
      if !NSWorkspace.shared.open(url) { NSSound.beep() }
    case .copy(let text):
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    case .reveal(let url):
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .run(.settings):
      break  // Opened before hide(), above.
    case .run(.resetWindowPosition), .run(.clipboardHistory), .clip:
      break  // Handled above, without hiding the panel.
    case .run(.quit):
      NSApp.terminate(nil)
    }
  }

  private func openClipboardHistory() {
    // Its hotkey closes its own list, as the launcher hotkey closes the panel.
    if panel.isVisible, model.mode == .clipboard { return hide() }
    closesOnCancel = !panel.isVisible
    guard panel.isVisible else { return show(.clipboard) }
    model.mode = .clipboard
    update("")
  }

  private func perform(_ action: SearchResult.ClipAction, on id: UUID) {
    switch action {
    case .paste, .copy:
      let copied = clipboard.copy(id)
      hide()
      guard copied else { return NSSound.beep() }
      guard action == .paste else { return }
      // After the panel has given the key back to the app being pasted into.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [clipboard] in
        // Without the permission the item is only copied; say so, as other failures do.
        if !clipboard.pasteIntoFrontmostApp() { NSSound.beep() }
      }
    case .togglePin, .delete:
      let selected = model.selected?.id
      action == .delete ? clipboard.delete(id) : clipboard.togglePin(id)
      model.menu = nil
      refreshRows(selecting: action == .togglePin ? "clip:\(id)" : selected)
    }
  }
}
