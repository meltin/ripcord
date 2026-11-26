import AppKit
import Carbon

/// The macOS permissions Ripcord's features need, with their state and a way to grant each.
enum Permission: CaseIterable, Identifiable {
  case accessibility, finder, systemEvents, loginWindow

  var id: Self { self }

  var title: String {
    switch self {
    case .accessibility: "Accessibility"
    case .finder: "Control Finder"
    case .systemEvents: "Control System Events"
    case .loginWindow: "Control the Login Window"
    }
  }

  /// What uses it.
  var purpose: String {
    switch self {
    case .accessibility:
      "Pasting, the music and volume keys, and Window Management."
    case .finder: "Empty Trash."
    case .systemEvents: "Toggle System Appearance."
    case .loginWindow: "Log Out, Restart and Shut Down."
    }
  }

  var symbol: String {
    switch self {
    case .accessibility: "accessibility"
    case .finder: "folder.fill"
    case .systemEvents: "circle.lefthalf.filled"
    case .loginWindow: "power"
    }
  }

  /// The app an Automation permission is for; nil for Accessibility.
  var bundleIdentifier: String? {
    switch self {
    case .accessibility: nil
    case .finder: "com.apple.finder"
    case .systemEvents: "com.apple.systemevents"
    case .loginWindow: "com.apple.loginwindow"
    }
  }

  enum Status {
    case granted, denied, notAsked
    /// The app to be controlled isn't running, so macOS can't say yet; it asks on first use.
    case unknown
  }

  /// Off the main thread: asking about Automation waits on the other app.
  func status() async -> Status {
    guard let bundleIdentifier else {
      return AXIsProcessTrusted() ? .granted : .notAsked
    }
    return await Task.detached { Self.automation(bundleIdentifier, ask: false) }.value
  }

  /// Puts up macOS's request where it can, which it shows only while undecided; once denied,
  /// only System Settings can change it.
  func request() async {
    guard let bundleIdentifier else {
      _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
      return
    }
    // System Events only answers while running.
    if self == .systemEvents,
      NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      ).isEmpty,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
    _ = await Task.detached { Self.automation(bundleIdentifier, ask: true) }.value
  }

  /// The Privacy & Security pane that lists it.
  func openSystemSettings() {
    let anchor = self == .accessibility ? "Privacy_Accessibility" : "Privacy_Automation"
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    {
      NSWorkspace.shared.open(url)
    }
  }

  /// Forgets the Accessibility grant and asks again: an ad-hoc signed build is a new app to
  /// macOS, so the grant an earlier build got no longer applies to it.
  static func resetAccessibility() {
    let reset = Process()
    reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
    reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? ""]
    try? reset.run()
    reset.waitUntilExit()
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  private static func automation(_ bundleIdentifier: String, ask: Bool) -> Status {
    var target = AEAddressDesc()
    guard let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier).aeDesc,
      AEDuplicateDesc(descriptor, &target) == noErr
    else { return .unknown }
    defer { AEDisposeDesc(&target) }
    // Any event: the permission covers the app, not one command.
    let wildcard = AEEventClass(typeWildCard)
    switch AEDeterminePermissionToAutomateTarget(&target, wildcard, AEEventID(wildcard), ask) {
    case noErr: return .granted
    case OSStatus(errAEEventNotPermitted): return .denied
    case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
    default: return .unknown
    }
  }
}
