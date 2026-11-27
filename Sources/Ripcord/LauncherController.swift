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
    case script
  }

  let icon: Icon
  let title: String
  let message: String
  let confirmTitle: String
  let action: SearchResult.Action
}

/// Configure Command's Set Hotkey… or Set Alias…, open over the panel as Raycast's are.
struct ConfigureEditor {
  enum Kind { case hotkey, alias }

  let kind: Kind
  let settingsKey: String
  /// The row it's for, named with its icon at the bottom of the card.
  let row: SearchResult
  /// The row selected when it opened, selected again when it closes: in a command's own list
  /// that's a clip or snippet, where `row` is the command.
  let selectedID: String
  var alias = ""
  /// The hotkey set, shown as keycaps; nil when there's none yet.
  var hotkey: String?
  /// The modifiers held while recording a hotkey.
  var modifiers: NSEvent.ModifierFlags = []
  /// Why the keys pressed can't be the hotkey.
  var problem: String?
}

/// The ⌘K actions of a row, or the root menu behind the footer's left button.
struct OpenMenu {
  let title: String
  /// Every action; `shown` is what the filter leaves.
  let items: [MenuAction]
  let isRoot: Bool
  var selection = 0
  /// "Search for actions…", typed while the menu is open; `selection` indexes `shown`.
  var filter = ""
  /// The app a paste goes to, which the card names ("Paste to Rex"), so the filter matches it.
  var pasteTarget: String?

  var shown: [MenuAction] {
    let typed = filter.trimmingCharacters(in: .whitespaces)
    return typed.isEmpty
      ? items
      : items.filter {
        Ripcord.title(of: $0.action, else: $0.title, pasteTarget).localizedStandardContains(typed)
      }
  }
}

/// Add Bookmark's or Edit Bookmark's form.
struct BookmarkDraft {
  var title = ""
  var url = ""
  var description = ""
  /// The heading it goes under; nil for a new one named `newGroup`.
  var heading: BookmarkFile.Heading?
  var newGroup = ""
  /// The headings to choose from, as the file had them when the form opened.
  var headings: [BookmarkFile.Heading] = []
  /// The bookmark being edited, its line as read; nil for a new one.
  var original: (line: Int, text: String)?
  /// What the browser's tab filled in, which alone doesn't make a draft.
  var prefilledTitle = ""
  var prefilledURL = ""

  /// Whether anything has been typed or picked, so it's worth keeping.
  var isStarted: Bool {
    // A group picked other than No group counts; a new one only once it has a name.
    let typedTitle = title == prefilledTitle ? "" : title
    let typedURL = url == prefilledURL ? "" : url
    return !(typedTitle + typedURL + description + newGroup).isEmpty
      || (heading.map { $0.line != -1 } ?? false)
  }
}

/// What the launcher asks of the notes window.
enum NotesRequest {
  /// Ripcord Notes: shows the window on the last note, or hides it.
  case toggle
  case create
  case open(URL)
  /// Search Notes moved this note to the Trash: the window lets go of it. `trashed` is where it
  /// went there, for Undo.
  case deleted(URL, trashed: URL?)
}

/// What the panel lists: apps and commands, or one command's own list.
enum LauncherMode {
  case root, clipboard, snippets, snippetForm, repositories, httpStatusCodes, colors, bookmarks
  case bookmarkForm, emoji, scriptOutput, notes

  /// A form, with no query or rows: the footer names it, and ⌘↵ saves it.
  var isForm: Bool { self == .snippetForm || self == .bookmarkForm }

  /// The command whose list this is; nil for the root search.
  var command: BuiltinCommand? {
    switch self {
    case .root: nil
    case .clipboard: .clipboardHistory
    case .snippets: .searchSnippets
    case .snippetForm: .createSnippet
    case .repositories: .searchRepositories
    case .httpStatusCodes: .httpStatusCodes
    case .colors: .colorHistory
    case .bookmarks: .searchBookmarks
    case .bookmarkForm: .addBookmark
    case .emoji: .searchEmoji
    case .scriptOutput: nil
    case .notes: .searchNotes
    }
  }
}

@MainActor
@Observable
final class LauncherModel {
  var mode = LauncherMode.root
  /// The history the clipboard rows were built from, for the preview of the selected one.
  var clipboard: ClipboardHistory?
  /// Clipboard History's type filter; nil lists every type.
  var clipType: ClipType?
  /// The backdrop shader's renderer; nil while it's off, so nothing is drawn or kept.
  var backdrop: BackdropRenderer?
  /// The app a paste lands in: the one in front when the panel opened, as it never activates.
  var pasteTarget: String?
  var query = ""
  var sections: [SearchSection] = []
  var selection = 0
  var menu: OpenMenu?
  /// A question asked over the panel before something that can't be undone.
  var confirmation: Confirmation?
  var configureEditor: ConfigureEditor?
  /// Each row's hotkey by `SearchResult.itemKey`, shown on the selected row as Raycast does.
  var hotkeys: [String: String] = [:]
  /// Bumped when the settings change, so the list is built afresh: the lazy stack kept drawing
  /// a row whose ID stayed the same with its old alias.
  var settingsVersion = 0
  /// Bumped to remount the search field, which takes focus back as it appears.
  var searchFieldID = 0
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
  var bookmarkDraft = BookmarkDraft()
  /// Search Emoji & Symbols' categories, and the one picked; nil shows them all.
  var emojiGroups: [String] = []
  var emojiCategory: Int?
  /// A fullOutput Script Command's title and output; nil output while it runs.
  var scriptOutput: (title: String, output: String?, failed: Bool) = ("", nil, false)
  /// A compact Script Command's last line, shown over the footer for a moment.
  var toast: (text: String, failed: Bool)?
  /// Each script's arguments by path, for the fields beside the search bar.
  var scriptArguments: [String: [ScriptCommand.Argument]] = [:]
  /// What's typed in those fields, by script path; dropped as the panel hides, passwords too.
  var argumentValues: [String: [String]] = [:]
  /// The argument field to focus, for the view to take and clear.
  var argumentFocusRequest: Int?
  /// An argument field has had the focus since the search field last took it.
  var isEditingArgument = false
  /// The selected row's key in `scriptArguments` when it takes arguments: a script's path, or
  /// Generate Dummy Text's settings key.
  var argumentScript: String? {
    switch selected?.action {
    case .runScript(let path)?: scriptArguments[path]?.isEmpty == false ? path : nil
    case .run(.generateDummyText)?: BuiltinCommand.generateDummyText.settingsKey
    default: nil
    }
  }
  /// A new bookmark's draft, kept while an edit has the form.
  var addDraft: BookmarkDraft?

  /// The command the footer names: an edit's form is the list's, where it came from.
  var footerCommand: BuiltinCommand? {
    switch mode {
    case .bookmarkForm where bookmarkDraft.original != nil: .searchBookmarks
    case .snippetForm where editing != nil: .searchSnippets
    default: mode.command
    }
  }

  /// Every row in display order; `selection` indexes into this.
  var results: [SearchResult] { sections.flatMap(\.results) }
  var selected: SearchResult? { results.indices.contains(selection) ? results[selection] : nil }
}

enum SearchCommand {
  case up, down, left, right, submit, cancel, back
  /// Tab in the search field: on to the selected script's first argument.
  case nextField
  case filterCategory(Int?)
  case activate(String)
  case toggleMenu(root: Bool)
  case filterTag(String?)
  case filterClipType(ClipType?)
  case runMenuItem(Int)
  case selectMenuItem(Int)
  case editAlias(String)
}

/// A panel that takes keys without activating Ripcord, so the previous app stays frontmost.
final class LauncherPanel: NSPanel {
  var keyEquivalentHandler: ((NSEvent) -> Bool)?
  /// Sees Esc before the focused field; true when it handled it. A text editor would otherwise
  /// take Esc to show word completions.
  var escapeHandler: (() -> Bool)?
  /// Sees typing before the focused field; true when it took the key, as an open menu's
  /// "Search for actions…" does.
  var typingHandler: ((NSEvent) -> Bool)?

  override var canBecomeKey: Bool { true }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, typingHandler?(event) == true { return }
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
    didSet {
      guard quicklinks != oldValue else { return }
      model.hotkeys = SearchResult.hotkeys(items: items, quicklinks: quicklinks)
      model.settingsVersion += 1
      update(model.query)
    }
  }
  var items: [String: ItemSettings] = [:] {
    didSet {
      guard items != oldValue else { return }
      model.hotkeys = SearchResult.hotkeys(items: items, quicklinks: quicklinks)
      model.settingsVersion += 1
      clipboard.isEnabled = items[BuiltinCommand.clipboardHistory.settingsKey]?.isEnabled ?? true
      update(model.query)
    }
  }
  /// Folders holding Raycast Script Commands, from the config.
  var scriptFolders: [String] = [] {
    didSet { if scriptFolders != oldValue { rescanScripts() } }
  }
  /// The Script Commands in `scriptFolders`, read again each time the panel shows.
  private var scripts: [ScriptCommand] = []
  /// Which compact run's toast is showing, so an older one doesn't clear a newer.
  private var scriptRun = 0
  /// The fullOutput run the output view waits for, so an earlier one's result never shows there.
  private var outputRun = 0
  /// The script whose confirmation is up: answering it runs the script this once.
  private var confirmedScript: String?
  /// The root search's Favorites, by item key.
  var favorites: [String] = [] {
    didSet {
      guard favorites != oldValue else { return }
      model.settingsVersion += 1
      update(model.query)
    }
  }
  var repositorySettings = RepositorySettings() {
    didSet {
      // Only a change in where to look empties the list; a new Open With app just redraws it.
      if repositorySettings.folders != oldValue.folders
        || repositorySettings.depth != oldValue.depth
      {
        repositories = []
        // Kept open behind Settings, the list would otherwise come back empty, or keep a removed
        // folder's repositories until the scan ends.
        if model.mode == .repositories {
          refreshRows(selecting: nil)
          scanRepositories()
        }
      } else if repositorySettings != oldValue, model.mode == .repositories {
        refreshRows(selecting: model.selected?.id)
      }
    }
  }
  /// The last scan, listed at once while a fresh one runs.
  private var repositories: [Repository] = []
  var snippets: [Snippet] = [] {
    didSet {
      model.snippets = snippets
      guard snippets != oldValue else { return }
      // A snippet edited in place keeps its row's ID; see LauncherModel.settingsVersion.
      model.settingsVersion += 1
      if model.mode == .snippets { refreshRows() }
    }
  }
  /// Saves a change to the config's snippets; false when the file couldn't be written.
  /// `change` gets the list as the file holds it now and returns the new one, or nil to refuse.
  var editSnippets: (_ change: ([Snippet]) -> [Snippet]?) -> Bool = { _ in false }
  /// Changes the settings file through the settings window's model, as its rows do.
  var editSettings: (_ change: (SettingsModel) -> Void) -> Bool = { _ in false }
  /// The input source selected while the panel is open, by TIS ID; nil leaves it alone.
  var inputSource: String?
  /// What the panel switched away from, put back when it closes.
  private var previousInputSource: TISInputSource?
  var onOpenSettings: () -> Void = {}
  var onCheckForUpdates: () -> Void = {}
  /// Settings at the page for the command with this settings key.
  var onConfigure: (_ settingsKey: String) -> Void = { _ in }
  /// The settings window's model, whose hotkey checks Set Hotkey… records through.
  weak var settings: SettingsModel?
  private var hotkeyMonitor: Any?
  /// Shows why something couldn't be done, as a System Action that lacks a permission.
  var onError: (String) -> Void = { _ in NSSound.beep() }
  /// Export Snippets and Import Snippets, which need file dialogs and the config.
  var onExportSnippets: () -> Void = {}
  /// Coffee: keep the Mac awake for this many seconds, or until Decaffeinate for nil.
  var onCaffeinate: (TimeInterval?) -> Void = { _ in }
  var onDecaffeinate: () -> Void = {}
  /// Sleep Timer: sleep the Mac, or turn its display off, after this many seconds.
  var onSleepTimer: (_ seconds: TimeInterval, _ displayOnly: Bool) -> Void = { _, _ in }
  var onStopSleepTimer: () -> Void = {}
  /// Clean Keyboard: block the keyboard for this many seconds.
  var onCleanKeyboard: (TimeInterval) -> Void = { _ in }
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
  private var colors = ColorHistory(
    fileURL: URL.applicationSupportDirectory.appending(path: "Ripcord/colors.json"))
  /// Forms left unfinished, listed under Drafts in the root search.
  private var draftStore = DraftStore(
    fileURL: URL.applicationSupportDirectory.appending(path: "Ripcord/drafts.json"))
  /// Search Emoji & Symbols' list, read from the app's resources the first time it opens.
  private var emojiCatalog: EmojiCatalog?
  private var emojiHistory = EmojiHistory(
    fileURL: URL.applicationSupportDirectory.appending(path: "Ripcord/emoji.json"))
  /// Search Emoji & Symbols' grid: rows of this many.
  static let emojiColumns = 8
  /// Read each time Search Bookmarks opens, so edits made by hand show up.
  private var bookmarks = BookmarkFile(text: "")
  /// The notes folder, and its notes as Search Notes last read them.
  private let noteStore = NoteStore(folder: NoteStore.userFolder)
  private var notes: [Note] = []
  /// Hands the notes window what it's asked to do.
  var onNotes: (NotesRequest) -> Void = { _ in }
  static let bookmarksURL = URL.homeDirectory.appending(path: ".config/ripcord/bookmarks.md")
  /// What Pick Color copies, and Color History lists first.
  var colorFormat = ColorFormat.hex {
    didSet { if colorFormat != oldValue, model.mode == .colors { refreshRows() } }
  }
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
    panel.typingHandler = { [weak self] event in
      guard let self else { return false }
      guard model.confirmation == nil else { return answerQuestion(event) }
      return typeIntoMenu(event)
    }
    panel.escapeHandler = { [weak self] in
      // Only the form: the search field turns Esc into .cancel itself.
      // The output view has no field either, and an argument field acts as the search field.
      guard let self, model.mode.isForm || model.mode == .scriptOutput || model.isEditingArgument
      else { return false }
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
      rootView: ZStack {
        Color(nsColor: background)
        // Over the gray and under the text, as dupin and Ghostty draw theirs.
        PanelBackdrop(model: model)
        SearchView(
          model: model,
          onQueryChange: { [weak self] in self?.update($0) },
          onCommand: { [weak self] in self?.handle($0) })
      })
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
  private let windows = WindowManager()
  /// The panel was opened by a hotkey just to ask a System Action's question.
  private var openedForQuestion = false

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
    loadBackdrop()
    model.backdrop?.state.lastKeystroke = nil
    model.backdrop?.start()
    model.pasteTarget = NSWorkspace.shared.frontmostApplication?.localizedName
    // A script added or edited since shows up; only each file's head is read.
    rescanScripts()
    if let resumed {
      // The query, selection and any draft are as they were; only the rows are re-read.
      if resumed == .bookmarks, !loadBookmarks() { return show() }
      // Notes may have been written or changed in the window meanwhile.
      if resumed == .notes { notes = noteStore.list() }
      model.mode = resumed
      refreshRows(selecting: model.selected?.id)
    } else {
      // What was left open is dropped, filter included.
      model.snippetTag = nil
      model.clipType = nil
      model.emojiCategory = nil
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
    model.backdrop?.stop()
    stashDraft()
    model.toast = nil
    model.argumentValues = [:]
    model.argumentFocusRequest = nil
    confirmedScript = nil
    if model.isEditingArgument {
      // The search field takes the focus back for next time.
      model.isEditingArgument = false
      model.searchFieldID += 1
    }
    // A recording left running would keep every hotkey unregistered.
    closeEditor(backToMenu: false)
    panel.orderOut(nil)
    openedForQuestion = false
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
    // A filter left on would hide snippets, clips or emoji the next time, unasked.
    model.snippetTag = nil
    model.clipType = nil
    model.emojiCategory = nil
    model.mode = .root
    update("")
  }

  private func refreshApps() {
    Task {
      apps = await Task.detached(priority: .userInitiated) { AppIndex.scan() }.value
      // Refresh the rows only: a ↓ or ⌘K pressed while the scan ran must survive it. A script
      // asking for an argument stays selected by ID when new apps land above it.
      refreshRows(selecting: model.argumentScript == nil ? nil : model.selected?.id)
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
    // The backdrop's inputs: a keystroke just now, and how long the query is.
    if query != model.query { model.backdrop?.state.lastKeystroke = .now }
    model.backdrop?.state.queryLength = query.count
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
      return Search.clipboardSections(
        for: query, history: clipboard.history, type: model.clipType)
    }
    if model.mode == .httpStatusCodes { return Search.httpStatusSections(for: query) }
    if model.mode == .bookmarks { return Search.bookmarkSections(for: query, file: bookmarks) }
    if model.mode == .notes { return Search.noteSections(for: query, notes: notes) }
    if model.mode == .emoji, let emojiCatalog {
      return Search.emojiSections(
        for: query, catalog: emojiCatalog, history: emojiHistory, category: model.emojiCategory)
    }
    if model.mode == .colors {
      return Search.colorSections(for: query, history: colors, format: colorFormat)
    }
    if model.mode == .repositories {
      return Search.repositorySections(
        for: query, repositories: repositories, settings: repositorySettings)
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
    if model.mode.isForm || model.mode == .scriptOutput { return [] }
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
      for: query, apps: apps, running: running, quicklinks: quicklinks, items: items,
      favorites: favorites, drafts: draftStore.drafts, scripts: scripts)
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
        // Answered yes: that script runs this once without asking again.
        if case .runScript(let path) = confirmation.action { confirmedScript = path }
        perform(confirmation.action)
      case .cancel, .back:
        model.confirmation = nil
        confirmedScript = nil
        // A panel opened only to ask goes away with the question.
        if openedForQuestion { hide() }
      default: break
      }
      return
    }
    if let editor = model.configureEditor {
      switch command {
      case .editAlias(let text): model.configureEditor?.alias = text
      case .submit where editor.kind == .alias:
        // Only a fresh press: Return held from the menu item that opened the card mustn't save.
        guard NSApp.currentEvent.map({ $0.type == .keyDown && $0.isARepeat }) != true else {
          return
        }
        saveAlias(editor)
      case .cancel: closeEditor(backToMenu: editor.kind == .hotkey)
      // A click outside the card.
      case .back: closeEditor(backToMenu: false)
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
        model.menu?.selection = min(menu.selection + 1, max(menu.shown.count - 1, 0))
        return
      case .submit:
        guard menu.shown.indices.contains(menu.selection) else { return NSSound.beep() }
        return perform(menu.shown[menu.selection].action)
      case .cancel:
        // Esc clears what's typed first, then closes, as Raycast's does.
        if !menu.filter.isEmpty {
          model.menu?.filter = ""
          model.menu?.selection = 0
          return
        }
        model.menu = nil
        return
      // The grid behind the menu stays put; the menu acts on what's selected.
      case .left, .right: return
      default: break
      }
    }
    if model.mode.isForm, case .submit = command { return saveForm() }
    let count = model.results.count
    if model.mode == .emoji, let moved = gridSelection(after: command) {
      model.selection = moved
      return
    }
    switch command {
    case .up: model.selection = max(model.selection - 1, 0)
    case .down: model.selection = min(model.selection + 1, max(count - 1, 0))
    case .left, .right: break  // Only the emoji grid moves sideways, above.
    case .filterCategory(let category):
      model.emojiCategory = category
      update(model.query)
    case .submit:
      guard let selected = model.selected else { return NSSound.beep() }
      // ⌥↵ and ⇧↵ reach here as Return; a row with an action for them runs it.
      let flags = NSApp.currentEvent?.modifierFlags ?? []
      let held = [(NSEvent.ModifierFlags.option, "⌥"), (.shift, "⇧")].filter {
        flags.contains($0.0)
      }.map(\.1).joined()
      let action = held.isEmpty ? nil : selected.actions.first { $0.shortcut == held + "↵" }
      perform(action?.action ?? selected.action)
    case .cancel:
      // An edit always goes back to its list, even one its hotkey opened.
      if model.mode == .snippetForm, model.formSource != nil { return goBack() }
      if model.mode == .bookmarkForm, model.bookmarkDraft.original != nil { return goBack() }
      // Like Raycast: Esc leaves a command's list for the root search first.
      guard model.mode != .root, !closesOnCancel else { return hide() }
      goBack()
    case .back:
      goBack()
    case .nextField:
      // Not behind an open menu.
      // The first field to type in; a dropdown takes a click.
      if model.menu == nil, let path = model.argumentScript {
        model.argumentFocusRequest = model.scriptArguments[path]?.firstIndex {
          $0.type != .dropdown
        }
      }
    case .activate(let id): model.results.first { $0.id == id }.map { perform($0.action) }
    case .toggleMenu(let root): toggleMenu(root: root)
    case .filterClipType(let type):
      model.clipType = type
      refreshRows(selecting: nil)
    case .filterTag(let tag):
      model.snippetTag = tag
      update(model.query)
    case .runMenuItem(let index):
      if let items = model.menu?.shown, items.indices.contains(index) {
        perform(items[index].action)
      }
    case .selectMenuItem(let index): model.menu?.selection = index
    case .editAlias: break  // Only while Set Alias… is open, above.
    }
  }

  /// Fills a fresh Add Bookmark from the browser that was in front, as Raycast's does: the
  /// script runs off the main thread, as the first run waits on macOS's Automation question, and
  /// its answer goes in only while the form is still empty.
  private func fillFromBrowser() {
    // In front now: the panel doesn't activate Ripcord, and its hotkey may open the form
    // before the panel shows.
    guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
      let script = BrowserTab.script(forBundleID: id)
    else { return }
    tabRequest += 1
    let request = tabRequest
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let output = Self.runAppleScript(script)
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.fill(fromTab: output, request: request) }
      }
    }
  }

  /// Which browser question is the latest; an answer to an older one is dropped.
  private var tabRequest = 0

  private func fill(fromTab output: String, request: Int) {
    let draft = model.bookmarkDraft
    guard request == tabRequest, model.mode == .bookmarkForm, draft.original == nil,
      draft.title.isEmpty, draft.url.isEmpty, let tab = BrowserTab.parse(output)
    else { return }
    model.bookmarkDraft.url = tab.url
    model.bookmarkDraft.title = tab.title
    model.bookmarkDraft.prefilledURL = tab.url
    model.bookmarkDraft.prefilledTitle = tab.title
  }

  /// Runs `script` with osascript, which macOS asks about as Ripcord's; its output, or "" when
  /// it fails, as when Automation is refused.
  private nonisolated static func runAppleScript(_ script: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    let output = Pipe()
    process.standardOutput = output
    // Not read, so it must not fill a pipe and stall the script.
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return "" }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : ""
  }

  private func rescanScripts() {
    let home = NSHomeDirectory()
    scripts = ScriptCommand.scan(
      scriptFolders.map {
        URL(
          fileURLWithPath: ($0 as NSString).expandingTildeInPath,
          relativeTo: URL(fileURLWithPath: home))
      })
    // A folder listed twice gives its scripts twice.
    model.scriptArguments = Dictionary(
      scripts.map { ($0.url.path, $0.arguments) }, uniquingKeysWith: { first, _ in first })
    model.scriptArguments[BuiltinCommand.generateDummyText.settingsKey] = DummyText.arguments(
      preferred: dummyTextLanguage)
  }

  /// Generate Dummy Text's language when its menu is left alone, first in that menu.
  var dummyTextLanguage = DummyText.Language.japanese {
    didSet {
      model.scriptArguments[BuiltinCommand.generateDummyText.settingsKey] = DummyText.arguments(
        preferred: dummyTextLanguage)
    }
  }

  /// Generate Dummy Text: the length and language from the fields beside the search bar, pasted
  /// into the app you were in, or copied. Run from a hotkey, the fields' defaults.
  private func generateDummyText(copyOnly: Bool) {
    let key = BuiltinCommand.generateDummyText.settingsKey
    let values = model.argumentValues[key] ?? []
    // Typed for this run, as a script's fields empty once it runs.
    model.argumentValues[key] = nil
    let length = DummyText.length(from: values.first ?? "")
    let language =
      values.count > 1
      ? DummyText.Language(rawValue: values[1]) ?? dummyTextLanguage : dummyTextLanguage
    paste(DummyText.generate(language, length: length), copyOnly: copyOnly)
  }

  /// Asks before running a script that wants it, on the card System Actions ask on; its
  /// arguments stay typed meanwhile.
  private func askToRun(_ script: ScriptCommand) {
    if !panel.isVisible {
      show()
      openedForQuestion = true
    }
    model.menu = nil
    model.confirmation = Confirmation(
      icon: .script, title: "Run “\(script.title)”?",
      message: "This script asks to be confirmed before it runs.", confirmTitle: "Run Script",
      action: .runScript(script.url.path))
  }

  /// Shows the script's row with its empty field focused: like Raycast, it doesn't run with a
  /// required argument missing, whichever way it was started.
  private func askForArgument(_ index: Int, of script: ScriptCommand) {
    let path = script.url.path
    if !(panel.isVisible && model.argumentScript == path) {
      if !panel.isVisible { show() } else if model.mode != .root { open(.root) }
      update(script.title)
      if let row = model.results.firstIndex(where: { $0.action == .runScript(path) }) {
        model.selection = row
      }
    }
    // Once the panel is key: shown just now, it would hand the focus back to the search field.
    // Only while the row is still there, or the request would wait for another script.
    DispatchQueue.main.async { [weak self] in
      guard let self, model.argumentScript == path else { return }
      model.argumentFocusRequest = index
    }
  }

  /// Runs a Script Command as its mode says: silent closes the panel and shows the last line
  /// over the screen; compact keeps the panel and shows it over the footer; fullOutput opens a
  /// view that shows all of it once the script ends. A failure shows the exit code and the last
  /// line of what the script printed.
  private func runScript(_ path: String) {
    guard let script = scripts.first(where: { $0.url.path == path }) else {
      return onError("That script is gone from its folder.")
    }
    // Read before a silent one hides the panel, which drops them.
    let values = model.argumentValues[path] ?? []
    if let missing = script.firstMissing(in: values) { return askForArgument(missing, of: script) }
    if script.needsConfirmation, confirmedScript != path { return askToRun(script) }
    confirmedScript = nil
    // Typed for this run, as Raycast's fields empty once it runs; a password isn't kept.
    model.argumentValues[path] = nil
    // Opened only to ask, from a hotkey: it goes with the question, as System Actions' does,
    // unless the output is to show in it.
    if openedForQuestion {
      openedForQuestion = false
      if script.mode == .compact, panel.isVisible { hide() }
    }
    // Hidden already when its hotkey ran it: what was left open there stays.
    if script.mode == .silent, panel.isVisible { hide() }
    if script.mode == .fullOutput {
      outputRun += 1
      model.scriptOutput = (script.title, nil, false)
      // Already showing another's output: open() would take it as a toggle and close.
      if !(panel.isVisible && model.mode == .scriptOutput) { open(.scriptOutput) }
    }
    let run = outputRun
    ScriptRunner.run(script, arguments: script.processArguments(values)) { [weak self] result in
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.finish(script, result, run: run) }
      }
    }
  }

  private func finish(_ script: ScriptCommand, _ result: ScriptRunner.Result, run: Int) {
    let failed = result.status != 0
    if script.mode == .fullOutput {
      // Shown only while its view is still the one open for this run.
      guard model.mode == .scriptOutput, run == outputRun else { return }
      // stdout, then stderr (not interleaved): many tools log to stderr even when they succeed.
      let parts = [result.output, result.errors, failed ? "Exit code \(result.status)" : ""]
        .map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.isEmpty }
      let shown = ScriptCommand.plain(parts.joined(separator: "\n"))
      model.scriptOutput = (script.title, shown.isEmpty ? "No output" : shown, failed)
      return
    }
    let line =
      failed
      ? "“\(script.title)” failed (exit \(result.status)): "
        + (ScriptCommand.lastLine(of: result.errors) ?? ScriptCommand.lastLine(of: result.output)
          ?? "no output")
      : ScriptCommand.lastLine(of: result.output)
    guard let line else { return }
    // Compact shows it in the panel while it's still open there; otherwise over the screen.
    guard script.mode == .compact, panel.isVisible else { return HUD.show(line, failed: failed) }
    // Counted as it shows, so only a newer toast keeps this one's timer from clearing it.
    scriptRun += 1
    let run = scriptRun
    model.toast = (line, failed)
    DispatchQueue.main.asyncAfter(deadline: .now() + (failed ? 4 : 2.5)) { [weak self] in
      MainActor.assumeIsolated {
        if self?.scriptRun == run { self?.model.toast = nil }
      }
    }
  }

  /// Whether anything is typed in Create Snippet's form.
  private var snippetStarted: Bool {
    !(model.draft.name + model.draft.text + (model.draft.keyword ?? "") + model.tagsText).isEmpty
      || model.draft.icon != nil
  }

  /// Keeps what's typed in a new snippet or bookmark as a draft as its form is left, or drops
  /// the draft once the form is emptied, as Raycast's Drafts do.
  private func stashDraft() {
    switch model.mode {
    case .snippetForm where model.formSource == nil:
      let started = snippetStarted
      let snippet = model.draft
      let tags = model.tagsText
      saveDrafts { drafts in
        drafts.snippet = started ? snippet : nil
        drafts.snippetTags = started ? tags : nil
      }
    case .bookmarkForm:
      // An edit keeps the new bookmark waiting behind it, if there is one; with none held, the
      // saved draft stays as it is.
      let editing = model.bookmarkDraft.original != nil
      if editing, model.addDraft == nil { return }
      let new = editing ? model.addDraft : model.bookmarkDraft
      let fields = new.flatMap { draft -> BookmarkDraftFields? in
        guard draft.isStarted else { return nil }
        return BookmarkDraftFields(
          title: draft.title, url: draft.url, description: draft.description,
          group: draft.heading.map { $0.line == -1 ? nil : $0.title } ?? "",
          newGroup: draft.newGroup)
      }
      saveDrafts { $0.bookmark = fields }
    default: break
    }
  }

  /// Changes the saved drafts, saying why when they can't be written.
  private func saveDrafts(_ change: (inout SavedDrafts) -> Void) {
    var drafts = draftStore.drafts
    change(&drafts)
    do { try draftStore.save(drafts) } catch { onError(error.localizedDescription) }
  }

  /// A question takes every key while it's up, answering Return and Esc itself: nothing reaches
  /// the field behind it, a form's text or an argument about to run, nor an input method
  /// still composing there.
  private func answerQuestion(_ event: NSEvent) -> Bool {
    let modified = !event.modifierFlags.intersection([.option, .control, .command]).isEmpty
    switch Int(event.keyCode) {
    // ⌥↵ and the like are dropped too: in a field they'd add a line to it.
    case kVK_Return, kVK_ANSI_KeypadEnter:
      guard !modified else { break }
      NSTextInputContext.current?.discardMarkedText()
      handle(.submit)
    case kVK_Escape:
      NSTextInputContext.current?.discardMarkedText()
      handle(.cancel)
    default: break
    }
    return true
  }

  /// Letters typed while a menu is open go to its "Search for actions…", and Delete takes the
  /// last one back; arrows, Return and Esc still reach the field, and shortcuts still fire.
  private func typeIntoMenu(_ event: NSEvent) -> Bool {
    guard model.menu != nil, model.configureEditor == nil else {
      return false
    }
    // Read first: reading the menu while writing it in one statement traps.
    let filter = model.menu?.filter ?? ""
    if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
      // Nothing typed: the key does nothing, and the selection stays.
      guard !filter.isEmpty else { return true }
      let flags = event.modifierFlags
      // ⌘⌫ clears it, ⌥⌫ takes the last word, ⌫ the last letter, as a field does.
      let kept =
        flags.contains(.command)
        ? ""
        : flags.contains(.option)
          ? String(
            filter.trimmingCharacters(in: .whitespaces).reversed()
              .drop { !$0.isWhitespace }.reversed())
          : String(filter.dropLast())
      model.menu?.filter = kept
      model.menu?.selection = 0
      return true
    }
    // ⌘V pastes into the filter, one line of it.
    if event.modifierFlags.intersection([.command, .control, .option]) == .command,
      event.charactersIgnoringModifiers?.lowercased() == "v"
    {
      let pasted = NSPasteboard.general.string(forType: .string) ?? ""
      model.menu?.filter =
        filter + (pasted.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
      model.menu?.selection = 0
      return true
    }
    // Other ⌘ and ⌃ keys are shortcuts, for the menu's actions.
    guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return false }
    // Printable text only: arrows and the like come as function-key characters.
    guard let text = event.characters, !text.isEmpty,
      text.unicodeScalars.allSatisfy({
        !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
      })
    else { return false }
    model.menu?.filter += text
    model.menu?.selection = 0
    return true
  }

  /// Selects the row of the item with `key` after a favorite moved it: its row ID can differ
  /// between Running and Favorites, as a running app's path does.
  private func select(itemKey key: String) {
    if let index = model.results.firstIndex(where: { $0.itemKey == key }) {
      model.selection = index
    }
  }

  /// Where an arrow moves the emoji grid's selection: ←→ by one, ↑↓ to the same column of the
  /// row above or below, across sections; nil for other commands.
  private func gridSelection(after command: SearchCommand) -> Int? {
    let columns = Self.emojiColumns
    // Each item's section, row and column, in display order.
    let cells = model.sections.enumerated().flatMap { section, entry in
      entry.results.indices.map { (section: section, row: $0 / columns, column: $0 % columns) }
    }
    guard cells.indices.contains(model.selection) else { return nil }
    let here = cells[model.selection]
    let rows = cells.indices.map { (cells[$0].section, cells[$0].row) }
    // Row keys in display order, each with its first index.
    let starts = cells.indices.filter { $0 == 0 || rows[$0] != rows[$0 - 1] }
    guard let rowIndex = starts.lastIndex(where: { $0 <= model.selection }) else { return nil }
    func cell(inRow row: Int) -> Int {
      let start = starts[row]
      let end = row + 1 < starts.count ? starts[row + 1] : cells.count
      return min(start + here.column, end - 1)
    }
    switch command {
    case .left: return max(model.selection - 1, 0)
    case .right: return min(model.selection + 1, cells.count - 1)
    case .up: return rowIndex == 0 ? model.selection : cell(inRow: rowIndex - 1)
    case .down: return rowIndex + 1 < starts.count ? cell(inRow: rowIndex + 1) : model.selection
    default: return nil
    }
  }

  private func toggleMenu(root: Bool) {
    let wantsRoot = root || model.selected == nil
    guard model.menu?.isRoot != wantsRoot else {
      model.menu = nil
      return
    }
    if !wantsRoot, let selected = model.selected {
      model.menu = OpenMenu(
        title: selected.title, items: selected.actions, isRoot: false,
        pasteTarget: model.pasteTarget)
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
      // Without Shift, so ⇧⌘, reads as "," (charactersIgnoringModifiers keeps Shift and gives
      // "<"). With ⌘ when it's held, so Kana and Dvorak-QWERTY ⌘ give its Latin letters; without
      // it for ⌃X and the like, which read as the layout types them.
      let key = event.characters(
        byApplyingModifiers: flags.contains(.command) ? .command : [])?.lowercased()
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
    // Set Alias… keeps the keys to its field; the row's shortcuts would act behind it.
    if model.configureEditor != nil { return false }
    if flags == .command, key == "\r", model.mode.isForm {
      saveForm()
      return true
    }
    if flags == .command, key == "k", !model.mode.isForm {
      toggleMenu(root: false)
      return true
    }
    let symbols: [(NSEvent.ModifierFlags, String)] = [
      (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]
    // Arrows by their key, as the menu writes them, for Move Favorite Up and Down: the layout
    // translates them to control characters, not the arrow function keys.
    let arrows = [kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→"]
    let shortcut =
      symbols.filter { flags.contains($0.0) }.map(\.1).joined()
      + (arrows[Int(event.keyCode)] ?? (key == "\r" ? "↵" : key.uppercased()))
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
    if action == .run(.generateDummyText) || action == .copyDummyText {
      return generateDummyText(copyOnly: action == .copyDummyText)
    }
    if action == .run(.clipboardHistory) {
      // Entries past their retention go as the list opens, though nothing new was copied.
      clipboard.prune()
      return open(.clipboard)
    }
    if action == .run(.searchSnippets) { return open(.snippets) }
    if action == .run(.httpStatusCodes) { return open(.httpStatusCodes) }
    if action == .run(.colorHistory) { return open(.colors) }
    if action == .run(.searchBookmarks) {
      if loadBookmarks() { open(.bookmarks) }
      return
    }
    if case .deleteBookmark(let line, let text) = action {
      model.menu = nil
      return deleteBookmark(line: line, text: text)
    }
    if action == .run(.searchEmoji) {
      if emojiCatalog == nil {
        guard
          let url = Bundle.main.url(
            forResource: "emoji", withExtension: "json", subdirectory: "Emoji"),
          let catalog = try? EmojiCatalog(data: Data(contentsOf: url))
        else { return onError("Ripcord's emoji list is missing; build the app with build-app.sh.") }
        emojiCatalog = catalog
        model.emojiGroups = catalog.groups
      }
      return open(.emoji)
    }
    if case .emoji(let shown, let base, let how) = action {
      model.menu = nil
      do { try emojiHistory.use(base) } catch { onError(error.localizedDescription) }
      guard how == .pasteKeepingOpen else { return paste(shown, copyOnly: how == .copy) }
      // The panel gives the key back for the paste, then comes back where it was.
      paste(shown, copyOnly: false, keepingMode: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
        self?.show(resuming: true)
      }
      return
    }
    if case .emojiSkinToneMenu(let character) = action, let emojiCatalog {
      model.menu = OpenMenu(
        title: "Skin Tone", items: Search.skinToneMenu(for: character, catalog: emojiCatalog),
        isRoot: false)
      return
    }
    if case .toggleFavorite(let key) = action {
      model.menu = nil
      if !editSettings({
        $0.config.favorites = Search.togglingFavorite(key, in: $0.config.favorites)
      }) {
        NSSound.beep()
      }
      return select(itemKey: key)
    }
    if case .moveFavorite(let key, let other) = action {
      model.menu = nil
      if !editSettings({
        $0.config.favorites = Search.swappingFavorite(key, with: other, in: $0.config.favorites)
      }) {
        NSSound.beep()
      }
      return select(itemKey: key)
    }
    if case .setEmojiSkinTone(let tone) = action {
      model.menu = nil
      do { try emojiHistory.setSkinTone(tone) } catch { onError(error.localizedDescription) }
      return refreshRows(selecting: model.selected?.id)
    }
    if case .runScript(let path) = action {
      model.menu = nil
      return runScript(path)
    }
    if case .openDraft(let form) = action {
      return perform(.run(form == .snippet ? .createSnippet : .addBookmark))
    }
    if case .discardDraft(let form) = action {
      model.menu = nil
      saveDrafts { drafts in
        if form == .snippet {
          drafts.snippet = nil
          drafts.snippetTags = nil
        } else {
          drafts.bookmark = nil
        }
      }
      // The form's own copy goes too, or opening the command would bring it back.
      if form == .snippet, model.formSource == nil {
        model.draft = Snippet(name: "", text: "")
        model.tagsText = ""
      }
      if form == .bookmark {
        model.addDraft = nil
        if model.bookmarkDraft.original == nil { model.bookmarkDraft = BookmarkDraft() }
      }
      return refreshRows(selecting: model.selected?.id)
    }
    if action == .run(.addBookmark) {
      guard loadBookmarks() else { return }
      let draft = model.bookmarkDraft
      // A new bookmark's draft survives the panel closing, and an edit in between, as Create
      // Snippet's does, as when clicking the browser to copy its URL; it's cleared once saved.
      if let kept = model.addDraft ?? (draft.original == nil && draft.isStarted ? draft : nil) {
        model.bookmarkDraft = rebased(kept)
        model.addDraft = nil
      } else if let saved = draftStore.drafts.bookmark,
        !(panel.isVisible && model.mode == .bookmarkForm)
      {
        // The draft left last time, its group found again by name.
        model.bookmarkDraft = rebased(
          BookmarkDraft(
            title: saved.title, url: saved.url, description: saved.description,
            heading: saved.group.map { $0.isEmpty ? nil : BookmarkFile.Heading(title: $0, line: 0) }
              ?? BookmarkFile.Heading(title: "", line: -1),
            newGroup: saved.newGroup))
      } else {
        // Raycast's starts on No group: the top of the file, above the first heading.
        let choices = groupChoices()
        model.bookmarkDraft = BookmarkDraft(heading: choices.first, headings: choices)
        // Not when this closes the form, as its hotkey does over an open one.
        if !(panel.isVisible && model.mode == .bookmarkForm) { fillFromBrowser() }
      }
      // From an edit, a new form rather than closing the panel, as its hotkey closes its own.
      if panel.isVisible, model.mode == .bookmarkForm, draft.original != nil {
        closesOnCancel = false
        return update("")
      }
      return open(.bookmarkForm)
    }
    if case .editBookmark(let line, let text) = action {
      model.menu = nil
      return editBookmark(line: line, text: text)
    }
    if case .moveBookmarkMenu(let line, let text) = action {
      guard loadBookmarks() else { return }
      let items = Search.moveMenu(for: (line, text), file: bookmarks)
      guard !items.isEmpty else {
        model.menu = nil
        return onError("There's no other group to move it to; add a # heading first.")
      }
      model.menu = OpenMenu(title: "Move to Group", items: items, isRoot: false)
      return
    }
    if case .moveBookmark(let line, let text, let headingLine, let headingTitle) = action {
      model.menu = nil
      let heading = BookmarkFile.Heading(title: headingTitle, line: headingLine)
      if let id = changeBookmarks({
        try $0.moving(line: line, text: text, under: .heading(heading))
      }) {
        refreshRows(selecting: id)
      }
      return
    }
    if case .deleteColor(let hex) = action {
      model.menu = nil
      do { try colors.delete(hex: hex) } catch { onError(error.localizedDescription) }
      return refreshRows(selecting: model.selected?.id)
    }
    // A command that takes a time: its title in the field and the time to be typed after it, as
    // Raycast asks for an argument.
    if case .run(let command) = action, [.sleepTimer, .cleanKeyboard].contains(command) {
      // Set Alias…'s card would stay up over rows that changed under it.
      closeEditor(backToMenu: false)
      if !panel.isVisible { show() }
      model.mode = .root
      return update(command.title + " ")
    }
    if action == .run(.searchRepositories) {
      // Not when its hotkey is closing the list.
      if !(panel.isVisible && model.mode == .repositories) { scanRepositories() }
      return open(.repositories)
    }
    if action == .run(.createSnippet) { return edit(nil) }
    if action == .run(.searchNotes) {
      notes = noteStore.list()
      return open(.notes)
    }
    if case .deleteNote(let url) = action {
      let id = model.selected?.id
      model.menu = nil
      do {
        let trashed = try noteStore.read(url).flatMap { try noteStore.trash($0) }
        onNotes(.deleted(url, trashed: trashed))
      } catch {
        onError(error.localizedDescription)
      }
      notes = noteStore.list()
      return refreshRows(selecting: id)
    }
    if case .clip(let id, let clipAction) = action { return perform(clipAction, on: id) }
    if case .snippet(let index, let snippetAction) = action {
      return perform(snippetAction, on: index)
    }
    if case .system(let system, let confirmed) = action {
      return perform(system, confirmed: confirmed)
    }
    if case .window(let layout) = action {
      // The window in front now: the panel never activates Ripcord, so it's still the user's.
      let frontmost = NSWorkspace.shared.frontmostApplication
      if panel.isVisible { hide() }
      if let message = windows.apply(layout, to: frontmost) { onError(message) }
      return
    }
    // Open Settings while the panel still holds the key press, so macOS treats it as the
    // user's request to bring Ripcord forward.
    if action == .run(.settings) { onOpenSettings() }
    if case .configureMenu(let key) = action {
      model.menu = OpenMenu(
        title: "Configure Command", items: MenuAction.configureMenu(key, settings: items[key]),
        isRoot: false)
      return
    }
    if let delete = deletion(action) {
      // Read first: saving re-reads the settings, which starts the list over at its first row.
      let id = model.selected?.id
      model.menu = nil
      if !editSettings(delete) { NSSound.beep() }
      return refreshRows(selecting: id)
    }
    switch action {
    case .setHotkey(let key): return openEditor(.hotkey, for: key)
    case .setAlias(let key): return openEditor(.alias, for: key)
    case .configure(let key): onConfigure(key)
    default: break
    }
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
    case .cleanShot(let command):
      // After hide(), so a capture doesn't include the panel.
      if !(command.url.map(NSWorkspace.shared.open) ?? false) { NSSound.beep() }
    case .run(.settings), .configure, .configureMenu, .setHotkey, .setAlias, .deleteHotkey,
      .deleteAlias:
      break  // Opened before hide(), above.
    case .openWith(let url, let app):
      NSWorkspace.shared.open([url], withApplicationAt: app, configuration: .init()) { _, error in
        if error != nil { DispatchQueue.main.async { NSSound.beep() } }
      }
    case .run(.exportSnippets):
      onExportSnippets()
    case .run(.ripcordNotes):
      onNotes(.toggle)
    case .run(.createNote):
      onNotes(.create)
    case .openNote(let url):
      onNotes(.open(url))
    case .run(.importSnippets):
      onImportSnippets()
    case .run(.caffeinate):
      onCaffeinate(nil)
    case .caffeinate(let seconds):
      onCaffeinate(seconds)
    case .run(.decaffeinate):
      onDecaffeinate()
    case .sleepTimer(let seconds, let displayOnly):
      onSleepTimer(seconds, displayOnly)
    case .run(.stopSleepTimer):
      onStopSleepTimer()
    case .run(.pickColor):
      pickColor()
    case .cleanKeyboard(let seconds):
      onCleanKeyboard(seconds)
    case .run(.resetWindowPosition), .run(.clipboardHistory), .run(.searchSnippets),
      .run(.searchRepositories), .run(.httpStatusCodes), .run(.sleepTimer), .run(.colorHistory),
      .run(.cleanKeyboard), .run(.searchBookmarks), .run(.addBookmark), .deleteBookmark,
      .editBookmark, .moveBookmarkMenu, .moveBookmark,
      .run(.searchEmoji), .emoji, .emojiSkinToneMenu, .setEmojiSkinTone, .toggleFavorite,
      .openDraft, .discardDraft, .runScript, .run(.searchNotes), .deleteNote,
      .moveFavorite,
      .deleteColor,
      .run(.createSnippet), .clip, .snippet, .system, .window:
      break  // Handled above, without hiding the panel.
    case .run(.checkForUpdates):
      onCheckForUpdates()
    case .run(.generateDummyText), .copyDummyText:
      break  // Handled above, where it reads the fields before hide() empties them.
    case .run(.quit):
      NSApp.terminate(nil)
    }
  }

  /// Asks first for one with a warning, over the panel (opened for it when a hotkey ran it);
  /// otherwise hides the panel and runs it in the app the user was in.
  private func perform(_ action: SystemAction, confirmed: Bool) {
    if let warning = action.warning, !confirmed {
      if !panel.isVisible {
        show()
        openedForQuestion = true
      }
      model.menu = nil
      model.confirmation = Confirmation(
        icon: .system(action), title: "\(action.title)?", message: warning,
        confirmTitle: action.title, action: .system(action, confirmed: true))
      return
    }
    // The app in front now: the panel never activates Ripcord, so it's still the user's.
    let frontmost = NSWorkspace.shared.frontmostApplication
    // From a hotkey with the panel hidden, whatever was left open there stays to come back to.
    if panel.isVisible { hide() }
    if let message = SystemActions.run(
      action, frontmost: frontmost, report: { [weak self] in self?.onError($0) })
    {
      onError(message)
    }
  }

  /// Off the main thread, as walking the folders takes a moment; the list refreshes when done.
  private func scanRepositories() {
    let settings = repositorySettings
    Task {
      let found = await Task.detached(priority: .userInitiated) {
        RepositoryIndex.scan(
          roots: RepositoryIndex.roots(settings.folders), depth: max(1, settings.depth))
      }.value
      guard settings.folders == repositorySettings.folders,
        settings.depth == repositorySettings.depth
      else { return }
      repositories = found
      if model.mode == .repositories { refreshRows(selecting: model.selected?.id) }
    }
  }

  /// Opens Set Hotkey… or Set Alias… over the panel for the selected row.
  private func openEditor(_ kind: ConfigureEditor.Kind, for key: String) {
    guard let selected = model.selected, let settings else { return NSSound.beep() }
    settings.load()
    if let error = settings.loadError { return onError(error) }
    // In a command's own list the setting is the command's, not the clip's or snippet's.
    let row =
      model.mode.command.flatMap { $0.settingsKey == key ? Search.row(for: $0) : nil } ?? selected
    model.menu = nil
    model.configureEditor = ConfigureEditor(
      kind: kind, settingsKey: key, row: row, selectedID: selected.id,
      alias: items[key]?.alias ?? "",
      hotkey: items[key]?.hotkey)
    guard kind == .hotkey else { return }
    // Ripcord's hotkeys would fire instead of being recorded.
    settings.onRecordingChange(true)
    hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
      [weak self] event in
      self?.record(event, for: key)
      return event.type == .flagsChanged ? event : nil
    }
  }

  /// A key press while Set Hotkey… is open, as Raycast's takes them: Esc goes back, Return
  /// closes, Delete removes the hotkey, and keys with modifiers become the hotkey, shown until
  /// the card closes.
  private func record(_ event: NSEvent, for key: String) {
    guard model.configureEditor?.kind == .hotkey, let settings else { return }
    let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
    if event.type == .flagsChanged {
      model.configureEditor?.modifiers = modifiers
      return
    }
    // Return held from the menu item that opened the card.
    guard !event.isARepeat else { return }
    let bare = modifiers.isEmpty
    switch Int(event.keyCode) {
    case kVK_Escape: return closeEditor(backToMenu: true)
    case kVK_Return where bare: return closeEditor(backToMenu: false)
    case kVK_Delete where bare:
      settings.setHotkey(nil, for: .item(key))
      settings.saveIfChanged()
      model.configureEditor?.problem = settings.loadError
    default:
      model.configureEditor?.problem =
        settings.setHotkey(from: event, for: .item(key)) ?? settings.loadError
    }
    // As the file holds it, so a save that failed doesn't show as set.
    settings.load()
    model.configureEditor?.hotkey = settings.hotkey(of: .item(key))
  }

  private func saveAlias(_ editor: ConfigureEditor) {
    let alias = editor.alias.trimmingCharacters(in: .whitespaces)
    if !editSettings({ $0.setAlias(alias, for: .item(editor.settingsKey)) }) { NSSound.beep() }
    closeEditor(backToMenu: false)
  }

  /// Closes Set Hotkey… or Set Alias…; Set Hotkey…'s Esc goes back to Configure Command.
  private func closeEditor(backToMenu: Bool) {
    guard let editor = model.configureEditor else { return }
    if let hotkeyMonitor {
      NSEvent.removeMonitor(hotkeyMonitor)
      self.hotkeyMonitor = nil
      // Registers the hotkeys again, the new one included.
      settings?.onRecordingChange(false)
    }
    model.configureEditor = nil
    // Saving re-reads the settings, which starts the list over at its first row.
    refreshRows(selecting: editor.selectedID)
    if backToMenu {
      perform(.configureMenu(editor.settingsKey))
    } else if editor.kind == .alias {
      // The alias field had the focus.
      model.searchFieldID += 1
    }
  }

  /// bookmarks.md as it is now; no file yet is an empty list, as looking never creates it.
  private static func readBookmarks() throws -> BookmarkFile {
    let data: Data
    do {
      data = try Data(contentsOf: bookmarksURL)
    } catch CocoaError.fileReadNoSuchFile {
      return BookmarkFile(text: "")
    }
    // Kept as is, a byte order mark included, so a change writes the same bytes back.
    guard let text = String(validating: data, as: UTF8.self) else {
      throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    return BookmarkFile(text: text)
  }

  /// Reads bookmarks.md for the list; false, after saying why, when it can't be read.
  private func loadBookmarks() -> Bool {
    do {
      bookmarks = try Self.readBookmarks()
      return true
    } catch {
      onError("Ripcord can't read bookmarks.md as UTF-8 text: \(error.localizedDescription)")
      return false
    }
  }

  /// Writes bookmarks.md, creating its folder for the first bookmark.
  private static func writeBookmarks(_ file: BookmarkFile) throws {
    // Through a symlink to the file it points at, as dotfiles managers link it, rather than
    // over the link.
    let target = bookmarksURL.resolvingSymlinksInPath()
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(file.text.utf8).write(to: target, options: .atomic)
  }

  private static let changedMessage =
    "bookmarks.md changed since it was read; the list now shows it as it is."

  /// Applies `change` to bookmarks.md as it is now, and writes it: one read and one write. The
  /// changed bookmark's row ID, or nil after saying why nothing was written.
  private func changeBookmarks(
    _ change: (BookmarkFile) throws -> (file: BookmarkFile, line: Int, text: String)
  ) -> String? {
    do {
      let current = try Self.readBookmarks()
      bookmarks = current
      let changed = try change(current)
      try Self.writeBookmarks(changed.file)
      bookmarks = changed.file
      return "bookmark:\(changed.line):\(changed.text)"
    } catch BookmarkFile.EditError.changed {
      guard model.mode == .bookmarkForm else {
        refreshRows(selecting: model.selected?.id)
        onError(Self.changedMessage)
        return nil
      }
      // What's typed stays; the form is set against the file as it is now, so ⌘↵ can save.
      let wasEditing = model.bookmarkDraft.original != nil
      model.bookmarkDraft = rebased(model.bookmarkDraft)
      onError(
        wasEditing && model.bookmarkDraft.original == nil
          ? "bookmarks.md changed, and the bookmark being edited isn't in it any more. Saving now adds it as a new one."
          : "bookmarks.md changed since the form opened. Check the group, then save again.")
    } catch BookmarkFile.EditError.invalid(let message) {
      onError(message)
    } catch {
      onError(error.localizedDescription)
    }
    return nil
  }

  /// Removes the bookmark's line, after reading the file again: a line changed meanwhile isn't
  /// the bookmark shown, so it's left alone.
  private func deleteBookmark(line: Int, text: String) {
    let id = model.selected?.id
    let deleted = changeBookmarks { current in
      guard let file = current.deleting(line: line, text: text) else {
        throw BookmarkFile.EditError.changed
      }
      return (file, line, text)
    }
    if deleted != nil { refreshRows(selecting: id) }
  }

  /// Where a bookmark can go: No group (above the first heading), then the file's headings.
  private func groupChoices() -> [BookmarkFile.Heading] {
    [BookmarkFile.Heading(title: "", line: -1)] + bookmarks.headings
  }

  /// `draft` against bookmarks.md as it is now: its groups read again, its group found again by
  /// name (a new one by that name if it's gone), and an edited bookmark found again by its line.
  private func rebased(_ draft: BookmarkDraft) -> BookmarkDraft {
    var rebased = draft
    rebased.headings = groupChoices()
    // The same line still there, or the one line with its text; two or more could be another.
    rebased.original = draft.original.flatMap { original in
      let same = bookmarks.bookmarks.filter { $0.text == original.text }
      let found = same.first { $0.line == original.line } ?? (same.count == 1 ? same[0] : nil)
      return found.map { ($0.line, $0.text) }
    }
    if let heading = draft.heading {
      let named = rebased.headings.filter { $0.title == heading.title }
      rebased.heading = named.first { $0.line == heading.line } ?? named.first
      if rebased.heading == nil { rebased.newGroup = heading.title }
    }
    return rebased
  }

  /// Opens the form on the bookmark on `line`, if the file still has it there.
  private func editBookmark(line: Int, text: String) {
    guard loadBookmarks() else { return }
    guard let bookmark = bookmarks.bookmarks.first(where: { $0.line == line && $0.text == text })
    else {
      refreshRows(selecting: model.selected?.id)
      return onError(Self.changedMessage)
    }
    // Saving would drop what the form can't show, such as a link title or a note after it.
    guard bookmark.isEditable else {
      return onError(
        "This bookmark's line has text the form doesn't show, which saving would drop; edit it in bookmarks.md instead."
      )
    }
    // A new bookmark being typed waits for Add Bookmark.
    if model.addDraft == nil, model.bookmarkDraft.original == nil, model.bookmarkDraft.isStarted {
      model.addDraft = model.bookmarkDraft
    }
    // The URL as written, not percent-encoded, so an edit leaves it alone.
    model.bookmarkDraft = BookmarkDraft(
      title: bookmark.title, url: bookmark.rawURL, description: bookmark.description ?? "",
      heading: BookmarkFile.Heading(title: bookmark.group, line: bookmark.groupLine),
      headings: groupChoices(), original: (line, text))
    model.mode = .bookmarkForm
    update("")
  }

  /// Saves the form that's open.
  private func saveForm() {
    if model.mode == .snippetForm { return saveDraft() }
    let draft = model.bookmarkDraft
    let destination: BookmarkFile.Destination =
      draft.heading.map { .heading($0) } ?? .newHeading(draft.newGroup)
    guard
      let id = changeBookmarks({
        try $0.saving(
          title: draft.title, url: draft.url, description: draft.description,
          replacing: draft.original, under: destination)
      })
    else { return }
    if draft.original == nil { saveDrafts { $0.bookmark = nil } }
    model.bookmarkDraft = BookmarkDraft()
    // The list, on the bookmark saved, as Raycast shows it after Add Bookmark. An edit came from
    // the list, so Esc does there what it did before.
    if draft.original == nil { closesOnCancel = false }
    model.mode = .bookmarks
    update("")
    refreshRows(selecting: id)
  }

  /// Shows macOS's loupe; the color clicked is copied in the default format and kept in Color
  /// History. Esc cancels it.
  private func pickColor() {
    NSColorSampler().show { [weak self] picked in
      guard let picked, let rgb = picked.usingColorSpace(.sRGB) else { return }
      MainActor.assumeIsolated {
        guard let self else { return }
        let color = PickedColor(
          red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
          blue: Double(rgb.blueComponent))
        do { try self.colors.add(color) } catch { self.onError(error.localizedDescription) }
        self.perform(.copy(self.colorFormat.string(for: color)))
      }
    }
  }

  /// Delete Hotkey and Delete Alias, as changes to the settings; nil for any other action.
  private func deletion(_ action: SearchResult.Action) -> ((SettingsModel) -> Void)? {
    switch action {
    case .deleteHotkey(let key): { $0.setHotkey(nil, for: .item(key)) }
    case .deleteAlias(let key): { $0.setAlias("", for: .item(key)) }
    default: nil
    }
  }

  /// Opens a command's own list, from its row or its hotkey.
  private func open(_ mode: LauncherMode) {
    // A form left for another command's list keeps what was typed.
    if model.mode != mode { stashDraft() }
    // A command's hotkey would change the list under Set Alias…'s card.
    closeEditor(backToMenu: false)
    // Its hotkey closes its own list, as the launcher hotkey closes the panel.
    if panel.isVisible, model.mode == mode { return hide() }
    closesOnCancel = !panel.isVisible
    guard panel.isVisible else { return show(mode) }
    model.mode = mode
    update("")
  }

  /// An edit goes back to Search Snippets, where it started; anything else to the root search.
  private func goBack() {
    stashDraft()
    model.isPickingIcon = false
    if model.mode == .bookmarkForm {
      // An edit goes back to the list, on the bookmark as it was.
      guard let original = model.bookmarkDraft.original, loadBookmarks() else {
        model.mode = .root
        return update("")
      }
      model.mode = .bookmarks
      update("")
      return refreshRows(selecting: "bookmark:\(original.line):\(original.text)")
    }
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
    // Create Snippet with nothing typed since launch picks up the draft left last time; not
    // when it's open already, where its hotkey closes it and an emptied form stays empty.
    if index == nil, !snippetStarted, !(panel.isVisible && model.mode == .snippetForm),
      let saved = draftStore.drafts.snippet
    {
      model.draft = saved
      model.tagsText = draftStore.drafts.snippetTags ?? ""
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
    if editing == nil, model.formSource == nil {
      saveDrafts { drafts in
        drafts.snippet = nil
        drafts.snippetTags = nil
      }
    }
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
  private func paste(_ text: String, copyOnly: Bool, keepingMode: Bool = false) {
    guard copyOnly else {
      hide(keepingMode: keepingMode)
      // After the panel has given the key back to the app being pasted into.
      return clipboard.pasteSnippet(text, after: 0.05)
    }
    let copied = NSPasteboard.general.string(forType: .string) ?? ""
    let expansion = Snippet.expand(text, values: Snippet.values(at: .now), clipboard: copied)
    let concealed = clipboard.isConcealed && text.contains("{clipboard}")
    let written = clipboard.write(expansion.text, transient: false, concealed: concealed)
    hide(keepingMode: keepingMode)
    if !written { NSSound.beep() }
  }

  /// A snippet whose keyword was typed in another app, pasted there in the keyword's place;
  /// `trailing` is the delimiter kept after it.
  func pasteExpansion(_ text: String, trailing: String) {
    clipboard.pasteSnippet(text, trailing: trailing)
  }

  /// `ripcord open`: the panel, with `query` typed if given; one already open stays open.
  func open(query: String?) {
    if !panel.isVisible { show(.root) }
    if let query { update(query) }
  }

  /// The backdrop setting: "off", a built-in shader's name, or a file in the shaders folder.
  var backdrop = Backdrop.off {
    didSet { if backdrop != oldValue { loadBackdrop() } }
  }
  /// Why the chosen backdrop isn't drawing, for Settings; nil when it is.
  var onBackdropError: (String?) -> Void = { _ in }
  static let shadersFolder = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".config/ripcord/shaders")

  /// Reads the chosen shader, again each time the panel shows so a saved edit appears, and
  /// compiles it when its text changed; off, the renderer and its Metal device go.
  func loadBackdrop() {
    let body: String?
    do {
      body = try Backdrop.body(for: backdrop, in: Self.shadersFolder)
    } catch {
      model.backdrop?.fail(error.localizedDescription)
      if model.backdrop == nil { onBackdropError(error.localizedDescription) }
      return
    }
    guard let body else {
      model.backdrop = nil
      return onBackdropError(nil)
    }
    if model.backdrop == nil {
      guard let renderer = BackdropRenderer() else {
        return onBackdropError("This Mac has no Metal device to draw a backdrop with.")
      }
      renderer.onError = { [weak self] message in
        guard let self else { return }
        // Metal calls the source "program_source"; the file's name says which one.
        // The first few lines: a shader with many errors would fill the page.
        onBackdropError(
          message.map {
            $0.replacingOccurrences(of: "program_source", with: backdrop)
              .split(separator: "\n", omittingEmptySubsequences: false).prefix(3)
              .joined(separator: "\n")
          })
      }
      model.backdrop = renderer
    }
    model.backdrop?.load(body)
  }

  /// How long and how many Clipboard History keeps, from the settings.
  var clipboardSettings = ClipboardSettings() {
    didSet { clipboard.apply(clipboardSettings) }
  }

  /// Every entry but the pinned ones gone, from Delete All Entries or Settings' Clear History.
  func clearClipboardHistory() {
    let selected = model.selected?.id
    clipboard.deleteAll()
    if model.mode == .clipboard { refreshRows(selecting: selected) }
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
    case .deleteAll:
      // Asked first: the entries have no undo.
      model.menu = nil
      model.confirmation = Confirmation(
        icon: .command(.clipboardHistory), title: "Delete All Entries?",
        message: "Every entry but the pinned ones is deleted. This can't be undone.",
        confirmTitle: "Delete All", action: .clip(id, .confirmDeleteAll))
    case .confirmDeleteAll:
      model.menu = nil
      clearClipboardHistory()
    }
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
