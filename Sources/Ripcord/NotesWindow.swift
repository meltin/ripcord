import AppKit
import Carbon.HIToolbox
import RipcordCore
import SwiftUI

/// The note being edited and what's typed in it.
@MainActor
@Observable
final class NotesModel {
  var note: Note
  var text: String
  /// Why the last save didn't happen; nil once one does.
  var problem: String?
  /// Bumped to put the caret in the editor, as the window comes forward.
  var focusRequest = 0
  /// The pointer is over the window: its buttons show, as Raycast Notes shows them.
  var isHovered = false
  /// Zoom In and Zoom Out's scale of the text.
  var zoom: CGFloat = 1

  init(note: Note) {
    self.note = note
    text = note.text
  }
}

/// Ripcord Notes' window: one note at a time, floating above other apps as Raycast Notes does,
/// and taking keys without bringing Ripcord forward, so the app you were in stays in front.
@MainActor
final class NotesWindowController: NSObject, NSWindowDelegate {
  private let store: NoteStore
  private let model: NotesModel
  /// Search Notes, in the launcher, for ⌘P.
  var onBrowse: () -> Void = {}
  /// Settings' Notes page, for Open Notes Settings.
  var onSettings: () -> Void = {}
  private let actionsModel = NotesActionsModel()
  /// The note's text as last laid out, for the window to fit when auto-sizing comes back on.
  private var textHeight: CGFloat = 0
  private var pendingSave: DispatchWorkItem?
  /// Reads the note again while the window shows, to pick up edits made in another editor.
  private var watch: Timer?
  /// Clicks in other apps while the window shows.
  private var clickWatch: Any?
  /// What the last tick read, so a file read halfway through being written isn't taken.
  private var lastSeen: String?
  private static let lastNoteKey = "lastNote"
  private static let autoSizingKey = "notesWindowAutoSizing"
  private static let hiddenWhileSharingKey = "notesHiddenWhileSharing"
  private static let zoomKey = "notesZoom"
  /// Where the window's top left was last, as Raycast Notes reopens where it was moved to.
  private static let placeKey = "notesWindowTopLeft"
  private static let saveDelay = 0.6

  /// Raycast Notes' window, measured: 396pt wide, 144pt tall empty, 39pt in from the right of
  /// the screen and 100pt down from its top, growing down as the note does.
  private static let width: CGFloat = 396
  private static let minHeight: CGFloat = 144
  private static let inset = (right: CGFloat(39), top: CGFloat(100))

  private lazy var window: NotesPanel = {
    let window = NotesPanel(
      contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.minHeight),
      styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    // A unified toolbar's title bar puts the traffic lights where Raycast Notes has them.
    window.toolbar = NSToolbar()
    window.toolbarStyle = .unified
    window.isReleasedWhenClosed = false
    window.isFloatingPanel = true
    window.level = .floating
    window.hidesOnDeactivate = false
    window.isMovableByWindowBackground = true
    window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    let content = NSHostingView(
      rootView: NotesView(
        model: model, onCreate: { [weak self] in self?.create() },
        onBrowse: { [weak self] in self?.browse() },
        onTextChange: { [weak self] in self?.scheduleSave() },
        onReload: { [weak self] in self?.reload() },
        onSaveAsNew: { [weak self] in self?.saveAsNew() },
        onActions: { [weak self] in self?.showActions() },
        onFormat: { [weak self] in self?.showFormats() },
        onTextHeight: { [weak self] in self?.fit(textHeight: $0) },
        onHover: { [weak self] in self?.hover($0) }))
    // The window's size follows the note, not the view's ideal size.
    content.sizingOptions = []
    // The title bar's and the corners' safe areas aren't the view's: it lays out from edge to
    // edge, as Raycast Notes does.
    content.safeAreaRegions = []
    window.contentView = content
    window.delegate = self
    window.onEscape = { [weak self] in self?.hide() }
    window.onKeyEquivalent = { [weak self] in self?.runShortcut($0) ?? false }
    window.sharingType = Self.isHiddenWhileSharing ? .none : .readOnly
    if !Self.isAutoSizing { window.styleMask.insert(.resizable) }
    Self.showTrafficLights(false, of: window)
    return window
  }()

  private lazy var actionsPanel: NotesActionsPanel = {
    let panel = NotesActionsPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isFloatingPanel = true
    // Over the note's window, which floats too.
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.contentViewController = actionsContent
    panel.delegate = self
    panel.onEscape = { [weak self] in self?.closeActions() }
    return panel
  }()

  private lazy var actionsContent = NSHostingController(
    rootView: NotesActionsView(
      model: actionsModel, onRun: { [weak self] in self?.run($0) },
      onClose: { [weak self] in self?.closeActions() }))

  private static var isAutoSizing: Bool {
    UserDefaults.standard.object(forKey: autoSizingKey) as? Bool ?? true
  }

  private static var isHiddenWhileSharing: Bool {
    UserDefaults.standard.bool(forKey: hiddenWhileSharingKey)
  }

  init(store: NoteStore) {
    self.store = store
    // The note open last time, else the most recent, else a new one.
    let last = UserDefaults.standard.string(forKey: Self.lastNoteKey)
      .flatMap { store.read(URL(fileURLWithPath: $0)) }
    model = NotesModel(note: last ?? store.list().first ?? store.newNote())
    let zoom = UserDefaults.standard.double(forKey: Self.zoomKey)
    model.zoom = zoom > 0 ? zoom : 1
  }

  /// Raycast Notes' actions that Ripcord has: what ⌘K lists and what their keys run.
  private var actions: [NotesAction] {
    [
      NotesAction(
        title: "New Note", symbol: "plus", keys: ["n"], modifiers: .command,
        run: { [weak self] in self?.create() }),
      NotesAction(
        title: "Duplicate Note", symbol: "plus.square.on.square", keys: ["d"], modifiers: .command,
        run: { [weak self] in self?.duplicate() }),
      NotesAction(
        title: "Browse Notes", symbol: "rectangle.stack", keys: ["p"], modifiers: .command,
        run: { [weak self] in self?.browse() }),
      NotesAction(
        title: "Find in Note", symbol: "magnifyingglass", keys: ["f"], modifiers: .command,
        startsSection: true, run: { [weak self] in self?.find() }),
      NotesAction(
        title: "Format…", symbol: "textformat", keys: [","], modifiers: [.command, .shift],
        keyCode: kVK_ANSI_Comma, startsSection: true, keepsPanelOpen: true,
        run: { [weak self] in self?.showFormats() }),
      NotesAction(
        title: Self.isAutoSizing ? "Disable Window Auto-Sizing" : "Enable Window Auto-Sizing",
        symbol: "macwindow", keys: ["/"], modifiers: [.command, .shift], keyCode: kVK_ANSI_Slash,
        startsSection: true, run: { [weak self] in self?.toggleAutoSizing() }),
      NotesAction(
        title: Self.isHiddenWhileSharing
          ? "Show While Screen Sharing" : "Hide While Screen Sharing",
        symbol: "eye.slash", keys: ["h"], modifiers: [.command, .shift],
        run: { [weak self] in self?.toggleHiddenWhileSharing() }),
      NotesAction(
        title: "Actual Size", symbol: "1.magnifyingglass", keys: ["0"], modifiers: .command,
        isEnabled: model.zoom != 1, startsSection: true, run: { [weak self] in self?.zoom(to: 1) }
      ),
      NotesAction(
        title: "Zoom In", symbol: "plus.magnifyingglass", keys: ["+", "="], modifiers: .command,
        isEnabled: model.zoom < Self.zoomRange.upperBound,
        run: { [weak self] in self?.zoom(by: 1.1) }),
      NotesAction(
        title: "Zoom Out", symbol: "minus.magnifyingglass", keys: ["-"], modifiers: .command,
        isEnabled: model.zoom > Self.zoomRange.lowerBound,
        run: { [weak self] in self?.zoom(by: 1 / 1.1) }),
      NotesAction(
        title: "Open Notes Settings", symbol: "gearshape", keys: [","], modifiers: .command,
        startsSection: true, run: { [weak self] in self?.onSettings() }),
      NotesAction(
        title: "Delete Note", symbol: "trash", keys: ["x"], modifiers: .control,
        isDestructive: true, startsSection: true, run: { [weak self] in self?.deleteNote() }),
    ]
  }

  private static let zoomRange: ClosedRange<CGFloat> = 0.6...2

  /// Raycast Notes' Format as…, with its keys.
  private var formats: [NotesAction] {
    func inline(
      _ title: String, _ symbol: String, _ style: MarkdownSpan.Style, _ open: String,
      _ close: String, key: String, _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NotesAction {
      NotesAction(
        title: title, symbol: symbol, keys: [key], modifiers: modifiers,
        run: { [weak self] in self?.editor?.toggleInline(style, open: open, close: close) })
    }
    func lines(
      _ title: String, _ symbol: String, _ format: MarkdownEditing.LineFormat, key: String,
      keyCode: Int, section: String? = nil
    ) -> NotesAction {
      NotesAction(
        title: title, symbol: symbol, keys: [key], modifiers: [.command, .shift],
        keyCode: keyCode, section: section,
        run: { [weak self] in self?.editor?.toggleLines(format) })
    }
    return [
      NotesAction(
        title: "Heading…", symbol: "textformat.size", keys: [], modifiers: [], section: "Inline",
        keepsPanelOpen: true, run: { [weak self] in self?.showHeadings() }),
      inline("Bold", "bold", .bold, "**", "**", key: "b"),
      inline("Italic", "italic", .italic, "*", "*", key: "i"),
      inline("Strikethrough", "strikethrough", .strike, "~~", "~~", key: "s", [.command, .shift]),
      inline("Underline", "underline", .underline, "<u>", "</u>", key: "u"),
      inline("Code", "chevron.left.forwardslash.chevron.right", .code, "`", "`", key: "e"),
      inline("Link", "link", .link, "[", "]()", key: "l"),
      NotesAction(
        title: "Code Block", symbol: "curlybraces.square", keys: ["c"],
        modifiers: [.command, .option], section: "Block",
        run: { [weak self] in self?.editor?.toggleCodeBlock() }),
      lines("Blockquote", "text.quote", .quote, key: "b", keyCode: kVK_ANSI_B),
      lines(
        "Ordered List", "list.number", .ordered, key: "7", keyCode: kVK_ANSI_7, section: "List"),
      lines("Bullet List", "list.bullet", .bullet, key: "8", keyCode: kVK_ANSI_8),
      lines("Task List", "checklist", .task, key: "9", keyCode: kVK_ANSI_9),
    ]
  }

  /// Heading…'s levels, in the same panel.
  private func showHeadings() {
    actionsModel.actions = (1...3).map { level in
      NotesAction(
        title: "Heading \(level)", symbol: "textformat.size", keys: [], modifiers: [],
        run: { [weak self] in self?.editor?.toggleLines(.heading(level)) })
    }
    actionsModel.placeholder = "Heading…"
    actionsModel.filter = ""
  }

  /// The note's text view, to format.
  private var editor: NoteTextView? {
    func find(in view: NSView) -> NoteTextView? {
      if let editor = view as? NoteTextView { return editor }
      return view.subviews.lazy.compactMap(find).first
    }
    return window.contentView.flatMap(find)
  }

  /// ⌘K opens the actions; the others run theirs.
  private func runShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
      showActions()
      return true
    }
    guard let action = (actions + formats).first(where: { $0.matches(event) }) else {
      return false
    }
    if action.isEnabled { action.run() } else { NSSound.beep() }
    return true
  }

  /// Raycast Notes' ⌘K panel, below the buttons and over the note.
  private func showActions() {
    actionsModel.actions = actions
    actionsModel.placeholder = "Search for actions…"
    actionsModel.filter = ""
    openPanel()
  }

  /// The T button's Format as…, in the same panel.
  private func showFormats() {
    actionsModel.actions = formats
    actionsModel.placeholder = "Format as…"
    actionsModel.filter = ""
    openPanel()
  }

  private func openPanel() {
    let content = actionsContent.sizeThatFits(
      in: NSSize(width: NotesActionsView.width, height: .greatestFiniteMagnitude))
    let frame = window.frame
    actionsPanel.setContentSize(content)
    actionsPanel.setFrameTopLeftPoint(
      NSPoint(x: frame.maxX - 38 - content.width, y: frame.maxY - 50))
    // Hidden from screen sharing along with the note.
    actionsPanel.sharingType = window.sharingType
    window.addChildWindow(actionsPanel, ordered: .above)
    actionsPanel.makeKeyAndOrderFront(nil)
  }

  private func closeActions() {
    guard actionsPanel.isVisible else { return }
    window.removeChildWindow(actionsPanel)
    actionsPanel.orderOut(nil)
    window.makeKey()
  }

  private func run(_ action: NotesAction) {
    if !action.keepsPanelOpen { closeActions() }
    action.run()
  }

  private func duplicate() {
    guard flushed() else { return NSSound.beep() }
    do {
      show(try store.save(model.text, over: store.newNote()))
    } catch {
      model.problem = error.localizedDescription
    }
  }

  /// The editor's find bar, as ⌘F shows it in a text view.
  private func find() {
    bringForward()
    DispatchQueue.main.async {
      let item = NSMenuItem()
      item.tag = NSTextFinder.Action.showFindInterface.rawValue
      NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
    }
  }

  private func toggleAutoSizing() {
    UserDefaults.standard.set(!Self.isAutoSizing, forKey: Self.autoSizingKey)
    // Without auto-sizing, the window is sized by hand.
    if Self.isAutoSizing {
      window.styleMask.remove(.resizable)
      fit(textHeight: textHeight)
    } else {
      window.styleMask.insert(.resizable)
    }
  }

  private func toggleHiddenWhileSharing() {
    UserDefaults.standard.set(!Self.isHiddenWhileSharing, forKey: Self.hiddenWhileSharingKey)
    window.sharingType = Self.isHiddenWhileSharing ? .none : .readOnly
  }

  private func zoom(by factor: CGFloat) {
    zoom(to: model.zoom * factor)
  }

  private func zoom(to scale: CGFloat) {
    let clamped = min(max(scale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    // Back to exactly 1 when a step lands near it, so Actual Size reads as such.
    model.zoom = abs(clamped - 1) < 0.01 ? 1 : clamped
    UserDefaults.standard.set(model.zoom, forKey: Self.zoomKey)
  }

  /// Moves the note to the Trash, as Delete Note does in Raycast.
  private func deleteNote() {
    let note = model.note
    pendingSave?.cancel()
    pendingSave = nil
    do {
      try store.trash(note)
    } catch {
      return NSSound.beep()
    }
    show(store.list().first { $0.url != note.url } ?? store.newNote())
  }

  func handle(_ request: NotesRequest) {
    switch request {
    case .toggle:
      if window.isVisible && window.isKeyWindow { return hide() }
      // Back to the note as it is on disk, in case it changed while hidden.
      if !window.isVisible, model.note.isSaved, model.text == model.note.text,
        let fresh = store.read(model.note.url)
      {
        show(fresh)
      } else {
        bringForward()
      }
    case .create: create()
    case .open(let url):
      // Saved first, so the note read back is what's typed when it's this one.
      guard flushed(), let note = store.read(url) else { return NSSound.beep() }
      show(note)
    case .deleted(let url):
      guard model.note.url == url else { return }
      // Its text is in the Trash now; nothing is left to save. The launcher keeps the keys.
      pendingSave?.cancel()
      pendingSave = nil
      show(store.list().first ?? store.newNote(), focusing: false)
    }
  }

  /// Saves first, so Search Notes lists what's typed.
  private func browse() {
    flush()
    onBrowse()
  }

  /// Saves what's typed; false when it couldn't be, so the note isn't left and the text lost.
  private func flushed() -> Bool {
    flush()
    if model.problem != nil { bringForward() }
    return model.problem == nil
  }

  /// On quitting: what couldn't be saved over a note changed outside is kept as a new one.
  func flushForQuit() {
    flush()
    if model.problem != nil { saveAsNew() }
  }

  /// Saves what's typed now, as on switching notes, closing the window or quitting.
  func flush() {
    pendingSave?.cancel()
    pendingSave = nil
    // A note changed outside keeps failing here, unwritten, until Reload or Save as New Note.
    do {
      model.note = try store.save(model.text, over: model.note)
      model.problem = nil
      if model.note.isSaved {
        UserDefaults.standard.set(model.note.url.path, forKey: Self.lastNoteKey)
      }
    } catch {
      model.problem = error.localizedDescription
    }
  }

  private func create() {
    guard flushed() else { return NSSound.beep() }
    show(store.newNote())
  }

  private func show(_ note: Note, focusing: Bool = true) {
    model.note = note
    model.text = note.text
    model.problem = nil
    if note.isSaved { UserDefaults.standard.set(note.url.path, forKey: Self.lastNoteKey) }
    if focusing { bringForward() }
  }

  private func bringForward() {
    if !window.isVisible { place() }
    window.orderFrontRegardless()
    window.makeKey()
    startWatching()
    // Once it's key, so the editor can take the focus.
    DispatchQueue.main.async { [model] in model.focusRequest += 1 }
  }

  /// At the top right of the screen with the pointer, where Ripcord was asked from, as Raycast
  /// Notes opens on the screen it's run on.
  private func place() {
    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? .main
    else { return }
    let size = window.frame.size
    // Where it was moved to, when that's on this screen; else this screen's top right.
    if let saved = UserDefaults.standard.string(forKey: Self.placeKey).map(NSPointFromString),
      screen.visibleFrame.contains(saved)
    {
      return window.setFrameTopLeftPoint(saved)
    }
    window.setFrameOrigin(
      NSPoint(
        x: screen.visibleFrame.maxX - Self.inset.right - size.width,
        y: screen.frame.maxY - Self.inset.top - size.height))
  }

  func windowDidMove(_ notification: Notification) {
    guard notification.object as? NSWindow === window else { return }
    let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
    UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: Self.placeKey)
  }

  /// As tall as the note, top edge kept, up to the screen's bottom, as Raycast Notes grows.
  private func fit(textHeight: CGFloat) {
    self.textHeight = textHeight
    guard Self.isAutoSizing else { return }
    let chrome = NotesView.headerHeight + NotesView.footerHeight
    let screen = window.screen ?? .main
    let top = window.frame.maxY
    let lowest = (screen?.visibleFrame.minY ?? 0) + Self.inset.right
    let height = min(max(textHeight + chrome, Self.minHeight), max(top - lowest, Self.minHeight))
    guard abs(height - window.frame.height) > 0.5 else { return }
    window.setFrame(
      NSRect(x: window.frame.minX, y: top - height, width: window.frame.width, height: height),
      display: true)
  }

  /// The traffic lights show with the other buttons, only while the pointer is over the window.
  private func hover(_ isHovered: Bool) {
    model.isHovered = isHovered
    Self.showTrafficLights(isHovered, of: window)
  }

  private static func showTrafficLights(_ shown: Bool, of window: NSWindow) {
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(button)?.isHidden = !shown
    }
  }

  private func hide() {
    flush()
    window.orderOut(nil)
    stopWatching()
  }

  private func startWatching() {
    // A click in another app that leaves this window taking the keys: another app's floating
    // window, such as Raycast Notes, doesn't bring its app forward, so nothing else would make
    // this one give them up.
    if clickWatch == nil {
      clickWatch = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
        [weak self] _ in
        // After the click has had its effect, as a normal app coming forward takes the keys.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          MainActor.assumeIsolated { self?.giveUpKeys() }
        }
      }
    }
    guard watch == nil else { return }
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.pickUpOutsideEdit() }
    }
    timer.tolerance = 0.5
    // Also while scrolling or resizing, which run the loop in another mode.
    RunLoop.main.add(timer, forMode: .common)
    watch = timer
  }

  private func stopWatching() {
    watch?.invalidate()
    watch = nil
    if let clickWatch { NSEvent.removeMonitor(clickWatch) }
    clickWatch = nil
  }

  /// Still shown, no longer taking the keys.
  private func giveUpKeys() {
    guard window.isVisible, window.isKeyWindow else { return }
    if actionsPanel.isVisible {
      window.removeChildWindow(actionsPanel)
      actionsPanel.orderOut(nil)
    }
    // Japanese still being composed is kept as typed, as moving to another app keeps it.
    if let editor, editor.hasMarkedText() {
      editor.unmarkText()
      editor.inputContext?.discardMarkedText()
      editor.didChangeText()
    }
    // The keys go to an unseen window for a moment, and on to the window that was clicked as
    // it closes, so this one stays on screen without blinking.
    window.refusesKey = true
    defer { window.refusesKey = false }
    keyHandoff.orderFrontRegardless()
    keyHandoff.makeKey()
    keyHandoff.orderOut(nil)
  }

  /// Off screen and clear, only ever key for the moment ``giveUpKeys()`` hands the keys over.
  private lazy var keyHandoff: NotesPanel = {
    let panel = NotesPanel(
      contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.alphaValue = 0
    panel.isReleasedWhenClosed = false
    return panel
  }()

  /// Shows what another editor saved to this note, while nothing typed here is waiting to be
  /// saved; with something typed, saving refuses to write over it and says so instead.
  private func pickUpOutsideEdit() {
    guard window.isVisible, pendingSave == nil, model.problem == nil, model.note.isSaved,
      model.text == model.note.text,
      // Not over Japanese still being composed, which isn't in the text yet.
      (window.firstResponder as? NSTextView)?.hasMarkedText() != true,
      let fresh = store.read(model.note.url), fresh.text != model.note.text
    else {
      lastSeen = nil
      return
    }
    // Taken once two reads agree: an editor writing in place may be halfway through.
    defer { lastSeen = fresh.text }
    guard fresh.text == lastSeen else { return }
    model.note = fresh
    model.text = fresh.text
  }

  private func scheduleSave() {
    pendingSave?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.flush() }
    pendingSave = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
  }

  /// The note as it is on disk now, dropping what was typed since it changed there.
  private func reload() {
    guard let fresh = store.read(model.note.url) else {
      return show(store.list().first ?? store.newNote())
    }
    show(fresh)
  }

  /// What was typed, kept as a note of its own, leaving the changed file as it is.
  private func saveAsNew() {
    let text = model.text
    model.note = store.newNote()
    model.problem = nil
    model.text = text
    flush()
  }

  /// The actions close when something else is clicked, as a menu does.
  func windowDidResignKey(_ notification: Notification) {
    guard notification.object as? NSWindow === actionsPanel, actionsPanel.isVisible else { return }
    window.removeChildWindow(actionsPanel)
    actionsPanel.orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) {
    flush()
    stopWatching()
  }
}

/// A panel that can take keys while another app stays in front.
final class NotesPanel: NSPanel {
  var onEscape: () -> Void = {}
  /// The note's actions' keys, as ⌘K lists them; true when one ran.
  var onKeyEquivalent: (NSEvent) -> Bool = { _ in false }
  /// Set while the keys are handed away, so AppKit doesn't give them straight back.
  var refusesKey = false

  override var canBecomeKey: Bool { !refusesKey }

  override func cancelOperation(_ sender: Any?) {
    onEscape()
  }

  /// Ripcord has no Edit menu in front, so ⌘X/C/V/A/Z are passed to the editor by hand, as the
  /// launcher passes them to its fields.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    let key = event.charactersIgnoringModifiers?.lowercased()
    let editing = [
      "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
      "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
    ]
    if flags == .command, let selector = key.flatMap({ editing[$0] }) {
      return NSApp.sendAction(selector, to: nil, from: self)
    }
    if key == "z", flags == .command || flags == [.command, .shift] {
      return NSApp.sendAction(
        flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:")), to: nil, from: self)
    }
    if onKeyEquivalent(event) { return true }
    return super.performKeyEquivalent(with: event)
  }
}

private struct NotesView: View {
  @Bindable var model: NotesModel
  let onCreate: () -> Void
  let onBrowse: () -> Void
  let onTextChange: () -> Void
  let onReload: () -> Void
  let onSaveAsNew: () -> Void
  let onActions: () -> Void
  let onFormat: () -> Void
  let onTextHeight: (CGFloat) -> Void
  let onHover: (Bool) -> Void

  /// Raycast Notes' title bar and footer, measured.
  static let headerHeight: CGFloat = 52
  static let footerHeight: CGFloat = 48

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Text(Note.title(of: model.text))
          .font(.system(size: 13))
          .foregroundStyle(model.isHovered ? .secondary : .tertiary)
          .lineLimit(1)
          // Clear of the traffic lights and the buttons.
          .padding(.horizontal, 100)
        HStack(spacing: 0) {
          Spacer()
          HStack(spacing: 0) {
            button("command", help: "Actions (⌘K)", action: onActions)
            button("rectangle.stack", help: "Browse Notes (⌘P)", action: onBrowse)
            button("plus", help: "New Note (⌘N)", action: onCreate)
          }
          .padding(.horizontal, 6)
          .frame(height: 34)
          .glassEffect(.regular.interactive(), in: Capsule())
          .opacity(model.isHovered ? 1 : 0)
        }
        .padding(.trailing, 8)
      }
      .frame(height: Self.headerHeight)
      if let problem = model.problem {
        HStack(spacing: 8) {
          Text(problem).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
          Button("Reload", action: onReload)
          Button("Save as New Note", action: onSaveAsNew)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.15))
      }
      MarkdownEditor(
        text: $model.text, noteURL: model.note.url, focusRequest: model.focusRequest,
        zoom: model.zoom, onChange: onTextChange, onHeight: onTextHeight)
      ZStack {
        Text("\(Self.shownCount(of: model.text)) characters")
          .font(.system(size: 13))
          .foregroundStyle(.tertiary)
        HStack {
          Spacer()
          // Raycast Notes' Format button, a serif T.
          Button(action: onFormat) {
            Text("T")
              .font(.system(size: 17, design: .serif))
              .frame(width: 32, height: 32)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .help("Format… (⇧⌘,)")
          .glassEffect(.regular.interactive(), in: Circle())
          .opacity(model.isHovered ? 1 : 0)
        }
        .padding(.trailing, 8)
      }
      .frame(height: Self.footerHeight)
    }
    .background(.regularMaterial)
    .onHover(perform: onHover)
  }

  /// The characters the editor shows: hidden marks aren't counted.
  static func shownCount(of text: String) -> Int {
    let hidden = MarkdownEditing.hidden(in: MarkdownSpan.spans(in: text))
    return text.count - hidden.reduce(0) { $0 + $1.length }
  }

  /// The window's keys run these, through its actions.
  private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Glyph(symbol, pointSize: 17).frame(width: 27, height: 28)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .help(help)
  }
}

extension NSAttributedString.Key {
  /// A Markdown mark the editor hides, as Raycast Notes does once it's complete: drawn clear and
  /// next to no width. Its value is the font it would have, which what's typed after it takes.
  fileprivate static let hiddenMark = NSAttributedString.Key("RipcordHiddenMark")
}

extension [NSAttributedString.Key: Any] {
  /// As typing attributes: a hidden mark's own look given back, so what's typed shows.
  fileprivate var shown: Self {
    guard let font = self[.hiddenMark] else { return self }
    var shown = filter { $0.key != .hiddenMark }
    shown[.font] = font
    shown[.foregroundColor] = NSColor.labelColor
    return shown
  }
}

/// The note's editor: an NSTextView that formats Markdown as you type. Its marks stay in the
/// text, so the file is exactly what's typed; a heading's and emphasis's are hidden once complete,
/// as in Raycast Notes, and a list's or quote's dimmed. Formatting waits while an input method is
/// composing.
private struct MarkdownEditor: NSViewRepresentable {
  @Binding var text: String
  /// Which note the text is: the same one changed elsewhere keeps the caret and scroll.
  let noteURL: URL
  /// Bumped to put the caret in the editor.
  let focusRequest: Int
  /// Zoom In and Zoom Out's scale.
  let zoom: CGFloat
  let onChange: () -> Void
  /// How tall the text is laid out, for the window to fit it.
  let onHeight: (CGFloat) -> Void

  static let fontSize: CGFloat = 14

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    // A thin scroller shown while scrolling, as the rest of Ripcord draws them.
    scrollView.scrollerStyle = .overlay
    scrollView.autohidesScrollers = true
    // The text starts where Raycast Notes' does, not pushed below the title bar again.
    scrollView.automaticallyAdjustsContentInsets = false
    // macOS puts its own style back when the scroll bar setting changes.
    context.coordinator.scrollerObserver = NotificationCenter.default.addObserver(
      forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
    ) { [weak scrollView] _ in
      MainActor.assumeIsolated { scrollView?.scrollerStyle = .overlay }
    }
    // TextKit 1, whose layout manager places the empty headings' placeholders.
    let textView = NoteTextView(usingTextLayoutManager: false)
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = .width
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: 0, height: CGFloat.greatestFiniteMagnitude)
    scrollView.documentView = textView
    textView.delegate = context.coordinator
    textView.drawsBackground = false
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    // The window grows to keep the text in view under ⌘F's find bar.
    context.coordinator.findBarObservation = scrollView.observe(\.isFindBarVisible) {
      [weak textView, coordinator = context.coordinator] _, _ in
      MainActor.assumeIsolated {
        if let textView { coordinator.reportHeight(of: textView) }
      }
    }
    scrollView.allowsMagnification = true
    scrollView.magnification = zoom
    // Raycast Notes' margins: 24pt from the sides, text 65pt from the window's top.
    textView.textContainerInset = NSSize(width: 19, height: 13)
    textView.font = .systemFont(ofSize: Self.fontSize)
    textView.typingAttributes = Self.base
    textView.string = text
    Self.format(textView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = scrollView.documentView as? NSTextView else { return }
    // Another note shown, or reloaded: what was being composed for the old one is dropped, and
    // so is its undo history, which would replay its edits on this text.
    if textView.string != text {
      let sameNote = context.coordinator.noteURL == noteURL
      let selection = textView.selectedRange()
      let scroll = scrollView.contentView.bounds.origin
      context.coordinator.isReplacing = true
      if textView.hasMarkedText() { textView.inputContext?.discardMarkedText() }
      textView.string = text
      textView.undoManager?.removeAllActions()
      Self.format(textView)
      context.coordinator.isReplacing = false
      if sameNote {
        let length = (text as NSString).length
        textView.setSelectedRange(
          NSRange(location: min(selection.location, length), length: 0))
        scrollView.contentView.scroll(to: scroll)
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
    }
    context.coordinator.noteURL = noteURL
    if scrollView.magnification != zoom { scrollView.magnification = zoom }
    context.coordinator.reportHeight(of: textView)
    if context.coordinator.focusRequest != focusRequest {
      context.coordinator.focusRequest = focusRequest
      textView.window?.makeFirstResponder(textView)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MarkdownEditor
    var focusRequest: Int
    /// The editor is being given another note's text: no change of the user's to pass on.
    var isReplacing = false
    var noteURL: URL?
    var scrollerObserver: NSObjectProtocol?
    var findBarObservation: NSKeyValueObservation?
    /// Text is going in, so the caret that follows it may stay before a style's closing marks:
    /// what's typed after ⌘B with nothing selected stays bold.
    private var isTyping = false

    isolated deinit {
      if let scrollerObserver { NotificationCenter.default.removeObserver(scrollerObserver) }
    }

    init(parent: MarkdownEditor) {
      self.parent = parent
      focusRequest = parent.focusRequest
      noteURL = parent.noteURL
    }

    func textDidChange(_ notification: Notification) {
      guard !isReplacing, let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
      parent.onChange()
      if !textView.hasMarkedText() { MarkdownEditor.format(textView) }
      reportHeight(of: textView)
    }

    /// Laid out first, then passed on after this update, as resizing the window lays it out
    /// again.
    func reportHeight(of textView: NSTextView) {
      guard let layoutManager = textView.layoutManager, let container = textView.textContainer
      else { return }
      layoutManager.ensureLayout(for: container)
      let scrollView = textView.enclosingScrollView
      let findBar =
        scrollView?.isFindBarVisible == true ? scrollView?.findBarView?.frame.height ?? 0 : 0
      let height =
        (layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2)
        * (scrollView?.magnification ?? 1) + findBar
      let onHeight = parent.onHeight
      DispatchQueue.main.async { onHeight(height) }
    }

    /// The caret, or the end of a selection that moved, steps over hidden marks as if they
    /// weren't there.
    func textView(
      _ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange,
      toCharacterRange new: NSRange
    ) -> NSRange {
      guard !isReplacing, !textView.hasMarkedText() else { return new }
      let text = textView.string
      let spans = MarkdownSpan.spans(in: text)
      let hidden = MarkdownEditing.hidden(in: spans)
      let stops = MarkdownEditing.stops(in: spans)
      guard new.length > 0 else {
        if isTyping,
          MarkdownSpan.spans(in: text).contains(where: {
            $0.marks.count == 2 && $0.marks[1].location == new.location
          })
        {
          return new
        }
        // ↑ from below a code block is offered the line after its hidden fence; it goes up to
        // the end of the block's last line instead.
        if NSApp.currentEvent?.type == .keyDown, NSApp.currentEvent?.keyCode == UInt16(kVK_UpArrow),
          let stop = stops.first(where: { stop in
            hidden.contains { $0.location == stop && NSMaxRange($0) == new.location }
          })
        {
          return NSRange(location: stop, length: 0)
        }
        let location = MarkdownEditing.caret(
          new.location, from: old.location + old.length, in: text, hidden: hidden, stops: stops)
        return NSRange(location: location, length: 0)
      }
      // A selection made in one go (⌘A, a drag) takes in a line's hidden mark; Shift and an
      // arrow step over marks as the caret does.
      let isStep =
        abs(new.location - old.location) <= 2 && abs(NSMaxRange(new) - NSMaxRange(old)) <= 2
      guard isStep else {
        return MarkdownEditing.outward(new, spans: MarkdownSpan.spans(in: text))
      }
      var start = new.location
      var end = NSMaxRange(new)
      if start != old.location {
        start = MarkdownEditing.caret(
          start, from: old.location, in: text, hidden: hidden, stops: stops)
      }
      if end != NSMaxRange(old) {
        end = MarkdownEditing.caret(
          end, from: NSMaxRange(old), in: text, hidden: hidden, stops: stops)
      }
      return end > start ? NSRange(location: start, length: end - start) : new
    }

    /// Cuts, word and line deletes, and typing over a selection leave no stray marks.
    func textView(
      _ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?
    ) -> Bool {
      if !isReplacing, replacementString != nil {
        isTyping = true
        // Over once this edit and the caret move after it are done.
        DispatchQueue.main.async { [weak self] in self?.isTyping = false }
      }
      guard !isReplacing, let replacementString, let textView = textView as? NoteTextView,
        !textView.isTidying, !textView.hasMarkedText(),
        let tidy = MarkdownEditing.tidy(
          range, replacement: replacementString, in: textView.string,
          spans: MarkdownSpan.spans(in: textView.string))
      else { return true }
      textView.replace(
        tidy.range, with: tidy.replacement, selecting: NSRange(location: tidy.caret, length: 0))
      return false
    }

    /// What's typed next never takes a hidden mark's look, or it would be drawn as nothing.
    func textView(
      _ textView: NSTextView, shouldChangeTypingAttributes old: [String: Any],
      toAttributes new: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
      new.shown
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      guard let textView = textView as? NoteTextView, !textView.hasMarkedText() else {
        return false
      }
      let selection = textView.selectedRange()
      let text = textView.string
      switch selector {
      case #selector(NSResponder.deleteBackward(_:)) where selection.length == 0:
        return textView.apply(
          MarkdownEditing.deleteBackward(
            at: selection.location, in: text, spans: MarkdownSpan.spans(in: text)))
      case #selector(NSResponder.deleteForward(_:)) where selection.length == 0:
        return textView.apply(
          MarkdownEditing.deleteForward(
            at: selection.location, in: text, spans: MarkdownSpan.spans(in: text)))
      case #selector(NSResponder.insertNewline(_:))
      where NSApp.currentEvent?.modifierFlags.contains(.shift) != true:
        // Return continues a list, task or quote, and ends it on an empty item.
        guard selection.length == 0,
          let edit = MarkdownEditing.newline(
            at: selection.location, in: text, spans: MarkdownSpan.spans(in: text))
        else { return false }
        textView.replace(
          edit.range, with: edit.replacement, selecting: NSRange(location: edit.caret, length: 0))
        return true
      case #selector(NSResponder.insertNewline(_:)):
        // Return ends a heading; Shift-Return starts another of the same level, as in Raycast.
        guard
          let prefix = MarkdownSpan.spans(in: text).first(where: {
            if case .heading = $0.style {
              return NSLocationInRange(selection.location, $0.range)
                || NSMaxRange($0.range) == selection.location
            }
            return false
          })?.marks.first
        else { return false }
        textView.insertText(
          "\n" + (text as NSString).substring(with: prefix), replacementRange: selection)
        return true
      default: return false
      }
    }
  }

  fileprivate static var base: [NSAttributedString.Key: Any] {
    [
      .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraph(),
    ]
  }

  /// Where list items' text starts, per level, past the bullet, number or checkbox drawn
  /// before it, as Raycast Notes indents them.
  static let listIndent: CGFloat = 22
  /// A quote's text, past its bar.
  static let quoteIndent: CGFloat = 12
  /// A code block's text, inside its background.
  static let codeInset: CGFloat = 12

  /// Lines a little apart, as Raycast Notes spaces them; `indent` for every line of an item,
  /// and `minimumHeight` for one whose marks are all there is.
  fileprivate static func paragraph(
    indent: CGFloat = 0, tail: CGFloat = 0, minimumHeight: CGFloat = 0, spacing: CGFloat = 6
  ) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.firstLineHeadIndent = indent
    style.headIndent = indent
    style.tailIndent = tail
    style.minimumLineHeight = minimumHeight
    style.paragraphSpacing = spacing
    return style
  }

  /// How deep a list item's mark is: two spaces or a tab a level.
  static func level(of mark: String) -> Int {
    let lead = mark.prefix { $0 == " " || $0 == "\t" }
    return lead.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
  }

  fileprivate static func headingFont(_ level: Int) -> NSFont {
    .systemFont(ofSize: [24, 20, 17][min(level, 3) - 1], weight: .bold)
  }

  /// Sets every character's look from the Markdown; the text itself is left as it is.
  static func format(_ textView: NSTextView) {
    guard let storage = textView.textStorage else { return }
    let whole = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.setAttributes(base, range: whole)
    for span in MarkdownSpan.spans(in: storage.string)
    where NSMaxRange(span.range) <= storage.length {
      storage.addAttributes(attributes(for: span, in: storage), range: span.range)
    }
    // A closed block's hidden fence lines leave room above and below its background.
    let string = storage.string as NSString
    for span in MarkdownSpan.spans(in: storage.string) where span.style == .fenced {
      for mark in span.marks {
        let fence = string.range(of: "```", range: mark)
        guard fence.location != NSNotFound else { continue }
        storage.addAttribute(
          .paragraphStyle, value: paragraph(spacing: 14),
          range: string.lineRange(for: NSRange(location: fence.location, length: 0)))
      }
    }
    storage.endEditing()
    textView.needsDisplay = true
    // What's typed next looks like the text before the caret: a heading's size even while an
    // input method composes, and plain after a closing `**`.
    let caret = textView.selectedRange().location
    textView.typingAttributes =
      caret > 0 && caret <= storage.length
      ? storage.attributes(at: caret - 1, effectiveRange: nil).shown.filter {
        $0.key != .strikethroughStyle
      } : base
  }

  private static func attributes(for span: MarkdownSpan, in storage: NSTextStorage)
    -> [NSAttributedString.Key: Any]
  {
    let font =
      storage.attribute(.font, at: span.range.location, effectiveRange: nil) as? NSFont
      ?? .systemFont(ofSize: fontSize)
    let lineHeight = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: fontSize))
    switch span.style {
    case .heading(let level):
      // As tall as the heading even when its marks are all there is.
      return [
        .font: headingFont(level),
        .paragraphStyle: paragraph(
          minimumHeight: NSLayoutManager().defaultLineHeight(for: headingFont(level))),
      ]
    case .bullet, .ordered, .task:
      let mark = span.marks.first.map { (storage.string as NSString).substring(with: $0) } ?? ""
      return [
        .paragraphStyle: paragraph(
          indent: listIndent * CGFloat(level(of: mark) + 1), minimumHeight: lineHeight)
      ]
    case .quote:
      return [.paragraphStyle: paragraph(indent: quoteIndent, minimumHeight: lineHeight)]
    case .bold:
      return [.font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)]
    case .italic:
      return [.font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)]
    case .strike: return [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
    case .underline: return [.underlineStyle: NSUnderlineStyle.single.rawValue]
    // Its rounded background is drawn by the text view.
    case .code:
      return [.font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)]
    // Inside the block's rounded background, drawn by the text view.
    case .codeBlock:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular),
        .paragraphStyle: paragraph(indent: codeInset, tail: -codeInset, spacing: 0),
      ]
    case .fenced: return [:]
    case .link: return [.foregroundColor: NSColor.linkColor]
    case .done: return [.foregroundColor: NSColor.secondaryLabelColor]
    case .hidden:
      return [
        .hiddenMark: font, .font: NSFont.systemFont(ofSize: 0.01),
        .foregroundColor: NSColor.clear,
      ]
    }
  }
}

/// The note's text view: Raycast Notes' placeholders, its Format as… edits, and deletes that
/// treat hidden marks as one with their text.
final class NoteTextView: NSTextView {
  /// Bold, Italic and the other inline formats on the selected words, or, with nothing
  /// selected, on what's typed next. A link's caret lands between its `()` for the URL.
  func toggleInline(_ style: MarkdownSpan.Style, open: String, close: String) {
    guard !hasMarkedText(),
      let edit = MarkdownEditing.toggle(
        style, open: open, close: close, selection: selectedRange(), in: string,
        spans: MarkdownSpan.spans(in: string))
    else { return NSSound.beep() }
    let addsLink = style == .link && edit.replacement.hasSuffix("]()")
    replace(
      edit.range, with: edit.replacement,
      selecting: addsLink
        ? NSRange(
          location: edit.range.location + (edit.replacement as NSString).length - 1, length: 0)
        : edit.selection)
  }

  /// A heading, quote or list on the lines the selection touches.
  func toggleLines(_ format: MarkdownEditing.LineFormat) {
    guard !hasMarkedText() else { return }
    let edit = MarkdownEditing.toggleLines(format, selection: selectedRange(), in: string)
    replace(edit.range, with: edit.replacement, selecting: edit.selection)
  }

  func toggleCodeBlock() {
    guard !hasMarkedText() else { return }
    let edit = MarkdownEditing.toggleCodeBlock(selection: selectedRange(), in: string)
    replace(edit.range, with: edit.replacement, selecting: edit.selection)
  }

  /// Carries out what a delete key was found to do; true when the key is dealt with.
  func apply(_ delete: MarkdownEditing.Delete) -> Bool {
    switch delete {
    case .normal: return false
    case .nothing: return true
    case .remove(let range):
      replace(range, with: "", selecting: NSRange(location: range.location, length: 0))
      return true
    }
  }

  /// Set while an edit made here is checked, which is already tidy.
  private(set) var isTidying = false

  /// An edit made as typing is, so it's undone with ⌘Z and saved.
  func replace(_ range: NSRange, with replacement: String, selecting selection: NSRange) {
    isTidying = true
    defer { isTidying = false }
    guard shouldChangeText(in: range, replacementString: replacement) else { return }
    textStorage?.replaceCharacters(in: range, with: replacement)
    didChangeText()
    setSelectedRange(selection)
  }

  /// Ripcord's accent, the caret's orange, for bullets, numbers, checkboxes and quote bars.
  private static let accent = FocusingTextField.caretColor

  /// Where a line's first fragment sits, in the view: the marks drawn for it line up with it.
  private func lineRect(at location: Int) -> NSRect? {
    guard let layoutManager else { return nil }
    let glyph = layoutManager.glyphIndexForCharacter(at: location)
    // The used rect: the text's own height, without the space after the paragraph.
    let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
    let origin = textContainerOrigin
    return NSRect(
      x: origin.x + (textContainer?.lineFragmentPadding ?? 0), y: origin.y + used.minY,
      width: used.width, height: used.height)
  }

  /// A task's checkbox, at the start of its line.
  private func checkbox(for span: MarkdownSpan) -> NSRect? {
    guard let mark = span.marks.first, let line = lineRect(at: span.range.location) else {
      return nil
    }
    let indent =
      MarkdownEditor.listIndent
      * CGFloat(MarkdownEditor.level(of: (string as NSString).substring(with: mark)))
    let size: CGFloat = 14
    return NSRect(x: line.minX + indent, y: line.midY - size / 2, width: size, height: size)
  }

  /// Inline code's rounded background and a quote's bar, behind the text.
  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    guard let layoutManager, let textContainer else { return }
    let origin = textContainerOrigin
    for span in MarkdownSpan.spans(in: string) {
      switch span.style {
      case .code:
        let glyphs = layoutManager.glyphRange(
          forCharacterRange: span.range, actualCharacterRange: nil)
        layoutManager.enumerateEnclosingRects(
          forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
          in: textContainer
        ) { box, _ in
          let pill = box.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -3, dy: 0)
          NSColor.labelColor.withAlphaComponent(0.08).setFill()
          NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
        }
      case .fenced:
        // From the block's first line to its last, across the container, with room around.
        guard let first = lineRect(at: span.range.location),
          let last = lineRect(at: max(span.range.location, NSMaxRange(span.range) - 1))
        else { continue }
        let padding = textContainer.lineFragmentPadding
        let box = NSRect(
          x: first.minX, y: first.minY - 7,
          width: textContainer.size.width - padding * 2, height: last.maxY - first.minY + 14)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
      case .quote:
        // From the quote's first line to its last, wrapped lines too.
        guard let first = lineRect(at: span.range.location),
          let last = lineRect(at: max(span.range.location, NSMaxRange(span.range) - 1))
        else { continue }
        let bar = NSRect(x: first.minX, y: first.minY, width: 3, height: last.maxY - first.minY)
        Self.accent.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
      default: continue
      }
    }
  }

  /// "Start writing..." in an empty note, "Heading 1" on a heading with nothing in it yet, and
  /// the bullets, numbers and checkboxes drawn where list items' hidden marks are.
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let origin = textContainerOrigin
    let padding = textContainer?.lineFragmentPadding ?? 0
    let color = NSColor.placeholderTextColor
    let font = NSFont.systemFont(ofSize: MarkdownEditor.fontSize)
    guard !string.isEmpty else {
      ("Start writing..." as NSString).draw(
        at: NSPoint(x: origin.x + padding, y: origin.y),
        withAttributes: [.font: font, .foregroundColor: color])
      return
    }
    guard let layoutManager else { return }
    for span in MarkdownSpan.spans(in: string) {
      guard let mark = span.marks.first else { continue }
      let indent =
        MarkdownEditor.listIndent
        * CGFloat(MarkdownEditor.level(of: (string as NSString).substring(with: mark)))
      switch span.style {
      case .heading(let level) where NSMaxRange(mark) == NSMaxRange(span.range):
        let line = layoutManager.lineFragmentRect(
          forGlyphAt: layoutManager.glyphIndexForCharacter(at: span.range.location),
          effectiveRange: nil)
        ("Heading \(level)" as NSString).draw(
          at: NSPoint(x: origin.x + line.minX + padding, y: origin.y + line.minY),
          withAttributes: [.font: MarkdownEditor.headingFont(level), .foregroundColor: color])
      case .bullet:
        guard let line = lineRect(at: span.range.location) else { continue }
        let dot: CGFloat = 6
        Self.accent.setFill()
        NSBezierPath(
          ovalIn: NSRect(x: line.minX + indent + 5, y: line.midY - dot / 2, width: dot, height: dot)
        ).fill()
      case .ordered:
        guard let line = lineRect(at: span.range.location) else { continue }
        let number = (string as NSString).substring(with: mark).trimmingCharacters(in: .whitespaces)
        let attributes: [NSAttributedString.Key: Any] = [
          .font: NSFont.monospacedDigitSystemFont(
            ofSize: MarkdownEditor.fontSize, weight: .regular),
          .foregroundColor: Self.accent,
        ]
        let size = (number as NSString).size(withAttributes: attributes)
        (number as NSString).draw(
          at: NSPoint(x: line.minX + indent, y: line.midY - size.height / 2),
          withAttributes: attributes)
      case .task(let checked):
        guard let box = checkbox(for: span) else { continue }
        let path = NSBezierPath(
          roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
        Self.accent.set()
        if checked {
          path.fill()
          let tick = NSBezierPath()
          tick.move(to: NSPoint(x: box.minX + 3.5, y: box.midY))
          tick.line(to: NSPoint(x: box.minX + 6, y: box.maxY - 4))
          tick.line(to: NSPoint(x: box.maxX - 3.5, y: box.minY + 4))
          tick.lineWidth = 1.8
          tick.lineCapStyle = .round
          tick.lineJoinStyle = .round
          NSColor.white.setStroke()
          tick.stroke()
        } else {
          path.lineWidth = 1.5
          path.stroke()
        }
      default: continue
      }
    }
  }

  /// A click on a task's checkbox checks or unchecks it.
  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    for span in MarkdownSpan.spans(in: string) {
      guard case .task(let checked) = span.style, let mark = span.marks.first,
        checkbox(for: span)?.insetBy(dx: -3, dy: -3).contains(point) == true
      else { continue }
      let box = (string as NSString).range(of: "[", range: mark)
      guard box.location != NSNotFound else { continue }
      replace(
        NSRange(location: box.location + 1, length: 1), with: checked ? " " : "x",
        selecting: selectedRange())
      return
    }
    super.mouseDown(with: event)
  }
}
