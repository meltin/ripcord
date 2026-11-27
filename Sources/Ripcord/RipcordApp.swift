import AppKit
import RipcordControl
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
  private let updater = Updater()
  private let snippetExpander = SnippetExpander()
  private var control: ControlServer?
  private lazy var settings: SettingsWindowController = {
    let model = SettingsModel(configURL: configURL)
    model.updater = updater
    return SettingsWindowController(model: model)
  }()
  private lazy var notes = NotesWindowController(store: NoteStore(folder: NoteStore.userFolder))
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
    caffeinator.onChange = { [weak self] in self?.showTimersInMenuBar() }
    launcher.onCaffeinate = { [weak self] seconds in
      if self?.caffeinator.caffeinate(for: seconds) == false {
        self?.showError("macOS didn't let Ripcord keep the Mac awake.")
      }
    }
    sleepTimer.onChange = { [weak self] in self?.showTimersInMenuBar() }
    sleepTimer.onFire = { [weak self] displayOnly in
      // Lid Awake would keep the Mac awake through the sleep asked for.
      if !displayOnly { self?.lidAwake.stop() }
      if let message = SystemActions.run(
        displayOnly ? .sleepDisplays : .sleep, frontmost: nil,
        report: { self?.showError($0) })
      {
        self?.showError(message)
      }
    }
    launcher.onSleepTimer = { [weak self] in self?.sleepTimer.start(after: $0, displayOnly: $1) }
    lidAwake.onChange = { [weak self] in
      guard let self else { return }
      showTimersInMenuBar()
      launcher.lidAwakeStatus = lidAwake.status
      settings.model.lidAwakeOn = lidAwake.isActive
    }
    lidAwake.onError = { [weak self] in self?.showError($0) }
    launcher.onBeforeSleep = { [weak self] in self?.lidAwake.stop() }
    launcher.onLidAwake = { [weak self] seconds in
      if let message = self?.lidAwake.start(for: seconds) { self?.showError(message) }
    }
    launcher.onToggleLidAwake = { [weak self] in
      guard let self else { return }
      if lidAwake.isActive { return lidAwake.stop() }
      if let message = lidAwake.start(for: nil) { showError(message) }
    }
    launcher.onStopLidAwake = { [weak self] in
      guard self?.lidAwake.isActive == true else { return NSSound.beep() }
      self?.lidAwake.stop()
    }
    keyboardCleaner.onChange = { [weak self] in self?.showTimersInMenuBar() }
    launcher.onCleanKeyboard = { [weak self] seconds in
      guard let self else { return }
      do throws(KeyboardCleaner.Refusal) {
        try keyboardCleaner.start(for: seconds)
      } catch {
        switch error {
        case .noAccess:
          showError(
            "Clean Keyboard needs Accessibility: allow Ripcord under System Settings › Privacy & Security › Accessibility."
          )
        case .secureInput:
          showError(
            "Another app has secure input on, as a password field or a terminal's Secure Keyboard Entry does, so keys would get through. Close it, then try again."
          )
        }
      }
    }

    launcher.onStopSleepTimer = { [weak self] in
      guard self?.sleepTimer.isActive == true else { return NSSound.beep() }
      self?.sleepTimer.stop()
    }
    launcher.onToggleCaffeinate = { [weak self] in
      guard let self else { return }
      if caffeinator.isActive { return caffeinator.decaffeinate() }
      if !caffeinator.caffeinate(for: nil) {
        showError("macOS didn't let Ripcord keep the Mac awake.")
      }
    }
    launcher.onCaffeinateWhile = { [weak self] bundleID in
      if self?.caffeinator.caffeinate(whileRunning: bundleID) == false {
        HUD.show("That app isn't running anymore.", failed: true)
      }
    }
    launcher.onCaffeinateStatus = { [weak self] in
      guard let caffeinator = self?.caffeinator else { return }
      HUD.show(
        Coffee.status(
          isActive: caffeinator.isActive, remaining: caffeinator.remaining,
          whileApp: caffeinator.whileApp))
    }
    launcher.onDecaffeinate = { [weak self] in
      // Nothing to stop: a beep rather than a panel that just closes.
      guard self?.caffeinator.isActive == true else { return NSSound.beep() }
      self?.caffeinator.decaffeinate()
    }
    launcher.onOpenSettings = { [weak self] in self?.openSettings() }
    launcher.onCheckForUpdates = { [weak self] in self?.checkForUpdates() }
    settings.model.onClearClipboard = { [weak self] in self?.launcher.clearClipboardHistory() }
    settings.model.onSetEmojiSkinTone = { [weak self] in self?.launcher.setEmojiSkinTone($0) }
    launcher.onBackdropError = { [weak self] in self?.settings.model.backdropError = $0 }
    startControl()
    snippetExpander.onExpand = { [weak self] in self?.launcher.pasteExpansion($0, trailing: $1) }
    launcher.onNotes = { [weak self] in self?.notes.handle($0) }
    notes.onBrowse = { [weak self] in self?.launcher.perform(.run(.searchNotes)) }
    notes.onSettings = { [weak self] in self?.settings.show(configuring: "command:ripcord-notes") }
    launcher.onConfigure = { [weak self] in self?.settings.show(configuring: $0) }
    launcher.settings = settings.model
    launcher.onError = { [weak self] in self?.showError($0) }
    launcher.editSnippets = { [weak self] change in self?.editSnippets(change) ?? false }
    launcher.editSettings = { [weak self] change in self?.editSettings(change) ?? false }
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
    // Before applyConfig, which writes the defaults when there's no file yet.
    let firstLaunch = !FileManager.default.fileExists(atPath: configURL.path)
    applyConfig()
    settings.showWelcomeIfNew(firstLaunch: firstLaunch)
  }

  /// What's typed in a note is saved before quitting, as its autosave may not have run yet.
  func applicationWillTerminate(_ notification: Notification) {
    // A closed Mac must sleep again once Ripcord isn't there to turn Lid Awake off.
    lidAwake.stop()
    notes.flushForQuit()
    control?.stop()
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

  /// Applies `change` to the file as it is now, and saves; false when it can't be read or saved.
  private func editSettings(_ change: (SettingsModel) -> Void) -> Bool {
    let model = settings.model
    model.load()
    guard model.loadError == nil else {
      showError(model.loadError ?? "")
      return false
    }
    change(model)
    // Saving calls applyConfig, which hands the launcher the new settings.
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
      // From the file as it is now; a file that doesn't read is reported, not covered up with
      // an older list.
      let snippets = try Config.load(from: configURL).snippets
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

  /// The socket the `ripcord` command talks to; without it the app works as before.
  private func startControl() {
    let server = ControlServer { [weak self] request in
      await self?.answer(request) ?? ControlResponse(error: "Ripcord is quitting.")
    }
    do {
      try server.start()
      control = server
    } catch {
      NSLog("Ripcord: \(error.localizedDescription)")
    }
  }

  private func answer(_ request: ControlRequest) async -> ControlResponse {
    switch request {
    case .open(let query):
      if !launcher.isVisible { applyConfig() }
      launcher.open(query: query)
      return ControlResponse()
    case .configGet(let key):
      do {
        // Written with the defaults first if it's missing, as at launch.
        _ = try Config.load(from: configURL)
        return ControlResponse(output: try Config.get(key, from: Data(contentsOf: configURL)))
      } catch {
        return ControlResponse(error: "ripcord: \(error.localizedDescription)")
      }
    case .configSet(let key, let json):
      // Through the settings window's model, as its own edits go, so an open window shows the
      // change and can't write back what was there before.
      let model = settings.model
      model.load()
      if let failure = model.loadError { return ControlResponse(error: "ripcord: \(failure)") }
      do {
        model.config = try Config.setting(key, to: json, in: Data(contentsOf: configURL))
      } catch {
        return ControlResponse(error: "ripcord: \(error.localizedDescription)")
      }
      model.saveIfChanged()
      return model.loadError.map { ControlResponse(error: "ripcord: \($0)") } ?? ControlResponse()
    case .pick(let items, let placeholder):
      if !launcher.isVisible { applyConfig() }
      // Capped here too, whatever sent it.
      return await launcher.pick(items: Control.pickable(items), placeholder: placeholder)
    }
  }

  @objc private func openSettings() {
    // A shader saved since shows its error, or its fix, on the General page.
    launcher.loadBackdrop()
    // Kept with the emoji used, not in config.json; ⌘K in the panel changes it too.
    settings.model.emojiSkinTone = launcher.emojiSkinTone
    settings.show()
  }

  @objc private func checkForUpdates() {
    updater.checkForUpdates()
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
      snippetExpander.apply(config)
      launcher.repositorySettings = config.repositories
      launcher.colorFormat = config.colorFormat
      launcher.showColorName = config.showColorName
      launcher.emojiSettings = config.emoji
      launcher.favorites = config.favorites
      launcher.scriptFolders = config.scriptFolders
      launcher.dummyTextLanguage = config.dummyTextLanguage
      launcher.clipboardSettings = config.clipboardHistory
      launcher.backdrop = config.backdrop
      launcher.cycleHalves = config.cycleHalves
      launcher.setWindowGaps(window: config.windowGap, screen: config.screenGap)
      lidAwake.lowBattery = config.lidAwakeLowBattery
      caffeinator.settings = config.coffee
      keyboardCleaner.settings = config.cleanKeyboard
      launcher.cleanKeyboardDuration = config.cleanKeyboard.defaultDuration
      // Start Caffeination When Ripcord Starts: only as it starts, not on every save.
      if !hasAppliedConfig, config.coffee.startOnLaunch { caffeinator.caffeinate(for: nil) }
      hasAppliedConfig = true
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
    let trusted = AXIsProcessTrusted()
    // A typo in config.json, or ⇧⇧ without Accessibility, mustn't leave Ripcord with no way to
    // open.
    if launcherHotkey == nil || (launcherHotkey?.isDoubleTap == true && !trusted),
      let workingLauncherHotkey, workingLauncherHotkey != launcherHotkey
    {
      assignments.insert((target: .launcher, hotkey: workingLauncherHotkey), at: 0)
    }
    // With a double tap among them, granting Accessibility has to register them again.
    let doubleTaps = assignments.contains { $0.hotkey.isDoubleTap }
    let signature =
      [config.hotkey] + assignments.map { "\($0.target)=\($0.hotkey.spec)" }
      + (doubleTaps ? ["accessibility=\(trusted)"] : [])
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
      showError(
        "\"\(config.hotkey)\" is not a hotkey. Use a form like \"option+space\" or \"shift+shift\"."
      )
    } else if let launcherFailure {
      // Left unrecorded, so the next panel open tries again.
      registeredHotkeys = nil
      showError(
        launcherFailure == GlobalHotKey.needsAccessibility
          ? "The Ripcord hotkey \(launcherHotkey?.keycaps.joined() ?? config.hotkey) needs Accessibility. Allow Ripcord under System Settings › Privacy & Security › Accessibility."
          : "Couldn't register the Ripcord hotkey (OSStatus \(launcherFailure)).")
    } else {
      registeredHotkeys = signature
      // ⇧⇧ waiting for Accessibility isn't working yet; the one standing in for it stays.
      if launcherHotkey?.isDoubleTap != true || trusted { workingLauncherHotkey = launcherHotkey }
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
      } else if let action = SystemAction.allCases.first(where: { $0.settingsKey == key }) {
        launcher.perform(.system(action))
      } else if let layout = WindowLayout.allCases.first(where: { $0.settingsKey == key }) {
        launcher.perform(.window(layout))
      } else if let command = CleanShotCommand.allCases.first(where: { $0.settingsKey == key }) {
        launcher.perform(.cleanShot(command))
      } else if key.hasPrefix("script:") {
        launcher.perform(.runScript(String(key.dropFirst("script:".count))))
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

  private let caffeinator = Caffeinator()
  private var hasAppliedConfig = false
  private let sleepTimer = SleepTimer()
  private let lidAwake = LidAwake()
  private let stopLidAwakeItem = NSMenuItem(
    title: "Turn Off Lid Awake", action: #selector(stopLidAwake), keyEquivalent: "")

  @objc private func stopLidAwake() { lidAwake.stop() }
  private let keyboardCleaner = KeyboardCleaner()
  private let stopCleanKeyboardItem = NSMenuItem(
    title: "Stop Clean Keyboard", action: #selector(stopCleanKeyboard), keyEquivalent: "")

  @objc private func stopCleanKeyboard() { keyboardCleaner.stop() }
  private let stopSleepTimerItem = NSMenuItem(
    title: "Stop Sleep Timer", action: #selector(stopSleepTimer), keyEquivalent: "")

  @objc private func stopSleepTimer() { sleepTimer.stop() }
  private var statusIcon: NSImage?
  private let decaffeinateItem = NSMenuItem(
    title: "Decaffeinate", action: #selector(decaffeinate), keyEquivalent: "")

  @objc private func decaffeinate() { caffeinator.decaffeinate() }

  /// The menu bar while a timer runs: a moon and the time left for Sleep Timer, else a cup for
  /// Coffee, with its time when timed, as Raycast's extensions show them; Ripcord's icon
  /// otherwise.
  private func showTimersInMenuBar() {
    guard let statusItem, let button = statusItem.button else { return }
    decaffeinateItem.isHidden = !caffeinator.isActive
    stopSleepTimerItem.isHidden = !sleepTimer.isActive
    stopLidAwakeItem.isHidden = !lidAwake.isActive
    stopCleanKeyboardItem.isHidden = !keyboardCleaner.isActive
    // Lid Awake first: a Mac that won't sleep when closed is the one to know about.
    let shown: (symbol: String, label: String, remaining: TimeInterval?)? =
      lidAwake.isActive
      ? ("sun.max", "Lid Awake", lidAwake.remaining)
      : sleepTimer.isActive
        ? ("moon.zzz.fill", "Sleep timer", sleepTimer.remaining)
        : caffeinator.isActive ? ("cup.and.saucer.fill", "Caffeinated", caffeinator.remaining) : nil
    guard let shown else {
      button.image = statusIcon
      button.title = ""
      statusItem.length = NSStatusItem.squareLength
      return
    }
    // A copy: the cached image is shared with the panel's icons of the same size.
    let image =
      (Tabler.image(shown.symbol, size: 18)?.copy() as? NSImage)
      ?? NSImage(systemSymbolName: shown.symbol, accessibilityDescription: shown.label)
    image?.isTemplate = true
    image?.accessibilityDescription = shown.label
    button.image = image
    button.imagePosition = .imageLeading
    button.title = shown.remaining.map { " " + Coffee.format($0, seconds: false) } ?? ""
    statusItem.length = NSStatusItem.variableLength
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
    statusIcon = icon
    let menu = NSMenu()
    decaffeinateItem.isHidden = true
    menu.addItem(decaffeinateItem)
    stopSleepTimerItem.isHidden = true
    menu.addItem(stopSleepTimerItem)
    stopLidAwakeItem.isHidden = true
    menu.addItem(stopLidAwakeItem)
    stopCleanKeyboardItem.isHidden = true
    menu.addItem(stopCleanKeyboardItem)
    menu.addItem(withTitle: "Open Ripcord", action: #selector(toggleLauncher), keyEquivalent: "")
    menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    menu.addItem(
      withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
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
