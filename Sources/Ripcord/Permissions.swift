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
    // An app answers only while running; Finder or System Events may have quit.
    if NSRunningApplication.runningApplications(
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
  static func resetAccessibility() async {
    // Never without an ID: tccutil with none resets every app's Accessibility grant.
    guard let id = Bundle.main.bundleIdentifier, !id.isEmpty else { return }
    await Task.detached {
      let reset = Process()
      reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
      reset.arguments = ["reset", "Accessibility", id]
      try? reset.run()
      reset.waitUntilExit()
    }.value
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  private static func automation(_ bundleIdentifier: String, ask: Bool) -> Status {
    var target = AEAddressDesc()
    guard let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier).aeDesc,
      AEDuplicateDesc(descriptor, &target) == noErr
    else { return .unknown }
    defer { AEDisposeDesc(&target) }
    // A concrete event: the permission covers the whole app, and macOS may only answer, never
    // ask, for the wildcard.
    switch AEDeterminePermissionToAutomateTarget(
      &target, AEEventClass(kCoreEventClass), AEEventID(kAEOpenApplication), ask)
    {
    case noErr: return .granted
    case OSStatus(errAEEventNotPermitted): return .denied
    case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
    default: return .unknown
    }
  }
}
