import AppKit
import Carbon.HIToolbox
import RipcordCore
import Vision

/// Records what's copied anywhere into the clipboard history, and puts history items back.
@MainActor
final class ClipboardMonitor {
  private(set) var history: ClipboardHistory
  var onChange: () -> Void = {}
  /// Off while Clipboard History is switched off on the Shortcuts page; what's copied meanwhile
  /// is never recorded.
  var isEnabled = true {
    didSet { if isEnabled != oldValue { changeCount = pasteboard.changeCount } }
  }
  private let pasteboard: NSPasteboard
  private var changeCount: Int
  private var timer: Timer?

  init(directory: URL, pasteboard: NSPasteboard = .general) {
    history = ClipboardHistory(directory: directory)
    // Nothing trimmed until the settings are read: a config that fails to load would otherwise
    // cut a history kept longer than the default down to it on the next copy.
    history.settings = ClipboardSettings(keepFor: .unlimited, maxEntries: .max)
    self.pasteboard = pasteboard
    // What was copied before launch isn't recorded, as it wasn't seen being copied.
    changeCount = pasteboard.changeCount
  }

  /// macOS posts nothing when the pasteboard changes, so poll its counter, as every clipboard
  /// manager does; one integer read every half second.
  func start() {
    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    timer.tolerance = 0.2
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func poll() {
    guard isEnabled, pasteboard.changeCount != changeCount else { return }
    changeCount = pasteboard.changeCount
    guard let capture = ClipCapture.read(pasteboard) else { return }
    // shortcut: without the nspasteboard.org marker, a guess. A copy made while a menu bar app's
    // overlay is up (CleanShot X keeps one for seconds after a capture) is credited to that app,
    // and a ⌘C followed within 0.5 s by ⌘Tab to the next app; exact needs a per-app event tap.
    let app = Self.overlayApp() ?? NSWorkspace.shared.frontmostApplication
    let source = ClipCapture.source(pasteboard) ?? app?.bundleIdentifier
    // Disabled Applications: what they copy isn't recorded at all.
    if let source, history.settings.disabledApps.contains(source) { return }
    update { try $0.add(capture, from: source) }
    recognizeImages()
  }

  /// The image whose text is being read, so none is read twice at once.
  private var reading: UUID?

  /// Reads the text in the images not read yet, newest first, one at a time off the main
  /// thread, as Raycast's Text Recognition; a search then finds an image by it.
  private func recognizeImages() {
    guard history.settings.textRecognition, reading == nil,
      let item = history.unreadImages.first, let url = history.imageURL(of: item)
    else { return }
    reading = item.id
    // Marked read first: should Vision bring Ripcord down on this image, the next launch
    // doesn't read it again.
    update { try $0.setRecognizedText("", for: item.id) }
    let accurate = history.settings.recognitionMode == .accurate
    Task { [weak self] in
      let text = await Task.detached(priority: .utility) {
        // shortcut: Fast finds nothing at all on macOS 27, so an empty Fast read is read again
        // as Accurate; drop the second read once Fast works again.
        let fast = accurate ? nil : Self.text(in: url, accurate: false)
        return fast?.isEmpty == false ? fast : Self.text(in: url, accurate: true)
      }.value
      guard let self else { return }
      reading = nil
      if let text, !text.isEmpty { update { try $0.setRecognizedText(text, for: item.id) } }
      recognizeImages()
    }
  }

  nonisolated private static func text(in url: URL, accurate: Bool) -> String? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = accurate ? .accurate : .fast
    // Language correction stays on: off, Fast recognition crashes inside Vision on macOS 27.
    // Accurate reads the languages the user reads first, Japanese among them; Fast knows only
    // Latin scripts, its default.
    if accurate, let supported = try? request.supportedRecognitionLanguages() {
      let preferred = Locale.preferredLanguages.compactMap { language in
        supported.first { $0.hasPrefix(language.prefix(2)) }
      }
      request.recognitionLanguages = Array(NSOrderedSet(array: preferred + ["en-US"])).compactMap {
        $0 as? String
      }
    }
    guard (try? VNImageRequestHandler(url: url).perform([request])) != nil else { return nil }
    return request.results?.compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
  }

  /// A menu bar app with a window above the screen saver level, as CleanShot X shows while and
  /// after it captures. Such apps copy without ever coming to the front.
  private static func overlayApp() -> NSRunningApplication? {
    let windows =
      CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    let screenSaver = Int(CGWindowLevelForKey(.screenSaverWindow))
    return windows.lazy.compactMap { window in
      guard let level = window[kCGWindowLayer as String] as? Int, level > screenSaver,
        let pid = window[kCGWindowOwnerPID as String] as? pid_t,
        let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .accessory
      else { return nil }
      return app
    }.first
  }

  func togglePin(_ id: UUID) { update { try $0.togglePin(id) } }
  func delete(_ id: UUID) { update { try $0.delete(id) } }
  func deleteAll() { update { try $0.deleteAll() } }
  /// Drops what the settings no longer keep: older entries, and those past the most kept.
  func prune() { update { try $0.prune() } }

  func apply(_ settings: ClipboardSettings) {
    // Turned on, or at launch: the images copied while it was off are read, settings changed
    // or not.
    defer { recognizeImages() }
    guard settings != history.settings else { return }
    update {
      $0.settings = settings
      try $0.prune()
    }
  }

  private func update(_ change: (inout ClipboardHistory) throws -> Void) {
    do {
      try change(&history)
    } catch {
      // Not worth an alert on every copy; the item is still in memory for this session.
      NSLog("Ripcord: couldn't save the clipboard history: \(error)")
    }
    onChange()
  }

  /// Puts `id` on the pasteboard and, unless Update History After Action is off, moves it to the
  /// top of the history.
  func copy(_ id: UUID) -> Bool {
    guard let item = history.item(id) else { return false }
    let written: Bool
    switch item.content {
    case .text(let text):
      pasteboard.clearContents()
      written = pasteboard.setString(text, forType: .string)
    case .image:
      // Read before clearing, so a missing file leaves what the user has copied alone.
      guard let url = history.imageURL(of: item), let data = try? Data(contentsOf: url) else {
        return false
      }
      switch url.pathExtension {
      case "png":
        pasteboard.clearContents()
        written = pasteboard.setData(data, forType: .png)
      case "tiff":
        pasteboard.clearContents()
        written = pasteboard.setData(data, forType: .tiff)
      default:
        // A JPEG or HEIC from a copied file goes back as an image every app can paste.
        guard let image = NSImage(data: data) else { return false }
        pasteboard.clearContents()
        written = pasteboard.writeObjects([image])
      }
    case .files(let paths):
      // Those still there, as Finder puts copied files: an app pastes the files themselves.
      let urls = paths.filter { FileManager.default.fileExists(atPath: $0) }
        .map { URL(fileURLWithPath: $0) as NSURL }
      guard !urls.isEmpty else { return false }
      pasteboard.clearContents()
      written = pasteboard.writeObjects(urls)
    }
    // Ripcord's own write isn't a new copy; count it here instead of on the next poll.
    changeCount = pasteboard.changeCount
    if written, history.settings.updateAfterAction { update { try $0.touch(id) } }
    return written
  }

  /// Puts a snippet's `text` on the pasteboard without recording it, as its {clipboard} may hold
  /// what a password manager kept out of the history. The markers tell other clipboard managers
  /// the same: `transient` for a paste that's undone right after, `concealed` for a password.
  func write(_ text: String, transient: Bool, concealed: Bool) -> Bool {
    pasteboard.clearContents()
    let written = pasteboard.setString(text, forType: .string)
    pasteboard.setString(
      Bundle.main.bundleIdentifier ?? "", forType: .init("org.nspasteboard.source"))
    if transient { pasteboard.setString("", forType: .init("org.nspasteboard.TransientType")) }
    if concealed { pasteboard.setString("", forType: .init("org.nspasteboard.ConcealedType")) }
    changeCount = pasteboard.changeCount
    return written
  }

  /// Whether what's copied now is a password manager's, by the nspasteboard.org convention.
  var isConcealed: Bool {
    pasteboard.types?.contains(.init("org.nspasteboard.ConcealedType")) ?? false
  }

  /// Everything on the pasteboard, every type of every item, to put back after a paste.
  func snapshot() -> [NSPasteboardItem] {
    (pasteboard.pasteboardItems ?? []).map { item in
      let copy = NSPasteboardItem()
      for type in item.types {
        if let data = item.data(forType: type) { copy.setData(data, forType: type) }
      }
      return copy
    }
  }

  /// Puts back a `snapshot()`, again without recording it.
  func restore(_ items: [NSPasteboardItem]) {
    pasteboard.clearContents()
    if !items.isEmpty { pasteboard.writeObjects(items) }
    changeCount = pasteboard.changeCount
  }

  /// What was copied before a snippet's paste, put back once the app has read it. Kept while
  /// another paste comes first, so the first snippet isn't taken for what was copied.
  private var pendingRestore: [NSPasteboardItem]?
  private var restoreRequest = 0

  /// Pastes a snippet into the frontmost app after `delay`, its placeholders filled, without
  /// recording it in the history; what was copied goes back once the app has read it.
  /// `trailing` follows it, as a delimiter kept after a keyword. Beeps when it can't.
  func pasteSnippet(_ text: String, trailing: String = "", after delay: TimeInterval = 0) {
    let saved = pendingRestore ?? snapshot()
    // Read before writing, which replaces what {clipboard} stands for.
    let copied =
      saved.lazy.compactMap { $0.string(forType: .string) }.first
      ?? pasteboard.string(forType: .string) ?? ""
    let expansion = Snippet.expand(text, values: Snippet.values(at: .now), clipboard: copied)
    let concealed = isConcealed && text.contains("{clipboard}")
    guard write(expansion.text + trailing, transient: true, concealed: concealed) else {
      return NSSound.beep()
    }
    pendingRestore = saved
    restoreRequest += 1
    let request = restoreRequest
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
      // The caret goes back to {cursor}, past the kept delimiter too; without one it stays at
      // the end, after the delimiter.
      let left = text.contains("{cursor}") ? expansion.charactersAfterCursor + trailing.count : 0
      guard pasteIntoFrontmostApp(thenLeft: left) else {
        // Not pasted (no Accessibility yet): put back what was copied, or the retry after
        // granting it would fill {clipboard} with this snippet.
        pendingRestore = nil
        restore(saved)
        return NSSound.beep()
      }
      // shortcut: the app reads the pasteboard when it handles ⌘V, which 0.5 s covers for
      // ordinary apps; a hung app would paste what was copied before. Wait for it if one does.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
        // A later paste puts it back instead.
        guard request == restoreRequest else { return }
        pendingRestore = nil
        restore(saved)
      }
    }
  }

  /// Presses ⌘V in the frontmost app. Without the Accessibility permission, asks for it and
  /// returns false, leaving the item copied.
  /// `left` presses ← that many times after, for a snippet's `{cursor}`.
  func pasteIntoFrontmostApp(thenLeft left: Int = 0) -> Bool {
    guard AccessibilityPermission.check().trusted else { return false }
    let source = CGEventSource(stateID: .combinedSessionState)
    // ⌘ itself pressed and let go around V: a V merely flagged ⌘ leaves the system holding ⌘
    // down, so the next key posted, or read by an app, comes with ⌘ (a q quitting the app).
    func command(_ isDown: Bool) {
      let event = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: isDown)
      event?.type = .flagsChanged
      event?.flags = isDown ? .maskCommand : []
      event?.post(tap: .cghidEventTap)
    }
    command(true)
    // shortcut: ⌘ plus the key at V's position on a US layout; a Dvorak user needs a layout lookup.
    for isDown in [true, false] {
      let event = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isDown)
      event?.flags = .maskCommand
      event?.post(tap: .cghidEventTap)
    }
    command(false)
    // Queued after ⌘V, so the app moves the caret back once the text is in.
    // shortcut: counts the snippet's characters, so an app that reformats a paste (re-indents,
    // turns tabs into spaces) ends off by that much, and ← doesn't cross lines in a terminal;
    // set the caret through Accessibility (kAXSelectedTextRange) if that bites. Past 2,000
    // characters after {cursor} it stops pressing, rather than flood the app with events.
    for _ in 0..<min(left, 2_000) {
      for isDown in [true, false] {
        let event = CGEvent(
          keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: isDown)
        // Set outright, as a real arrow key sends them, so a ⌘ or ⇧ still held can't turn ←
        // into ⌘← or ⇧←.
        event?.flags = [.maskNumericPad, .maskSecondaryFn]
        event?.post(tap: .cghidEventTap)
      }
    }
    return true
  }
}

/// macOS's Accessibility request, made once per launch by whichever feature needs it first, so a
/// dismissed request doesn't come back on every paste or media key.
@MainActor
enum AccessibilityPermission {
  private static var hasAsked = false

  /// Whether Ripcord may post keys. `asked` is true when this call put up macOS's request.
  static func check() -> (trusted: Bool, asked: Bool) {
    let asking = !hasAsked
    hasAsked = true
    // The key's name, spelled out: kAXTrustedCheckOptionPrompt is a global var Swift 6 rejects.
    let trusted = AXIsProcessTrustedWithOptions(
      ["AXTrustedCheckOptionPrompt": asking] as CFDictionary)
    return (trusted, asking && !trusted)
  }
}
