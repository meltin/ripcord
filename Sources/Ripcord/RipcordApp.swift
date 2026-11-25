import AppKit
import RipcordCore

@main
@MainActor
enum RipcordApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // NSApplication holds its delegate weakly.
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".config/ripcord/config.json")
  private let launcher = LauncherController()
  private var statusItem: NSStatusItem?
  private var registeredHotkey: String?

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem = makeStatusItem()
    launcher.onEditConfig = { [weak self] in self?.editConfig() }
    applyConfig()
  }

  /// Opening Ripcord.app again shows the panel, a way in when the hotkey or menu bar icon fails.
  func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !launcher.isVisible { toggleLauncher() }
    return false
  }

  @objc private func toggleLauncher() {
    if !launcher.isVisible { applyConfig() }
    launcher.toggle()
  }

  @objc private func editConfig() {
    NSWorkspace.shared.open(configURL)
  }

  /// Re-read on every show so edits to the file apply without a restart.
  private func applyConfig() {
    do {
      let config = try Config.load(from: configURL)
      launcher.quicklinks = config.quicklinks
      guard config.hotkey != registeredHotkey else { return }
      guard let hotkey = Hotkey(config.hotkey) else {
        return showError("\"\(config.hotkey)\" is not a hotkey. Use a form like \"option+space\".")
      }
      try GlobalHotKey.register(hotkey) { [weak self] in self?.toggleLauncher() }
      registeredHotkey = config.hotkey
    } catch {
      showError("\(configURL.path):\n\(error)")
    }
  }

  private func makeStatusItem() -> NSStatusItem {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    // The bundle has the icon; a bare `swift run` doesn't, so fall back to a symbol there.
    let icon =
      Bundle.main.image(forResource: "MenuBarIcon")
      ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
    icon?.isTemplate = true
    icon?.accessibilityDescription = "Ripcord"
    item.button?.image = icon
    let menu = NSMenu()
    menu.addItem(withTitle: "Open Ripcord", action: #selector(toggleLauncher), keyEquivalent: "")
    menu.addItem(withTitle: "Edit Config…", action: #selector(editConfig), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Ripcord", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
      menuItem.target = self
    }
    item.menu = menu
    return item
  }

  private func showError(_ message: String) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Ripcord"
    alert.informativeText = message
    alert.runModal()
  }
}
