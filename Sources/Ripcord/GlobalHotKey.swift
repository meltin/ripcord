import Carbon.HIToolbox
import RipcordCore

struct HotKeyError: Error, CustomStringConvertible {
  let status: OSStatus
  var description: String {
    status == eventHotKeyExistsErr
      ? "Another app already uses this hotkey. Pick another in the config file."
      : "Couldn't register the hotkey (OSStatus \(status))."
  }
}

/// One system-wide hotkey through Carbon, which needs no Accessibility permission.
@MainActor
enum GlobalHotKey {
  private static var registered: EventHotKeyRef?
  private static var action: (() -> Void)?
  private static var handlerInstalled = false

  /// Replaces the current hotkey only once the new one is registered, so a failure keeps the old.
  static func register(_ hotkey: Hotkey, action: @escaping () -> Void) throws {
    installHandler()
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x5250_4344), id: 1)  // "RPCD"
    let status = RegisterEventHotKey(
      hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    guard status == noErr else { throw HotKeyError(status: status) }
    if let registered { UnregisterEventHotKey(registered) }
    registered = ref
    self.action = action
  }

  private static func installHandler() {
    guard !handlerInstalled else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        // Carbon delivers application-target events on the main thread.
        MainActor.assumeIsolated { GlobalHotKey.action?() }
        return noErr
      }, 1, &eventType, nil, nil)
    handlerInstalled = true
  }
}
