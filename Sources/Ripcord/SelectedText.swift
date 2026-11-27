import AppKit

/// The text selected in the app in front, read through Accessibility, which Window Management
/// already has. The clipboard is never touched.
enum SelectedText {
  /// Nil when nothing is selected, Ripcord is in front, or the app doesn't say.
  static func inFrontApp() -> String? {
    guard let app = NSWorkspace.shared.frontmostApplication, app != .current else { return nil }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    // An app that hangs mustn't hold the hotkey up.
    AXUIElementSetMessagingTimeout(application, 0.5)
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { return nil }
    var selected: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        unsafeDowncast(focused, to: AXUIElement.self), kAXSelectedTextAttribute as CFString,
        &selected) == .success,
      let text = selected as? String
    else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
