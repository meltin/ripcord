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
  /// The pointer is over the window: its buttons show, as Raycast Notes shows them.
  var isHovered = false

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
  /// What the last tick read, so a file read halfway through being written isn't taken.
  private var lastSeen: String?
  private static let lastNoteKey = "lastNote"
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
    Self.showTrafficLights(false, of: window)
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
    window.setFrameOrigin(
      NSPoint(
        x: screen.visibleFrame.maxX - Self.inset.right - size.width,
        y: screen.frame.maxY - Self.inset.top - size.height))
  }

  /// As tall as the note, top edge kept, up to the screen's bottom, as Raycast Notes grows.
  private func fit(textHeight: CGFloat) {
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
  }

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
    if let editor = firstResponder as? NoteTextView, editor.performFormatShortcut(event) {
      return true
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
            button("command", help: "Actions (⌘K)", key: "k") {}
            button("rectangle.stack", help: "Browse Notes (⌘P)", key: "p", action: onBrowse)
            button("plus", help: "New Note (⌘N)", key: "n", action: onCreate)
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
        onChange: onTextChange, onHeight: onTextHeight)
      ZStack {
        Text("\(Self.shownCount(of: model.text)) characters")
          .font(.system(size: 13))
          .foregroundStyle(.tertiary)
        HStack {
          Spacer()
          // Raycast Notes' Format button, a serif T.
          Text("T")
            .font(.custom("New York", size: 17))
            .frame(width: 32, height: 32)
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

  private func button(
    _ symbol: String, help: String, key: KeyEquivalent, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Glyph(symbol, pointSize: 17).frame(width: 27, height: 28)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .help(help)
    .keyboardShortcut(key, modifiers: .command)
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
    context.coordinator.reportHeight(of: textView)
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
    var noteURL: URL?
    var scrollerObserver: NSObjectProtocol?

    deinit {
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
    @MainActor func reportHeight(of textView: NSTextView) {
      guard let layoutManager = textView.layoutManager, let container = textView.textContainer
      else { return }
      layoutManager.ensureLayout(for: container)
      let height =
        layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
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
      let hidden = MarkdownEditing.hidden(in: MarkdownSpan.spans(in: text))
      guard new.length > 0 else {
        let location = MarkdownEditing.caret(
          new.location, from: old.location + old.length, in: text, hidden: hidden)
        return NSRange(location: location, length: 0)
      }
      var start = new.location
      var end = NSMaxRange(new)
      if start != old.location {
        start = MarkdownEditing.caret(start, from: old.location, in: text, hidden: hidden)
      }
      if end != NSMaxRange(old) {
        end = MarkdownEditing.caret(end, from: NSMaxRange(old), in: text, hidden: hidden)
      }
      return end > start ? NSRange(location: start, length: end - start) : new
    }

    /// Cuts, word and line deletes, and typing over a selection leave no stray marks.
    func textView(
      _ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?
    ) -> Bool {
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
      case #selector(NSResponder.insertNewline(_:)):
        // Return ends a heading; Shift-Return starts another of the same level, as in Raycast.
        guard NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
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
    [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor]
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
      storage.addAttributes(
        attributes(for: span.style, at: span.range, in: storage), range: span.range)
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

  private static func attributes(
    for style: MarkdownSpan.Style, at range: NSRange, in storage: NSTextStorage
  ) -> [NSAttributedString.Key: Any] {
    let font =
      storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
      ?? .systemFont(ofSize: fontSize)
    switch style {
    case .heading(let level):
      // As tall as the heading even when its marks are all there is.
      let lineHeight = NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle
      lineHeight?.minimumLineHeight = NSLayoutManager().defaultLineHeight(for: headingFont(level))
      // Set off from the text below, as Raycast Notes' headings are.
      lineHeight?.paragraphSpacing = 6
      return [.font: headingFont(level), .paragraphStyle: lineHeight ?? .default]
    case .bold:
      return [.font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)]
    case .italic:
      return [.font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)]
    case .strike: return [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
    case .code, .codeBlock:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular),
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
    case .hidden:
      return [
        .hiddenMark: font, .font: NSFont.systemFont(ofSize: 0.01),
        .foregroundColor: NSColor.clear,
      ]
    }
  }
}

/// The note's text view: Raycast Notes' placeholders, its format shortcuts, and deletes that
/// treat hidden marks as one with their text.
final class NoteTextView: NSTextView {
  /// ⌘B bold, ⌘I italic, ⇧⌘X strikethrough and ⌘E code, on the selected words; true when the
  /// keys were one of them.
  func performFormatShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    let key = event.charactersIgnoringModifiers?.lowercased()
    let format: (MarkdownSpan.Style, String)? =
      switch (flags, key) {
      case (.command, "b"): (.bold, "**")
      case (.command, "i"): (.italic, "*")
      case (.command, "e"): (.code, "`")
      case ([.command, .shift], "x"): (.strike, "~~")
      default: nil
      }
    guard let format else { return false }
    guard !hasMarkedText(),
      let edit = MarkdownEditing.toggle(
        format.0, mark: format.1, selection: selectedRange(), in: string,
        spans: MarkdownSpan.spans(in: string))
    else {
      NSSound.beep()
      return true
    }
    replace(edit.range, with: edit.replacement, selecting: edit.selection)
    return true
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

  /// "Start writing..." in an empty note, and "Heading 1" on a heading with nothing in it yet.
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let origin = textContainerOrigin
    let padding = textContainer?.lineFragmentPadding ?? 0
    let color = NSColor.placeholderTextColor
    guard !string.isEmpty else {
      ("Start writing..." as NSString).draw(
        at: NSPoint(x: origin.x + padding, y: origin.y),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: MarkdownEditor.fontSize), .foregroundColor: color,
        ])
      return
    }
    guard let layoutManager else { return }
    for span in MarkdownSpan.spans(in: string) {
      guard case .heading(let level) = span.style, let prefix = span.marks.first,
        NSMaxRange(prefix) == NSMaxRange(span.range)
      else { continue }
      let line = layoutManager.lineFragmentRect(
        forGlyphAt: layoutManager.glyphIndexForCharacter(at: span.range.location),
        effectiveRange: nil)
      ("Heading \(level)" as NSString).draw(
        at: NSPoint(x: origin.x + line.minX + padding, y: origin.y + line.minY),
        withAttributes: [.font: MarkdownEditor.headingFont(level), .foregroundColor: color])
    }
  }
}
