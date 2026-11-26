import AppKit
import Carbon
import RipcordCore
import SwiftUI

/// Raycast's in-panel alert: Return runs `action`, Esc cancels.
struct Confirmation {
  /// Whose icon the card shows.
  enum Icon {
    case command(BuiltinCommand)
    case system(SystemAction)
  }

  let icon: Icon
  let title: String
  let message: String
  let confirmTitle: String
  let action: SearchResult.Action
}

/// The ⌘K actions of a row, or the root menu behind the footer's left button.
struct OpenMenu {
  let title: String
  let items: [MenuAction]
  let isRoot: Bool
  var selection = 0
}

/// What the panel lists: apps and commands, or one command's own list.
enum LauncherMode {
  case root, clipboard, snippets, snippetForm

  /// The command whose list this is; nil for the root search.
  var command: BuiltinCommand? {
    switch self {
    case .root: nil
    case .clipboard: .clipboardHistory
    case .snippets: .searchSnippets
    case .snippetForm: .createSnippet
    }
  }
}

@MainActor
@Observable
final class LauncherModel {
  var mode = LauncherMode.root
  /// The history the clipboard rows were built from, for the preview of the selected one.
  var clipboard: ClipboardHistory?
  /// The app a paste lands in: the one in front when the panel opened, as it never activates.
  var pasteTarget: String?
  var query = ""
  var sections: [SearchSection] = []
  var selection = 0
  var menu: OpenMenu?
  /// A question asked over the panel before something that can't be undone.
  var confirmation: Confirmation?
  /// The config's snippets, for the preview of the selected one.
  var snippets: [Snippet] = []
  /// What Create Snippet's form holds; `editing` is the snippet's index when it's an edit.
  var draft = Snippet(name: "", text: "")
  var editing: Int?
  /// The snippet as it was when the edit began, so a save never overwrites another one that
  /// took its place in the file meanwhile, even after the panel hid and the config was re-read.
  var editingOriginal: Snippet?
  var isPickingIcon = false
  /// The snippet the form was opened on from Search Snippets (edit or duplicate), selected again
  /// when it goes back there; nil for Create Snippet.
  var formSource: Int?
  /// Search Snippets' tag filter; nil lists every snippet.
  var snippetTag: String?
  /// The Tags field as typed; split into tags when saved, so a half-typed ", " stays put.
  var tagsText = ""

  /// Every row in display order; `selection` indexes into this.
  var results: [SearchResult] { sections.flatMap(\.results) }
  var selected: SearchResult? { results.indices.contains(selection) ? results[selection] : nil }
}

enum SearchCommand {
  case up, down, submit, cancel, back
  case activate(String)
  case toggleMenu(root: Bool)
  case filterTag(String?)
  case runMenuItem(Int)
  case selectMenuItem(Int)
}

/// A panel that takes keys without activating Ripcord, so the previous app stays frontmost.
final class LauncherPanel: NSPanel {
  var keyEquivalentHandler: ((NSEvent) -> Bool)?
  /// Sees Esc before the focused field; true when it handled it. A text editor would otherwise
  /// take Esc to show word completions.
  var escapeHandler: (() -> Bool)?

  override var canBecomeKey: Bool { true }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape),
      // Esc first cancels Japanese input that's still being composed.
      (firstResponder as? NSTextView)?.hasMarkedText() != true,
      escapeHandler?() == true
    {
      return
    }
    super.sendEvent(event)
  }

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
  var snippets: [Snippet] = [] {
    didSet {
      model.snippets = snippets
      if snippets != oldValue, model.mode == .snippets { refreshRows() }
    }
  }
  /// Saves a change to the config's snippets; false when the file couldn't be written.
  /// `change` gets the list as the file holds it now and returns the new one, or nil to refuse.
  var editSnippets: (_ change: ([Snippet]) -> [Snippet]?) -> Bool = { _ in false }
  /// The input source selected while the panel is open, by TIS ID; nil leaves it alone.
  var inputSource: String?
  /// What the panel switched away from, put back when it closes.
  private var previousInputSource: TISInputSource?
  var onOpenSettings: () -> Void = {}
  /// Shows why something couldn't be done, as a System Action that lacks a permission.
  var onError: (String) -> Void = { _ in NSSound.beep() }
  /// Export Snippets and Import Snippets, which need file dialogs and the config.
  var onExportSnippets: () -> Void = {}
  var onImportSnippets: () -> Void = {}
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
    panel.escapeHandler = { [weak self] in
      // Only the form: the search field turns Esc into .cancel itself.
      guard let self, model.mode == .snippetForm else { return false }
      // An open icon list closes first, as a menu does.
      if model.isPickingIcon {
        model.isPickingIcon = false
      } else {
        handle(.cancel)
      }
      return true
    }

    let glass = NSGlassEffectView()
    glass.cornerRadius = 22
    // A gray over the glass, as see-through as Raycast's panel: bare glass turns muddy over dark
    // or busy windows, and a glass tint comes out white. Measured on screen against Raycast: Light
    // matches over white and dark windows; Dark over dark windows only, as the dark glass is
    // brighter than Raycast and a gray over it can't match both.
    let background = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(srgbRed: 0.031, green: 0.051, blue: 0.049, alpha: 0.70)
        : NSColor(srgbRed: 0.902, green: 0.918, blue: 0.918, alpha: 0.52)
    }
    glass.contentView = NSHostingView(
      rootView: SearchView(
        model: model,
        onQueryChange: { [weak self] in self?.update($0) },
        onCommand: { [weak self] in self?.handle($0) }
      ).background(Color(nsColor: background)))
    panel.contentView = glass

    clipboard.onChange = { [weak self] in
      guard let self, model.mode == .clipboard else { return }
      refreshRows(selecting: model.selected?.id)
    }
    clipboard.start()
  }

  /// A command the panel hid in the middle of, as when the user clicked another app or pressed
  /// the hotkey, reopened as it was by the launcher hotkey for a while: Raycast's Pop to Root
  /// Search, whose default is 90 seconds.
  private var leftOpen: (mode: LauncherMode, at: Date)?
  private static let popToRootAfter: TimeInterval = 90

  func toggle() {
    panel.isVisible ? hide(keepingMode: true) : show(resuming: true)
  }

  func windowDidResignKey(_ notification: Notification) {
    // Not visible when orderOut itself resigned the key, after a finished action.
    if panel.isVisible { hide(keepingMode: true) }
  }

  private func show(_ mode: LauncherMode = .root, resuming: Bool = false) {
    let resumed = leftOpen.flatMap { left in
      resuming && Date.now.timeIntervalSince(left.at) < Self.popToRootAfter ? left.mode : nil
    }
    leftOpen = nil
    refreshApps()
    model.pasteTarget = NSWorkspace.shared.frontmostApplication?.localizedName
    if let resumed {
      // The query, selection and any draft are as they were; only the rows are re-read.
      model.mode = resumed
      refreshRows(selecting: model.selected?.id)
    } else {
      // What was left open is dropped, filter included.
      model.snippetTag = nil
      model.mode = mode
      update("")
    }
    isPlacing = true
    panel.setFrameTopLeftPoint(savedTopLeft() ?? defaultTopLeft())
    isPlacing = false
    switchInputSource()
    panel.makeKeyAndOrderFront(nil)
  }

  private func switchInputSource() {
    // Already switched when show() runs again on a visible panel (a command's hotkey).
    guard previousInputSource == nil, let id = inputSource, let target = InputSource.enabled(id)
    else { return }
    let current = InputSource.current()
    guard InputSource.id(of: current) != id else { return }
    previousInputSource = current
    InputSource.select(target)
  }

  /// Taken and cleared: hide() runs again when hiding resigns the panel's key status.
  private func restoreInputSource() {
    guard let previous = previousInputSource else { return }
    previousInputSource = nil
    InputSource.select(previous)
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

  /// `keepingMode` leaves a command's list or form as it is, to come back to (`leftOpen`).
  private func hide(keepingMode: Bool = false) {
    panel.orderOut(nil)
    model.menu = nil
    model.confirmation = nil
    restoreInputSource()
    // A kept form keeps its icon list too, so closing it doesn't move the caret to Name.
    if keepingMode, model.mode != .root {
      leftOpen = (model.mode, .now)
      return
    }
    model.isPickingIcon = false
    leftOpen = nil
    // A filter left on would hide snippets the next time, unasked.
    model.snippetTag = nil
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
    // A question belongs to the rows it was asked over; once they change it goes too.
    model.confirmation = nil
  }

  private func sections(for query: String) -> [SearchSection] {
    if model.mode == .clipboard {
      model.clipboard = clipboard.history
      return Search.clipboardSections(for: query, history: clipboard.history)
    }
    if model.mode == .snippets {
      // A tag no snippet carries any more lists nothing; drop it.
      if let tag = model.snippetTag,
        !snippets.contains(where: { !$0.text.isEmpty && $0.tags?.contains(tag) == true })
      {
        model.snippetTag = nil
      }
      return Search.snippetSections(for: query, snippets: snippets, tag: model.snippetTag)
    }
    // No rows behind the form, so ⌘K and row shortcuts have nothing to act on.
    if model.mode == .snippetForm { return [] }
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
    // A question takes Return and Esc, and nothing else gets through while it's up.
    if let confirmation = model.confirmation {
      switch command {
      case .submit:
        // Only a fresh press: a Return held down from the menu that opened the question
        // mustn't answer it.
        guard NSApp.currentEvent.map({ $0.type == .keyDown && $0.isARepeat }) != true else {
          return
        }
        model.confirmation = nil
        perform(confirmation.action)
      case .cancel, .back:
        model.confirmation = nil
      default: break
      }
      return
    }
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
    if model.mode == .snippetForm, case .submit = command { return saveDraft() }
    let count = model.results.count
    switch command {
    case .up: model.selection = max(model.selection - 1, 0)
    case .down: model.selection = min(model.selection + 1, max(count - 1, 0))
    case .submit: model.selected.map { perform($0.action) } ?? NSSound.beep()
    case .cancel:
      // An edit always goes back to its list, even one its hotkey opened.
      if model.mode == .snippetForm, model.formSource != nil { return goBack() }
      // Like Raycast: Esc leaves a command's list for the root search first.
      guard model.mode != .root, !closesOnCancel else { return hide() }
      goBack()
    case .back:
      goBack()
    case .activate(let id): model.results.first { $0.id == id }.map { perform($0.action) }
    case .toggleMenu(let root): toggleMenu(root: root)
    case .filterTag(let tag):
      model.snippetTag = tag
      update(model.query)
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
    // Shortcuts would act behind a question; only its Return and Esc count.
    guard model.confirmation == nil, !flags.isDisjoint(with: [.command, .control]),
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
    // Undo and redo, for the same reason; they matter in Create Snippet's editor.
    if key == "z", flags == .command || flags == [.command, .shift] {
      return NSApp.sendAction(
        flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:")), to: nil, from: panel)
    }
    if flags == .command, key == "\r", model.mode == .snippetForm {
      saveDraft()
      return true
    }
    if flags == .command, key == "k", model.mode != .snippetForm {
      toggleMenu(root: false)
      return true
    }
    let symbols: [(NSEvent.ModifierFlags, String)] = [
      (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]
    let shortcut = symbols.filter { flags.contains($0.0) }.map(\.1).joined() + key.uppercased()
    // ⌘N creates a snippet even when Search Snippets lists none.
    let create = MenuAction(
      title: "Create Snippet", symbol: "plus", shortcut: "⌘N", action: .run(.createSnippet))
    let candidates =
      (model.selected?.actions ?? []) + BuiltinCommand.rootMenu
      + (model.mode == .snippets ? [create] : [])
    guard let match = candidates.first(where: { $0.shortcut == shortcut }) else { return false }
    perform(match.action)
    return true
  }

  /// Runs a result's action; also what app, command and Quicklink hotkeys call.
  func perform(_ action: SearchResult.Action) {
    // Like Raycast, the panel stays open and glides home, so the reset is visible at once.
    if action == .run(.resetWindowPosition) { return resetPosition() }
    if action == .run(.clipboardHistory) { return open(.clipboard) }
    if action == .run(.searchSnippets) { return open(.snippets) }
    if action == .run(.createSnippet) { return edit(nil) }
    if case .clip(let id, let clipAction) = action { return perform(clipAction, on: id) }
    if case .snippet(let index, let snippetAction) = action {
      return perform(snippetAction, on: index)
    }
    if case .system(let system, let confirmed) = action {
      return perform(system, confirmed: confirmed)
    }
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
      // Signed as Ripcord's, by the nspasteboard.org convention, so the history credits it.
      NSPasteboard.general.setString(
        Bundle.main.bundleIdentifier ?? "", forType: .init("org.nspasteboard.source"))
    case .reveal(let url):
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .run(.settings):
      break  // Opened before hide(), above.
    case .run(.exportSnippets):
      onExportSnippets()
    case .run(.importSnippets):
      onImportSnippets()
    case .run(.resetWindowPosition), .run(.clipboardHistory), .run(.searchSnippets),
      .run(.createSnippet), .clip, .snippet, .system:
      break  // Handled above, without hiding the panel.
    case .run(.quit):
      NSApp.terminate(nil)
    }
  }

  /// Asks first for one with a warning, over the panel (opened for it when a hotkey ran it);
  /// otherwise hides the panel and runs it in the app the user was in.
  private func perform(_ action: SystemAction, confirmed: Bool) {
    if let warning = action.warning, !confirmed {
      if !panel.isVisible { show() }
      model.confirmation = Confirmation(
        icon: .system(action), title: "\(action.title)?", message: warning,
        confirmTitle: action.title, action: .system(action, confirmed: true))
      return
    }
    // The app in front now: the panel never activates Ripcord, so it's still the user's.
    let frontmost = NSWorkspace.shared.frontmostApplication
    hide()
    if let message = SystemActions.run(action, frontmost: frontmost) { onError(message) }
  }

  /// Opens a command's own list, from its row or its hotkey.
  private func open(_ mode: LauncherMode) {
    // Its hotkey closes its own list, as the launcher hotkey closes the panel.
    if panel.isVisible, model.mode == mode { return hide() }
    closesOnCancel = !panel.isVisible
    guard panel.isVisible else { return show(mode) }
    model.mode = mode
    update("")
  }

  /// An edit goes back to Search Snippets, where it started; anything else to the root search.
  private func goBack() {
    model.isPickingIcon = false
    let source = model.mode == .snippetForm ? model.formSource : nil
    model.mode = source == nil ? .root : .snippets
    update("")
    if let source { refreshRows(selecting: "snippet:\(source)") }
  }

  /// Opens the form on a new snippet, or on the one at `index`.
  /// A new snippet's draft survives the panel closing, as when clicking another app to copy
  /// something into it; it's cleared once saved.
  private func edit(_ index: Int?, duplicate: Bool = false) {
    model.isPickingIcon = false
    let draftIsNew = model.formSource == nil
    let source = index.flatMap { snippets.indices.contains($0) ? $0 : nil }
    model.formSource = source
    model.editing = duplicate ? nil : source
    model.editingOriginal = model.editing.map { snippets[$0] }
    if let source {
      let snippet = snippets[source]
      model.draft = snippet
      // A copy gets its own name, and no keyword, which belongs to the original alone.
      if duplicate {
        model.draft.name = "\(snippet.name) Copy"
        model.draft.keyword = nil
      }
      model.tagsText = (snippet.tags ?? []).joined(separator: ", ")
    } else if !draftIsNew {
      model.draft = Snippet(name: "", text: "")
      model.tagsText = ""
    }
    if index != nil {
      model.mode = .snippetForm
      return update("")
    }
    open(.snippetForm)
  }

  /// Saves the form, then shows the snippet in Search Snippets. A name and text are required.
  private func saveDraft() {
    let draft = Snippet(
      name: model.draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
      text: model.draft.text,
      keyword: model.draft.keyword?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
      icon: model.draft.icon, tags: Snippet.tags(from: model.tagsText))
    guard !draft.name.isEmpty, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return NSSound.beep() }
    let editing = model.editing.flatMap { index in model.editingOriginal.map { (index, $0) } }
    var index = 0
    let saved = editSnippets { current in
      guard let (at, original) = editing else {
        index = current.count
        return current + [draft]
      }
      // The file may have changed since the list was read; never overwrite another snippet.
      guard current.indices.contains(at), current[at] == original else { return nil }
      index = at
      return current.enumerated().map { $0.offset == at ? draft : $0.element }
    }
    guard saved else { return NSSound.beep() }
    model.draft = Snippet(name: "", text: "")
    model.tagsText = ""
    model.editing = nil
    model.editingOriginal = nil
    model.formSource = nil
    model.isPickingIcon = false
    // A filter that would hide the saved snippet is dropped.
    if let tag = model.snippetTag, draft.tags?.contains(tag) != true { model.snippetTag = nil }
    model.mode = .snippets
    update("")
    refreshRows(selecting: "snippet:\(index)")
  }

  private func perform(_ action: SearchResult.SnippetAction, on index: Int) {
    guard snippets.indices.contains(index) else { return NSSound.beep() }
    switch action {
    case .paste, .copy: paste(snippets[index].text, copyOnly: action == .copy)
    case .edit: edit(index)
    case .duplicate: edit(index, duplicate: true)
    case .delete:
      // Asked first, as Raycast does by default: a deleted snippet has no undo.
      model.menu = nil
      model.confirmation = Confirmation(
        icon: .command(.searchSnippets), title: "Delete “\(snippets[index].name)”?",
        message: "Warning: this can't be undone.",
        confirmTitle: "Delete", action: .snippet(index, .confirmDelete))
    case .confirmDelete:
      model.menu = nil
      let original = snippets[index]
      let saved = editSnippets { current in
        // As in saveDraft: only the snippet that was shown, never one that took its place.
        guard current.indices.contains(index), current[index] == original else { return nil }
        return current.enumerated().filter { $0.offset != index }.map(\.element)
      }
      if !saved { NSSound.beep() }
    }
  }

  /// Paste borrows the pasteboard and puts back what the user had copied; Copy replaces it.
  private func paste(_ text: String, copyOnly: Bool) {
    let action: SearchResult.SnippetAction = copyOnly ? .copy : .paste
    // Read before writing, which replaces what {clipboard} stands for.
    let copied = NSPasteboard.general.string(forType: .string) ?? ""
    let expansion = Snippet.expand(text, values: Snippet.values(at: .now), clipboard: copied)
    let concealed = clipboard.isConcealed && text.contains("{clipboard}")
    let saved = action == .paste ? clipboard.snapshot() : []
    let written = clipboard.write(
      expansion.text, transient: action == .paste, concealed: concealed)
    hide()
    guard written else { return NSSound.beep() }
    guard action == .paste else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [clipboard] in
      guard clipboard.pasteIntoFrontmostApp(thenLeft: expansion.charactersAfterCursor) else {
        // Not pasted (no Accessibility yet): put back what was copied, or the retry after
        // granting it would fill {clipboard} with this snippet.
        clipboard.restore(saved)
        return NSSound.beep()
      }
      // shortcut: the app reads the pasteboard when it handles ⌘V, which 0.5 s covers for
      // ordinary apps; a hung app would paste what was copied before. Wait for it if one does.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { clipboard.restore(saved) }
    }
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

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
