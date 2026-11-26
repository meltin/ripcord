import AppKit
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
  private var pendingSave: DispatchWorkItem?
  /// Reads the note again while the window shows, to pick up edits made in another editor.
  private var watch: Timer?
  private static let lastNoteKey = "lastNote"
  private static let saveDelay = 0.6

  private lazy var window: NotesPanel = {
    let window = NotesPanel(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.isFloatingPanel = true
    window.level = .floating
    window.hidesOnDeactivate = false
    window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    window.minSize = NSSize(width: 300, height: 200)
    window.contentView = NSHostingView(
      rootView: NotesView(
        model: model, onCreate: { [weak self] in self?.create() },
        onBrowse: { [weak self] in self?.browse() },
        onTextChange: { [weak self] in self?.scheduleSave() },
        onReload: { [weak self] in self?.reload() },
        onSaveAsNew: { [weak self] in self?.saveAsNew() }))
    window.delegate = self
    window.onEscape = { [weak self] in self?.hide() }
    window.setFrameAutosaveName("RipcordNotes")
    if !window.setFrameUsingName("RipcordNotes") { window.center() }
    return window
  }()

  init(store: NoteStore) {
    self.store = store
    // The note open last time, else the most recent, else a new one.
    let last = UserDefaults.standard.string(forKey: Self.lastNoteKey)
      .flatMap { store.read(URL(fileURLWithPath: $0)) }
    model = NotesModel(note: last ?? store.list().first ?? store.newNote())
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
    window.orderFrontRegardless()
    window.makeKey()
    startWatching()
    // Once it's key, so the editor can take the focus.
    DispatchQueue.main.async { [model] in model.focusRequest += 1 }
  }

  private func hide() {
    flush()
    window.orderOut(nil)
    stopWatching()
  }

  private func startWatching() {
    guard watch == nil else { return }
    watch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.pickUpOutsideEdit() }
    }
  }

  private func stopWatching() {
    watch?.invalidate()
    watch = nil
  }

  /// Shows what another editor saved to this note, while nothing typed here is waiting to be
  /// saved; with something typed, saving refuses to write over it and says so instead.
  private func pickUpOutsideEdit() {
    guard window.isVisible, pendingSave == nil, model.problem == nil, model.note.isSaved,
      model.text == model.note.text, let fresh = store.read(model.note.url),
      fresh.text != model.note.text
    else { return }
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

  func windowWillClose(_ notification: Notification) {
    flush()
    stopWatching()
  }
}

/// A panel that can take keys while another app stays in front.
final class NotesPanel: NSPanel {
  var onEscape: () -> Void = {}

  override var canBecomeKey: Bool { true }

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

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 4) {
        Text(Note.title(of: model.text))
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
          .frame(maxWidth: .infinity)
          // Clear of the traffic lights, and centered between them and the buttons.
          .padding(.leading, 70)
        button("list.bullet", help: "Browse Notes (⌘P)", key: "p", action: onBrowse)
        button("plus", help: "New Note (⌘N)", key: "n", action: onCreate)
      }
      .padding(.horizontal, 10)
      .frame(height: 30)
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
      MarkdownEditor(text: $model.text, focusRequest: model.focusRequest, onChange: onTextChange)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
    .background(.regularMaterial)
  }

  private func button(
    _ symbol: String, help: String, key: KeyEquivalent, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Glyph(symbol, pointSize: 14).frame(width: 26, height: 24)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .help(help)
    .keyboardShortcut(key, modifiers: .command)
  }
}

/// The note's editor: an NSTextView that formats Markdown as you type, keeping its marks in the
/// text, dimmed. Formatting waits while an input method is composing.
private struct MarkdownEditor: NSViewRepresentable {
  @Binding var text: String
  /// Bumped to put the caret in the editor.
  let focusRequest: Int
  let onChange: () -> Void

  static let fontSize: CGFloat = 14

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    // A thin scroller shown while scrolling, as the rest of Ripcord draws them.
    scrollView.scrollerStyle = .overlay
    scrollView.autohidesScrollers = true
    // macOS puts its own style back when the scroll bar setting changes.
    context.coordinator.scrollerObserver = NotificationCenter.default.addObserver(
      forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
    ) { [weak scrollView] _ in
      MainActor.assumeIsolated { scrollView?.scrollerStyle = .overlay }
    }
    guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
    textView.delegate = context.coordinator
    textView.drawsBackground = false
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.textContainerInset = NSSize(width: 8, height: 6)
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
      context.coordinator.isReplacing = true
      if textView.hasMarkedText() { textView.inputContext?.discardMarkedText() }
      textView.string = text
      textView.undoManager?.removeAllActions()
      Self.format(textView)
      context.coordinator.isReplacing = false
    }
    if context.coordinator.focusRequest != focusRequest {
      context.coordinator.focusRequest = focusRequest
      textView.window?.makeFirstResponder(textView)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MarkdownEditor
    var focusRequest: Int
    /// The editor is being given another note's text: no change of the user's to pass on.
    var isReplacing = false
    var scrollerObserver: NSObjectProtocol?

    deinit {
      if let scrollerObserver { NotificationCenter.default.removeObserver(scrollerObserver) }
    }

    init(parent: MarkdownEditor) {
      self.parent = parent
      focusRequest = parent.focusRequest
    }

    func textDidChange(_ notification: Notification) {
      guard !isReplacing, let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
      parent.onChange()
      if !textView.hasMarkedText() { MarkdownEditor.format(textView) }
    }
  }

  private static var base: [NSAttributedString.Key: Any] {
    [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor]
  }

  /// Sets every character's look from the Markdown; the text itself is left as it is.
  static func format(_ textView: NSTextView) {
    guard let storage = textView.textStorage else { return }
    let whole = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.setAttributes(base, range: whole)
    for span in MarkdownSpan.spans(in: storage.string)
    where NSMaxRange(span.range) <= storage.length {
      storage.addAttributes(
        attributes(for: span.style, at: span.range, in: storage), range: span.range)
    }
    storage.endEditing()
    textView.typingAttributes = base
  }

  private static func attributes(
    for style: MarkdownSpan.Style, at range: NSRange, in storage: NSTextStorage
  ) -> [NSAttributedString.Key: Any] {
    let font =
      storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
      ?? .systemFont(ofSize: fontSize)
    switch style {
    case .heading(let level):
      let size: CGFloat = [22, 18, 16][min(level, 3) - 1]
      return [.font: NSFont.systemFont(ofSize: size, weight: .bold)]
    case .bold:
      return [.font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)]
    case .italic:
      return [.font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)]
    case .code, .codeBlock:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12),
      ]
    case .quote: return [.foregroundColor: NSColor.secondaryLabelColor]
    case .link: return [.foregroundColor: NSColor.linkColor]
    case .done:
      return [
        .foregroundColor: NSColor.secondaryLabelColor,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
      ]
    case .mark: return [.foregroundColor: NSColor.tertiaryLabelColor]
    }
  }
}
