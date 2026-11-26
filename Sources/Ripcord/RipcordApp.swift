import AppKit
import RipcordCore
import ServiceManagement
import UniformTypeIdentifiers

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
  private lazy var settings = SettingsWindowController(model: SettingsModel(configURL: configURL))
  private var statusItem: NSStatusItem?
  /// What's registered now, so re-reading an unchanged config skips the work and the alerts.
  private var registeredHotkeys: [String]?
  /// The config last read; hotkeys look things up here when pressed, so an edited Quicklink URL
  /// takes effect without re-registering.
  private var config = Config.default
  /// The last launcher hotkey that worked, kept while the config holds one that doesn't parse.
  private var workingLauncherHotkey: Hotkey?
  private var isRecording = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()
    statusItem = makeStatusItem()
    launcher.onOpenSettings = { [weak self] in self?.openSettings() }
    launcher.editSnippets = { [weak self] change in self?.editSnippets(change) ?? false }
    launcher.onExportSnippets = { [weak self] in self?.exportSnippets() }
    launcher.onImportSnippets = { [weak self] in self?.importSnippets() }
    settings.model.onSave = { [weak self] in self?.applyConfig() }
    settings.model.onRecordingChange = { [weak self] isRecording in
      self?.isRecording = isRecording
      // A registered hotkey would swallow the very keys being recorded.
      if isRecording {
        GlobalHotKey.unregisterAll()
        self?.registeredHotkeys = nil
      } else {
        self?.applyConfig()
      }
    }
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

  /// Through the settings window's model, so an open window shows the change and can't write
  /// back a list from before it. Read first, so edits made to the file meanwhile are kept.
  private func editSnippets(_ change: ([Snippet]) -> [Snippet]?) -> Bool {
    let model = settings.model
    model.load()
    guard model.loadError == nil else {
      showError(model.loadError ?? "")
      return false
    }
    guard let snippets = change(model.config.snippets) else {
      // The file changed under the panel; show what it holds now.
      applyConfig()
      return false
    }
    model.config.snippets = snippets
    // Saving calls applyConfig, which hands the launcher the new list.
    model.saveIfChanged()
    if let error = model.loadError { showError(error) }
    return model.loadError == nil
  }

  /// Writes every snippet to a JSON file Raycast can import too.
  private func exportSnippets() {
    NSApp.activate()
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "snippets.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let snippets = (try? Config.load(from: configURL))?.snippets ?? config.snippets
      try Snippet.exportData(snippets).write(to: url, options: .atomic)
    } catch {
      showError("Couldn't export the snippets: \(error.localizedDescription)")
    }
  }

  /// Adds the snippets in a JSON file, such as one Raycast exported, skipping ones already here.
  private func importSnippets() {
    NSApp.activate()
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let data = try Data(contentsOf: url)
      var added = 0
      var failure: Error?
      let saved = editSnippets { current in
        do {
          let merged = try Snippet.merging(data, into: current)
          added = merged.added
          return merged.snippets
        } catch {
          failure = error
          return nil
        }
      }
      if let failure { throw failure }
      if saved {
        showMessage(added == 1 ? "Imported 1 snippet." : "Imported \(added) snippets.")
      }
    } catch {
      showError("Couldn't import \(url.lastPathComponent): \(error.localizedDescription)")
    }
  }

  @objc private func openSettings() {
    settings.show()
  }

  /// Re-read on every show so edits to the file apply without a restart.
  private func applyConfig() {
    do {
      let config = try Config.load(from: configURL)
      self.config = config
      launcher.quicklinks = config.quicklinks
      launcher.items = config.items
      launcher.inputSource = config.inputSource
      launcher.snippets = config.snippets
      applyLaunchAtLogin(config.launchAtLogin)
      // Saving mid-recording must not bring back the hotkeys the recorder turned off.
      if !isRecording { applyHotkeys(config) }
    } catch {
      showError("\(configURL.path):\n\(error)")
    }
  }

  private func applyHotkeys(_ config: Config) {
    var assignments = config.hotkeyAssignments
    let launcherHotkey = Hotkey(config.hotkey)
    // A typo in config.json mustn't leave Ripcord with no way to open.
    if launcherHotkey == nil, let workingLauncherHotkey {
      assignments.insert((target: .launcher, hotkey: workingLauncherHotkey), at: 0)
    }
    let signature = [config.hotkey] + assignments.map { "\($0.target)=\($0.hotkey.spec)" }
    guard signature != registeredHotkeys else { return }
    let failures = GlobalHotKey.set(
      assignments.map { assignment in
        let target = assignment.target
        return (assignment.hotkey, { [weak self] in self?.run(target) })
      })
    // Rows on the Shortcuts page show their own failure; only the launcher's needs an alert.
    settings.model.failedHotkeys = Set(failures.keys.map { assignments[$0].target })
    let launcherFailure = assignments.firstIndex { $0.target == .launcher }.flatMap { failures[$0] }
    if launcherHotkey == nil {
      registeredHotkeys = signature
      showError("\"\(config.hotkey)\" is not a hotkey. Use a form like \"option+space\".")
    } else if let launcherFailure {
      // Left unrecorded, so the next panel open tries again.
      registeredHotkeys = nil
      showError("Couldn't register the Ripcord hotkey (OSStatus \(launcherFailure)).")
    } else {
      registeredHotkeys = signature
      workingLauncherHotkey = launcherHotkey
    }
  }

  /// What an app, command or Quicklink hotkey does. Apps open by bundle ID, so the hotkey
  /// works before the panel has ever scanned /Applications.
  private func run(_ target: HotkeyTarget) {
    switch target {
    case .launcher:
      toggleLauncher()
    case .item(let key):
      if let command = BuiltinCommand.allCases.first(where: { $0.settingsKey == key }) {
        // Read now, as opening the panel does, so a snippet added to the file is listed.
        if !launcher.isVisible { applyConfig() }
        launcher.perform(.run(command))
      } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key)
        ?? (key.hasPrefix("/") ? URL(fileURLWithPath: key) : nil)
      {
        launcher.perform(.open(url))
      } else {
        NSSound.beep()
      }
    case .quicklink(let index):
      guard config.quicklinks.indices.contains(index),
        let url = config.quicklinks[index].url(for: "")
      else { return NSSound.beep() }
      launcher.perform(.open(url))
    }
  }

  private func applyLaunchAtLogin(_ enabled: Bool) {
    let service = SMAppService.mainApp
    // requiresApproval means it is registered and waiting for the user in System Settings.
    let registered = service.status == .enabled || service.status == .requiresApproval
    guard enabled != registered else { return }
    do {
      try enabled ? service.register() : service.unregister()
    } catch {
      showError("Couldn't change Launch at Login: \(error.localizedDescription)")
    }
  }

  /// An accessory app shows no menu bar, but its main menu still carries the key equivalents
  /// that text fields in the settings window need.
  private func makeMainMenu() -> NSMenu {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    edit.addItem(.separator())
    edit.addItem(
      withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let app = NSMenu(title: "Ripcord")
    app.addItem(
      withTitle: "Quit Ripcord", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let main = NSMenu()
    for submenu in [app, edit] {
      let item = NSMenuItem()
      item.submenu = submenu
      main.addItem(item)
    }
    return main
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
    menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Ripcord", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
      menuItem.target = self
    }
    item.menu = menu
    return item
  }

  private func showMessage(_ message: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.runModal()
  }

  private func showError(_ message: String) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Ripcord"
    alert.informativeText = message
    alert.runModal()
  }
}
