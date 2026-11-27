import AppKit
import Carbon.HIToolbox
import RipcordCore

/// System-wide hotkeys through Carbon, which needs no Accessibility permission. Each one carries
/// its index as the Carbon hotkey ID, so the shared handler knows which was pressed. A double
/// tap such as ⇧⇧ can't be a Carbon hotkey; AppKit's event monitors spot it instead, as snippet
/// expansion does, which takes Accessibility.
@MainActor
enum GlobalHotKey {
  /// The failure of a double-tap hotkey while Ripcord lacks Accessibility.
  static let needsAccessibility: OSStatus = -1

  private static var registered: [EventHotKeyRef] = []
  private static var actions: [() -> Void] = []
  private static var handlerInstalled = false
  /// Each double-tapped modifier's index in `actions`.
  private static var doubleTaps: [UInt32: Int] = [:]
  private static var tapMonitors: [Any] = []
  private static var detector = DoubleTapDetector()

  /// Registers `entries` in place of the current set and returns the failures by index.
  /// macOS refuses only a clash inside Ripcord (eventHotKeyExistsErr); another app holding the
  /// same keys still registers, so `Config.owner(of:except:)` guards against the first kind.
  static func set(_ entries: [(hotkey: Hotkey, action: () -> Void)]) -> [Int: OSStatus] {
    installHandler()
    unregisterAll()
    var failures: [Int: OSStatus] = [:]
    for (index, entry) in entries.enumerated() {
      if entry.hotkey.isDoubleTap {
        doubleTaps[entry.hotkey.modifiers] = index
        // Watched anyway, so it works as soon as the permission is granted.
        if !AXIsProcessTrusted() { failures[index] = needsAccessibility }
        continue
      }
      var ref: EventHotKeyRef?
      let id = EventHotKeyID(signature: OSType(0x5250_4344), id: UInt32(index))  // "RPCD"
      let status = RegisterEventHotKey(
        entry.hotkey.keyCode, entry.hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
      if status == noErr, let ref { registered.append(ref) } else { failures[index] = status }
    }
    actions = entries.map(\.action)
    if !doubleTaps.isEmpty { watchTaps() }
    return failures
  }

  static func unregisterAll() {
    for ref in registered { UnregisterEventHotKey(ref) }
    registered = []
    actions = []
    doubleTaps = [:]
    tapMonitors.forEach(NSEvent.removeMonitor)
    tapMonitors = []
  }

  /// ⌃⌥⇧⌘ as Carbon's flags, the form `Hotkey` keeps.
  static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    let pairs: [(NSEvent.ModifierFlags, Int)] = [
      (.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey),
    ]
    return pairs.filter { flags.contains($0.0) }.map { UInt32($0.1) }.reduce(0, |)
  }

  /// Other apps' keys through the global monitor, and the panel's and Settings' own through
  /// the local one, which the global monitor never sees.
  private static func watchTaps() {
    guard tapMonitors.isEmpty else { return }
    detector = DoubleTapDetector()
    let types: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
    let global = NSEvent.addGlobalMonitorForEvents(matching: types) { event in
      MainActor.assumeIsolated { handleTap(event) }
    }
    let local = NSEvent.addLocalMonitorForEvents(matching: types) { event in
      MainActor.assumeIsolated { handleTap(event) }
      return event
    }
    tapMonitors = [global, local].compactMap { $0 }
  }

  private static func handleTap(_ event: NSEvent) {
    // Without Accessibility or under a password field's secure input, key presses don't arrive
    // while modifiers still may, so capitals typed with ⇧ would look like taps.
    guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
      detector = DoubleTapDetector()
      return
    }
    if event.type == .keyDown { return detector.keyPressed() }
    guard
      let modifier = detector.modifiersChanged(
        to: carbonModifiers(event.modifierFlags), at: event.timestamp),
      let index = doubleTaps[modifier], actions.indices.contains(index)
    else { return }
    actions[index]()
  }

  private static func installHandler() {
    guard !handlerInstalled else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        var id = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &id)
        // Carbon delivers application-target events on the main thread.
        MainActor.assumeIsolated {
          let index = Int(id.id)
          if GlobalHotKey.actions.indices.contains(index) { GlobalHotKey.actions[index]() }
        }
        return noErr
      }, 1, &eventType, nil, nil)
    handlerInstalled = true
  }
}
