import AppKit
import Carbon
import RipcordCore

/// Typing a snippet's keyword in any app replaces it with the snippet, as Raycast's Snippets do.
/// It watches keys through AppKit's global monitor, which the Accessibility permission Ripcord
/// already asks for covers; keys typed into password fields never reach it.
@MainActor
final class SnippetExpander {
  /// Pastes a snippet's text, then `trailing`, where the keyword was.
  var onExpand: (_ text: String, _ trailing: String) -> Void = { _, _ in }

  private var settings = SnippetExpansion()
  private var snippets: [Snippet] = []
  private var matcher = KeywordMatcher()
  private var monitors: [Any] = []
  private var appObserver: NSObjectProtocol?
  private var windowObserver: NSObjectProtocol?
  /// Marks the Backspaces it sends, so the monitor doesn't take them for typing.
  private static let marker: Int64 = 0x5269_7063

  func apply(_ config: Config) {
    settings = config.snippetExpansion
    snippets = config.snippets.filter { $0.keyword?.isEmpty == false }
    matcher.reset()
    let wanted = settings.isEnabled && !snippets.isEmpty
    if wanted, monitors.isEmpty {
      start()
    } else if !wanted, !monitors.isEmpty {
      stop()
    }
  }

  private func start() {
    let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      MainActor.assumeIsolated { self?.handle(event) }
    }
    // A click may move the caret anywhere.
    let clicks = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.matcher.reset() }
    }
    monitors = [keys, clicks].compactMap { $0 }
    let reset: @Sendable (Notification) -> Void = { [weak self] _ in
      MainActor.assumeIsolated { self?.matcher.reset() }
    }
    appObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main,
      using: reset)
    // Ripcord's panel and Notes take keys the global monitor never sees.
    windowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main, using: reset)
  }

  private func stop() {
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    appObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
    windowObserver.map(NotificationCenter.default.removeObserver)
    appObserver = nil
    windowObserver = nil
  }

  private func handle(_ event: NSEvent) {
    if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.marker { return }
    // Shortcuts, other apps' settings and kana input all leave the caret's text unknown.
    guard event.modifierFlags.isDisjoint(with: [.command, .control]), Self.isTypingASCII,
      let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
      !settings.disabledApps.contains(app)
    else { return matcher.reset() }
    if event.keyCode == UInt16(kVK_Delete) { return matcher.deleteBackward() }
    guard let characters = event.characters, !characters.isEmpty,
      // Arrows, Home, Escape and the like move the caret or leave the text.
      !characters.unicodeScalars.contains(where: { (0xF700...0xF8FF).contains($0.value) }),
      event.keyCode != UInt16(kVK_Escape), event.keyCode != UInt16(kVK_ForwardDelete)
    else { return matcher.reset() }
    let keywords = snippets.compactMap(\.keyword)
    for character in characters {
      guard
        let match = matcher.type(
          character, keywords: keywords, mode: settings.mode,
          withinWords: settings.expandsWithinWords),
        let snippet = snippets.first(where: { $0.keyword == match.keyword })
      else { continue }
      return expand(snippet, taking: match)
    }
  }

  /// Takes the keyword back with Backspaces, then pastes the snippet in its place.
  private func expand(_ snippet: Snippet, taking match: KeywordMatcher.Match) {
    guard AccessibilityPermission.check().trusted else { return }
    let source = CGEventSource(stateID: .combinedSessionState)
    for _ in 0..<match.deleting {
      for isDown in [true, false] {
        let event = CGEvent(
          keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: isDown)
        // None, as a real Backspace sends them: a held ⌥ or ⌘ would take a word or a line.
        event?.flags = []
        event?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event?.post(tap: .cghidEventTap)
      }
    }
    onExpand(snippet.text, match.trailing)
  }

  /// Whether keys type what they say: an English layout, or an input method in its ASCII mode,
  /// not Japanese kana, whose keystrokes are still being composed.
  private static var isTypingASCII: Bool {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
    else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
  }
}
