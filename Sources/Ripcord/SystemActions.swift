import AppKit
import AudioToolbox
import Carbon
import IOKit.hidsystem
import RipcordCore

/// Runs System Actions. Each returns nil when done, or a message to show when it couldn't be;
/// ones that wait on another app or a disk run off the main thread and `report` a problem later.
@MainActor
enum SystemActions {
  /// The default output's volume set to `percent`, and unmuted above 0; a message when the device
  /// has no volume to set, as some do.
  static func setVolume(percent: Int) -> String? {
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var defaultOutput = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &defaultOutput, 0, nil, &size, &device) == noErr,
      device != kAudioObjectUnknown
    else { return "There's no sound output to set." }
    var volume = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    var level = Float32(min(max(percent, 0), 100)) / 100
    guard
      AudioObjectSetPropertyData(
        device, &volume, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr
    else { return "This sound output's volume can't be set." }
    var mute = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain)
    if percent > 0, AudioObjectHasProperty(device, &mute) {
      var off: UInt32 = 0
      AudioObjectSetPropertyData(device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
    }
    return nil
  }

  /// `frontmost` is the app the user was in when they asked.
  static func run(
    _ action: SystemAction, frontmost: NSRunningApplication?,
    report: @escaping @MainActor (String) -> Void
  ) -> String? {
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
    case .showScreenSaver:
      // macOS's own, which ends on the next key or move as set in System Settings.
      let engine = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
      return NSWorkspace.shared.open(engine) ? nil : "Couldn't start the screen saver."
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
    case .setVolume:
      return nil  // Asks for a level first, in the launcher.
    case .setVolume0, .setVolume25, .setVolume50, .setVolume75, .setVolume100:
      return setVolume(percent: action.volumePercent ?? 0)
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
      return runAppleScript(
        #"tell application "Finder" to empty trash"#, controlling: "Finder", report: report)
    case .ejectAllDisks:
      return ejectAllDisks(report: report)
    case .showDesktop:
      return showDesktop()
    case .toggleAppearance:
      return runAppleScript(
        #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#,
        controlling: "System Events", report: report)
    case .toggleHiddenFiles:
      return toggleHiddenFiles()
    }
  }

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
      // Ten seconds, not longer: an app whose save prompt was cancelled stays open, and one
      // quit by hand much later mustn't come back unasked.
      for _ in 0..<100 where !app.isTerminated {
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
    typealias Send = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification")
    else { return "Couldn't show the desktop on this version of macOS." }
    unsafeBitCast(symbol, to: Send.self)("com.apple.showdesktop.awake" as CFString, nil)
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
    let permission = AccessibilityPermission.check()
    guard permission.trusted else {
      // macOS's own request is up; a message on top of it would only cover it.
      if permission.asked {
        NSSound.beep()
        return nil
      }
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

  /// Off the main thread, as ejecting waits on the disk. A volume already gone counts as
  /// ejected: ejecting one volume takes the others on the same disk with it.
  private static func ejectAllDisks(report: @escaping @MainActor (String) -> Void) -> String? {
    let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey]
    let volumes =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    let ejectable = volumes.filter { url in
      let values = try? url.resourceValues(forKeys: Set(keys))
      return values?.volumeIsEjectable == true || values?.volumeIsRemovable == true
    }
    Task.detached {
      let failed = ejectable.filter { url in
        guard (try? NSWorkspace.shared.unmountAndEjectDevice(at: url)) == nil else { return false }
        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil)
        return mounted?.contains(url) == true
      }
      guard !failed.isEmpty else { return }
      let names = failed.map { FileManager.default.displayName(atPath: $0.path) }
      await report("Couldn't eject \(names.joined(separator: ", ")). Something may be using it.")
    }
    return nil
  }

  /// Flips Finder's AppleShowAllFiles and reopens Finder, which reads it only at launch.
  private static func toggleHiddenFiles() -> String? {
    let key = "AppleShowAllFiles" as CFString
    let domain = "com.apple.finder" as CFString
    let showing = CFPreferencesGetAppBooleanValue(key, domain, nil)
    func set(_ value: Bool) {
      CFPreferencesSetAppValue(key, value as CFBoolean, domain)
      CFPreferencesAppSynchronize(domain)
    }
    set(!showing)
    guard
      let finder = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.finder"
      ).first
    else { return nil }
    // Finder only reads it at launch; if it won't quit, the setting goes back to what it shows.
    let problem = relaunch(finder)
    if problem != nil { set(showing) }
    return problem
  }

  /// Through osascript, off the main thread: the script waits for the app to answer, which
  /// for a full Trash can take minutes. macOS still credits Ripcord, which launched it, when it
  /// asks for the Automation permission.
  private static func runAppleScript(
    _ source: String, controlling app: String, report: @escaping @MainActor (String) -> Void
  ) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source]
    let errors = Pipe()
    process.standardError = errors
    let output = errors.fileHandleForReading
    process.terminationHandler = { process in
      guard process.terminationStatus != 0 else { return }
      let text = String(decoding: output.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      Task { @MainActor in
        report(
          automationMessage(for: text.contains("-1743") ? -1743 : 0, app: app)
            ?? "Couldn't ask \(app): \(text)")
      }
    }
    do {
      try process.run()
      return nil
    } catch {
      return "Couldn't run osascript: \(error.localizedDescription)"
    }
  }

  /// errAEEventNotPermitted: the user said no to, or hasn't yet been asked about, Automation.
  private static func automationMessage(for code: Int, app: String) -> String? {
    guard code == -1743 else { return nil }
    return
      "Allow Ripcord to control \(app) under System Settings › Privacy & Security › Automation, then try again."
  }
}
