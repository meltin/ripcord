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
    // Once it's key, so the editor can take the focus.
    DispatchQueue.main.async { [model] in model.focusRequest += 1 }
  }

  private func hide() {
    flush()
    window.orderOut(nil)
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
  @FocusState private var isEditing: Bool

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
      TextEditor(text: $model.text)
        .font(.system(size: 14))
        .scrollContentBackground(.hidden)
        .thinScroller()
        .focused($isEditing)
        .onChange(of: model.focusRequest) { isEditing = true }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onChange(of: model.text) { onTextChange() }
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
