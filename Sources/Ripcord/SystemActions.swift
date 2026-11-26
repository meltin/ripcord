import AppKit
import Carbon
import IOKit.hidsystem
import RipcordCore

/// Runs System Actions. Each returns nil when done, or a message to show when it couldn't be.
@MainActor
enum SystemActions {
  /// `frontmost` is the app the user was in when they asked.
  static func run(_ action: SystemAction, frontmost: NSRunningApplication?) -> String? {
    switch action {
    case .lockScreen:
      return lockScreen()
    case .logOut:
      return sendToLoginWindow(AEEventID(kAEReallyLogOut))
    case .restart:
      return sendToLoginWindow(AEEventID(kAERestart))
    case .shutDown:
      return sendToLoginWindow(AEEventID(kAEShutDown))
    case .sleep:
      return pmset("sleepnow")
    case .sleepDisplays:
      return pmset("displaysleepnow")
    case .playPause:
      return pressMediaKey(NX_KEYTYPE_PLAY)
    case .nextTrack:
      return pressMediaKey(NX_KEYTYPE_NEXT)
    case .previousTrack:
      return pressMediaKey(NX_KEYTYPE_PREVIOUS)
    case .toggleMute:
      return pressMediaKey(NX_KEYTYPE_MUTE)
    case .volumeUp:
      return pressMediaKey(NX_KEYTYPE_SOUND_UP)
    case .volumeDown:
      return pressMediaKey(NX_KEYTYPE_SOUND_DOWN)
    case .hideOtherApps:
      guard let frontmost = userApp(frontmost) else { return noFrontmostApp }
      for app in regularApps() where app != frontmost { app.hide() }
      return nil
    case .unhideAllApps:
      for app in regularApps() { app.unhide() }
      return nil
    case .quitAllApps:
      for app in quittableApps() { app.terminate() }
      return nil
    case .quitOtherApps:
      guard let frontmost = userApp(frontmost) else { return noFrontmostApp }
      for app in quittableApps() where app != frontmost { app.terminate() }
      return nil
    case .restartFrontmostApp:
      guard let frontmost = userApp(frontmost) else { return noFrontmostApp }
      return relaunch(frontmost)
    case .openTrash:
      let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
      return trash.map { NSWorkspace.shared.open($0) } == true ? nil : "Couldn't open the Trash."
    case .emptyTrash:
      return runAppleScript(#"tell application "Finder" to empty trash"#, controlling: "Finder")
    case .ejectAllDisks:
      return ejectAllDisks()
    case .showDesktop:
      return showDesktop()
    case .toggleAppearance:
      return runAppleScript(
        #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#,
        controlling: "System Events")
    case .toggleHiddenFiles:
      return toggleHiddenFiles()
    }
  }

  private static var hasAskedForAccessibility = false

  private static let noFrontmostApp = "There's no app in front to act on."

  /// The app the user was in, if it's an ordinary app and not Ripcord itself (its settings
  /// window makes it frontmost).
  private static func userApp(_ app: NSRunningApplication?) -> NSRunningApplication? {
    guard let app, app.activationPolicy == .regular, app != NSRunningApplication.current else {
      return nil
    }
    return app
  }

  /// Apps with a Dock icon; menu bar apps and input methods are never touched.
  private static func regularApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular && $0 != NSRunningApplication.current
    }
  }

  /// Asked to quit, never forced, so each can ask to save; Finder stays, as quitting it only
  /// makes it come back.
  private static func quittableApps() -> [NSRunningApplication] {
    regularApps().filter { $0.bundleIdentifier != "com.apple.finder" }
  }

  private static func relaunch(_ app: NSRunningApplication) -> String? {
    guard let bundle = app.bundleURL else { return "Couldn't find where the app is." }
    guard app.terminate() else { return "\(app.localizedName ?? "The app") didn't quit." }
    Task { @MainActor in
      // Waits for it to finish quitting, which may include the user answering a save prompt.
      for _ in 0..<600 where !app.isTerminated {
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard app.isTerminated else { return }
      _ = try? await NSWorkspace.shared.openApplication(
        at: bundle, configuration: NSWorkspace.OpenConfiguration())
    }
    return nil
  }

  /// The login window's own private call; there's no public API for locking the screen.
  private static func lockScreen() -> String? {
    typealias Lock = @convention(c) () -> Int32
    guard
      let framework = dlopen(
        "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
      let symbol = dlsym(framework, "SACLockScreenImmediate")
    else { return "Couldn't lock the screen on this version of macOS." }
    _ = unsafeBitCast(symbol, to: Lock.self)()
    return nil
  }

  /// The Dock's notification behind the Show Desktop gesture; there's no public API for it.
  private static func showDesktop() -> String? {
    typealias Send = @convention(c) (CFString, Int32) -> Int32
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification")
    else { return "Couldn't show the desktop on this version of macOS." }
    _ = unsafeBitCast(symbol, to: Send.self)("com.apple.showdesktop.awake" as CFString, 0)
    return nil
  }

  /// Log out, restart and shut down, as Apple's TN2062 has apps ask the login window. Apps still
  /// get to ask to save, and can cancel.
  private static func sendToLoginWindow(_ event: AEEventID) -> String? {
    let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
    let message = NSAppleEventDescriptor(
      eventClass: AEEventClass(kCoreEventClass), eventID: event, targetDescriptor: target,
      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
    )
    do {
      _ = try message.sendEvent(options: [.noReply], timeout: 10)
      return nil
    } catch {
      return automationMessage(for: (error as NSError).code, app: "the login window")
        ?? "Couldn't ask the login window: \(error.localizedDescription)"
    }
  }

  private static func pmset(_ argument: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = [argument]
    do {
      try process.run()
      return nil
    } catch {
      return "Couldn't run pmset: \(error.localizedDescription)"
    }
  }

  /// A keyboard's media key, down then up; posting it needs the Accessibility permission, as
  /// pasting does.
  private static func pressMediaKey(_ key: Int32) -> String? {
    // macOS's request comes up once per launch; after that, the message says where to go.
    let options = ["AXTrustedCheckOptionPrompt": !hasAskedForAccessibility] as CFDictionary
    hasAskedForAccessibility = true
    guard AXIsProcessTrustedWithOptions(options) else {
      return
        "Allow Ripcord under System Settings › Privacy & Security › Accessibility, then try again."
    }
    for isDown in [true, false] {
      // NX_SUBTYPE_AUX_CONTROL_BUTTONS; data1 carries the key and whether it's down (0xA) or up (0xB).
      let state = isDown ? 0xA : 0xB
      NSEvent.otherEvent(
        with: .systemDefined, location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)), timestamp: 0,
        windowNumber: 0, context: nil, subtype: 8, data1: Int(key) << 16 | state << 8,
        data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
    }
    return nil
  }

  private static func ejectAllDisks() -> String? {
    let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey]
    let volumes =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    let ejectable = volumes.filter { url in
      let values = try? url.resourceValues(forKeys: Set(keys))
      return values?.volumeIsEjectable == true || values?.volumeIsRemovable == true
    }
    let failed = ejectable.filter { (try? NSWorkspace.shared.unmountAndEjectDevice(at: $0)) == nil }
    guard !failed.isEmpty else { return nil }
    let names = failed.map { FileManager.default.displayName(atPath: $0.path) }
    return "Couldn't eject \(names.joined(separator: ", ")). Something may be using it."
  }

  /// Flips Finder's AppleShowAllFiles and reopens Finder, which reads it only at launch.
  private static func toggleHiddenFiles() -> String? {
    let key = "AppleShowAllFiles" as CFString
    let domain = "com.apple.finder" as CFString
    let showing = CFPreferencesGetAppBooleanValue(key, domain, nil)
    CFPreferencesSetAppValue(key, (!showing) as CFBoolean, domain)
    CFPreferencesAppSynchronize(domain)
    guard
      let finder = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.finder"
      ).first
    else { return nil }
    return relaunch(finder)
  }

  private static func runAppleScript(_ source: String, controlling app: String) -> String? {
    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)
    guard let error else { return nil }
    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
    return automationMessage(for: code, app: app)
      ?? (error[NSAppleScript.errorMessage] as? String ?? "Couldn't ask \(app).")
  }

  /// errAEEventNotPermitted: the user said no to, or hasn't yet been asked about, Automation.
  private static func automationMessage(for code: Int, app: String) -> String? {
    guard code == -1743 else { return nil }
    return
      "Allow Ripcord to control \(app) under System Settings › Privacy & Security › Automation, then try again."
  }
}
