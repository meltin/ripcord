import Carbon.HIToolbox
import RipcordCore

/// System-wide hotkeys through Carbon, which needs no Accessibility permission. Each one carries
/// its index as the Carbon hotkey ID, so the shared handler knows which was pressed.
@MainActor
enum GlobalHotKey {
  private static var registered: [EventHotKeyRef] = []
  private static var actions: [() -> Void] = []
  private static var handlerInstalled = false

  /// Registers `entries` in place of the current set and returns the failures by index.
  /// macOS refuses only a clash inside Ripcord (eventHotKeyExistsErr); another app holding the
  /// same keys still registers, so `Config.owner(of:except:)` guards against the first kind.
  static func set(_ entries: [(hotkey: Hotkey, action: () -> Void)]) -> [Int: OSStatus] {
    installHandler()
    unregisterAll()
    var failures: [Int: OSStatus] = [:]
    for (index, entry) in entries.enumerated() {
      var ref: EventHotKeyRef?
      let id = EventHotKeyID(signature: OSType(0x5250_4344), id: UInt32(index))  // "RPCD"
      let status = RegisterEventHotKey(
        entry.hotkey.keyCode, entry.hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
      if status == noErr, let ref { registered.append(ref) } else { failures[index] = status }
    }
    actions = entries.map(\.action)
    return failures
  }

  static func unregisterAll() {
    for ref in registered { UnregisterEventHotKey(ref) }
    registered = []
    actions = []
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
