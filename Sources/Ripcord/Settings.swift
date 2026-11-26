import AppKit
import Carbon.HIToolbox
import RipcordCore
import SwiftUI
import os

/// The settings window's copy of config.json; every edit is written straight back to the file.
@MainActor
@Observable
final class SettingsModel {
  let configURL: URL
  var config = Config.default
  /// Set when the file can't be read; editing stays off so the broken file isn't overwritten.
  var loadError: String?
  var onSave: () -> Void = {}
  var onRecordingChange: (Bool) -> Void = { _ in }
  /// A command's settings key whose page the window should turn to, from Configure Command.
  var requestedKey: String?
  /// Hotkeys macOS refused at the last registration, shown on their rows.
  var failedHotkeys: Set<HotkeyTarget> = []
  /// Scanned when the Applications page first appears, so the window costs nothing until then.
  var apps: [AppEntry] = []
  /// The one row recording a hotkey; starting another row stops it.
  private(set) var recordingTarget: HotkeyTarget?
  private(set) var recorderMessage: (target: HotkeyTarget, text: String)?
  private var saved = Config.default
  private var keyMonitor: Any?

  init(configURL: URL) { self.configURL = configURL }

  /// The Applications page's rows, worked out once per scan rather than on every redraw.
  private(set) var appEntries: [CatalogEntry] = []

  func loadApps() {
    Task {
      apps = await Task.detached(priority: .userInitiated) { AppIndex.scan() }.value
      appEntries = Search.catalog(apps: apps, quicklinks: []).first?.entries ?? []
    }
  }

  func load() {
    do {
      config = try Config.load(from: configURL)
      saved = config
      loadError = nil
    } catch {
      loadError = "\(configURL.path) couldn't be read, so changes here aren't saved. \(error)"
    }
  }

  func saveIfChanged() {
    guard loadError == nil, config != saved else { return }
    do {
      try config.save(to: configURL)
      saved = config
      onSave()
    } catch {
      loadError = "Couldn't save \(configURL.path): \(error.localizedDescription)"
    }
  }

  // MARK: Hotkey recording

  /// The one row whose alias is being typed; starting a recording ends it, and the reverse.
  var editingAlias: HotkeyTarget?

  func startRecording(for target: HotkeyTarget) {
    stopRecording()
    editingAlias = nil
    recordingTarget = target
    recorderMessage = nil
    onRecordingChange(true)
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.record(event)
      return nil
    }
  }

  func stopRecording() {
    guard let keyMonitor else { return }
    NSEvent.removeMonitor(keyMonitor)
    self.keyMonitor = nil
    recordingTarget = nil
    onRecordingChange(false)
  }

  private func record(_ event: NSEvent) {
    guard let target = recordingTarget else { return }
    if event.keyCode == UInt16(kVK_Escape) { return stopRecording() }
    if let problem = setHotkey(from: event, for: target) {
      recorderMessage = (target, problem)
      return
    }
    stopRecording()
  }

  /// Saves the keys `event` pressed as `target`'s hotkey; why it can't be one otherwise. The
  /// panel's Set Hotkey… records through this too.
  func setHotkey(from event: NSEvent, for target: HotkeyTarget) -> String? {
    guard
      let hotkey = Hotkey(
        keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(event.modifierFlags))
    else {
      return "Use ⌘, ⌥ or ⌃ (⇧ optional) with a letter, a digit, an arrow, Return or Space."
    }
    if let owner = config.owner(of: hotkey, except: target) {
      return "Already used by \(name(of: owner))."
    }
    setHotkey(hotkey.spec, for: target)
    // Saved before re-registering, so the new hotkey is the one that comes back.
    saveIfChanged()
    return nil
  }

  private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    let pairs: [(NSEvent.ModifierFlags, Int)] = [
      (.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey),
    ]
    return pairs.filter { flags.contains($0.0) }.map { UInt32($0.1) }.reduce(0, |)
  }

  // MARK: Per-item settings

  func name(of target: HotkeyTarget) -> String {
    switch target {
    case .launcher: "the Ripcord hotkey"
    case .item(let key):
      BuiltinCommand.allCases.first { $0.settingsKey == key }?.title
        ?? SystemAction.allCases.first { $0.settingsKey == key }?.title
        ?? WindowLayout.allCases.first { $0.settingsKey == key }?.title
        ?? apps.first { $0.settingsKey == key }?.names[0]
        // Before the Applications page has scanned the apps, ask Launch Services.
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: key).map {
          FileManager.default.displayName(atPath: $0.path)
        } ?? key
    case .quicklink(let index):
      config.quicklinks.indices.contains(index) ? config.quicklinks[index].name : "a Quicklink"
    }
  }

  /// The alias; a Quicklink's is its keyword.
  func alias(of target: HotkeyTarget) -> String {
    switch target {
    case .launcher: ""
    case .item(let key): config.item(key).alias ?? ""
    case .quicklink(let index):
      config.quicklinks.indices.contains(index) ? config.quicklinks[index].keyword ?? "" : ""
    }
  }

  func setAlias(_ alias: String, for target: HotkeyTarget) {
    switch target {
    case .launcher: break
    case .item(let key):
      var settings = config.item(key)
      settings.alias = alias
      config.setItem(key, settings)
    case .quicklink(let index):
      guard config.quicklinks.indices.contains(index) else { return }
      config.quicklinks[index].keyword =
        alias.trimmingCharacters(in: .whitespaces).isEmpty ? nil : alias
    }
  }

  func hotkey(of target: HotkeyTarget) -> String? {
    switch target {
    case .launcher: config.hotkey
    case .item(let key): config.item(key).hotkey
    case .quicklink(let index):
      config.quicklinks.indices.contains(index) ? config.quicklinks[index].hotkey : nil
    }
  }

  func setHotkey(_ spec: String?, for target: HotkeyTarget) {
    switch target {
    case .launcher:
      if let spec { config.hotkey = spec }
    case .item(let key):
      var settings = config.item(key)
      settings.hotkey = spec
      config.setItem(key, settings)
    case .quicklink(let index):
      guard config.quicklinks.indices.contains(index) else { return }
      config.quicklinks[index].hotkey = spec
    }
  }

  func isEnabled(_ target: HotkeyTarget) -> Bool {
    switch target {
    case .launcher: true
    case .item(let key): config.item(key).isEnabled
    case .quicklink(let index):
      config.quicklinks.indices.contains(index) ? config.quicklinks[index].isEnabled : true
    }
  }

  func setEnabled(_ enabled: Bool, for target: HotkeyTarget) {
    switch target {
    case .launcher: break
    case .item(let key):
      var settings = config.item(key)
      settings.isEnabled = enabled
      config.setItem(key, settings)
    case .quicklink(let index):
      guard config.quicklinks.indices.contains(index) else { return }
      config.quicklinks[index].isEnabled = enabled
    }
  }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  let model: SettingsModel
  private lazy var window: NSWindow = {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = "Ripcord Settings"
    window.titlebarAppearsTransparent = true
    // The page says where you are; the title bar keeps only the traffic lights.
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: SettingsView(model: model))
    window.delegate = self
    window.center()
    return window
  }()

  private var welcomeWindow: NSWindow?
  /// Tracked rather than read from `window`, which is lazy and would be built just to ask.
  private var isSettingsOpen = false
  private static let welcomeShownKey = "welcomeShown"

  /// The guide on a first launch (no config file before it), once; closing it counts as seen.
  func showWelcomeIfNew(firstLaunch: Bool) {
    guard firstLaunch, !UserDefaults.standard.bool(forKey: Self.welcomeShownKey) else { return }
    model.load()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    let content = NSHostingView(
      rootView: WelcomeView(model: model) { [weak window] in window?.performClose(nil) })
    window.contentView = content
    window.setContentSize(content.fittingSize)
    window.delegate = self
    window.center()
    welcomeWindow = window
    NSApp.setActivationPolicy(.regular)
    bringForward(window)
  }

  /// Closes the window on Esc and steps through the pages on ↑ and ↓ while it's open, as
  /// Raycast's settings do. An AppKit monitor, since SwiftUI's key handlers missed held keys.
  private var escMonitor: Any?

  init(model: SettingsModel) { self.model = model }

  /// Becomes a regular app while the window is open, as Raycast does: macOS 14 only lets an
  /// accessory app ask to come forward, and the request loses to the app the user was in.
  /// `configuring` turns to the page of the command or app with that settings key.
  func show(configuring key: String? = nil) {
    if let key { model.requestedKey = key }
    // On the screen the panel was on, the pointer's: `center()` alone uses the screen macOS
    // counts as main, which can be another display, and a closed window keeps its old place.
    if !window.isVisible,
      let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
    {
      let area = screen.visibleFrame
      let size = window.frame.size
      window.setFrameOrigin(
        NSPoint(
          x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded()))
    }
    isSettingsOpen = true
    NSApp.setActivationPolicy(.regular)
    if escMonitor == nil {
      escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else { return event }
        if let step = pageStep(event) {
          NotificationCenter.default.post(
            name: step > 0 ? Self.nextPage : Self.previousPage, object: nil)
          return nil
        }
        guard event.keyCode == UInt16(kVK_Escape), event.window === window,
          // Esc stops a recording, and cancels Japanese input that's still being composed.
          model.recordingTarget == nil,
          // Esc in an alias being typed ends the edit instead.
          model.editingAlias == nil,
          (window.firstResponder as? NSTextView)?.hasMarkedText() != true
        else { return event }
        window.performClose(nil)
        return nil
      }
    }
    bringForward(window)
  }

  /// Bumped by each `bringForward`, so only the latest one keeps asking.
  private var activationRequest = 0

  /// Brings `target` in front and asks to become the active app, at once, inside the key press
  /// or click that opened it, which macOS grants most readily, then again for up to a second:
  /// the policy change lands a run loop pass later, and a request lost to the app the user was
  /// in leaves the window grayed out behind that app's, with the keys going to it.
  private func bringForward(_ target: NSWindow) {
    activationRequest += 1
    let request = activationRequest
    let previous = NSWorkspace.shared.frontmostApplication
    func attempt(_ number: Int) {
      NSApp.activate()
      // On top of other apps' windows even if macOS turns the request down.
      target.orderFrontRegardless()
      target.makeKey()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
        let front = NSWorkspace.shared.frontmostApplication
        guard request == activationRequest, target.isVisible,
          !NSApp.isActive || !target.isKeyWindow,
          // The user has moved on: to another app, the panel, or a dialog of their own.
          front == previous || front == .current,
          NSApp.keyWindow == nil || NSApp.keyWindow === target,
          NSApp.modalWindow == nil, target.attachedSheet == nil
        else { return }
        guard number < 10 else {
          // Read with: log show --predicate 'subsystem == "io.github.meltin.ripcord"'
          Self.log.error(
            "Window stayed in the background: active \(NSApp.isActive, privacy: .public), key \(target.isKeyWindow, privacy: .public), frontmost \(front?.bundleIdentifier ?? "-", privacy: .public)"
          )
          return
        }
        attempt(number + 1)
      }
    }
    attempt(1)
  }

  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "io.github.meltin.ripcord", category: "settings")

  /// Posted for the sidebar to move to the next or previous page.
  static let nextPage = Notification.Name("RipcordSettingsNextPage")
  static let previousPage = Notification.Name("RipcordSettingsPreviousPage")

  /// +1 for ↓ and -1 for ↑, held down too, unless a field, an alias or a hotkey recording has
  /// the keys.
  private func pageStep(_ event: NSEvent) -> Int? {
    guard event.window === window,
      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
      model.recordingTarget == nil, model.editingAlias == nil,
      !(window.firstResponder is NSText)
    else { return nil }
    switch Int(event.keyCode) {
    case kVK_DownArrow: return 1
    case kVK_UpArrow: return -1
    default: return nil
    }
  }

  func windowWillClose(_ notification: Notification) {
    model.stopRecording()
    if (notification.object as? NSWindow) === welcomeWindow {
      UserDefaults.standard.set(true, forKey: Self.welcomeShownKey)
      welcomeWindow = nil
    } else {
      isSettingsOpen = false
      if let escMonitor { NSEvent.removeMonitor(escMonitor) }
      escMonitor = nil
    }
    // An accessory again once neither window is open.
    if !isSettingsOpen, welcomeWindow == nil {
      NSApp.setActivationPolicy(.accessory)
      // Switchers such as AltTab note the policy only as apps activate and deactivate; without
      // this, Ripcord stays listed with no windows after Settings closes.
      NSApp.deactivate()
    }
  }

  /// Picks up edits made to the file in an editor while the window was in the background.
  func windowDidBecomeKey(_ notification: Notification) {
    model.load()
  }

  /// Switching away mid-recording must not leave Ripcord's hotkeys unregistered.
  func windowDidResignKey(_ notification: Notification) {
    model.stopRecording()
  }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
  case general = "General"
  case permissions = "Permissions"
  case applications = "Applications"
  case quicklinks = "Quicklinks"
  case clipboardHistory = "Clipboard History"
  case snippets = "Snippets"
  case systemActions = "System Actions"
  case windowManagement = "Window Management"
  case coffee = "Coffee"
  case repositories = "Git Repositories"
  case ripcord = "Ripcord"

  var id: Self { self }

  var symbol: String {
    switch self {
    case .general: "slider.horizontal.3"
    case .permissions: "lock.shield.fill"
    case .applications: "square.grid.2x2.fill"
    case .quicklinks: "link"
    case .clipboardHistory: "list.clipboard.fill"
    case .snippets: "doc.plaintext.fill"
    case .systemActions: "gearshape.fill"
    case .windowManagement: "rectangle.split.2x1.fill"
    case .coffee: "cup.and.saucer.fill"
    case .repositories: "arrow.triangle.branch"
    case .ripcord: "command"
    }
  }

  var color: Color {
    switch self {
    case .general, .systemActions, .ripcord: .gray
    case .permissions: .green
    case .applications, .quicklinks, .snippets: .blue
    case .clipboardHistory: .red
    case .windowManagement: .indigo
    case .coffee: .brown
    case .repositories: .orange
    }
  }

  /// What the page's header says it's for.
  var summary: String {
    switch self {
    case .general: ""
    case .permissions:
      "What Ripcord may do on your Mac, and which features need it. Each is asked for on first use too."
    case .applications:
      "An alias to type in the panel, a hotkey to open it from anywhere; unchecked apps never show in search."
    case .quicklinks:
      "Type a keyword, a space and a query in the panel. {query} in the URL is replaced by what you type."
    case .clipboardHistory:
      "Text and images you copy, searchable and ready to paste. Switching it off also stops recording."
    case .snippets: "Text you save and paste with Search Snippets."
    case .systemActions:
      "Lock, sleep, control music and volume, and manage apps, the Trash and disks."
    case .windowManagement:
      "Put the frontmost window in a half, quarter or third, or on another display."
    case .coffee:
      "Keep the Mac awake, until Decaffeinate or for a time typed after Caffeinate, as in “caffeinate 1h 30m”."
    case .repositories:
      "Find the Git repositories in your folders and open each in the app you pick for its Return."
    case .ripcord: "Ripcord's own commands."
    }
  }

  /// The commands a page lists, by settings key; nil for pages built another way.
  var commandKeys: Set<String>? {
    switch self {
    case .clipboardHistory, .snippets, .repositories, .coffee, .ripcord:
      Set(BuiltinCommand.allCases.filter { $0.settingsPage == self }.map(\.settingsKey))
    case .systemActions: Set(SystemAction.allCases.map(\.settingsKey))
    case .windowManagement: Set(WindowLayout.allCases.map(\.settingsKey))
    case .general, .permissions, .applications, .quicklinks: nil
    }
  }
}

extension BuiltinCommand {
  /// The settings page that lists it; exhaustive, so a new command can't go missing there.
  fileprivate var settingsPage: SettingsPage {
    switch self {
    case .clipboardHistory: .clipboardHistory
    case .searchSnippets, .createSnippet, .exportSnippets, .importSnippets: .snippets
    case .searchRepositories: .repositories
    case .caffeinate, .decaffeinate: .coffee
    case .settings, .resetWindowPosition, .quit: .ripcord
    }
  }
}

struct SettingsView: View {
  @Bindable var model: SettingsModel
  @State private var page = SettingsPage.general

  var body: some View {
    // Laid out by hand rather than with NavigationSplitView, which shrank the sidebar to fit
    // and cut its labels short.
    HStack(spacing: 0) {
      Sidebar(page: $page)
        .frame(width: 220)
      Divider()
      Group {
        switch page {
        case .general: PageScroll(model: model) { GeneralPage(model: model) }
        case .permissions:
          PageScroll(model: model) {
            PageHeader(page: .permissions)
            PermissionsCard()
          }
        case .applications: ApplicationsPage(model: model)
        case .quicklinks:
          PageScroll(model: model) {
            PageHeader(page: .quicklinks)
            QuicklinksPage(model: model)
          }
        case .repositories:
          PageScroll(model: model) {
            PageHeader(page: .repositories)
            RepositoriesSettings(model: model)
            CommandsList(model: model, page: .repositories)
          }
        default:
          PageScroll(model: model) {
            PageHeader(page: page)
            CommandsList(model: model, page: page)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .ignoresSafeArea()
    .frame(minWidth: 760, minHeight: 520)
    .onChange(of: model.config) { model.saveIfChanged() }
    .onChange(of: model.requestedKey, initial: true) {
      guard let key = model.requestedKey else { return }
      // A key no page lists as a command is an app's.
      page =
        SettingsPage.allCases.first { $0.commandKeys?.contains(key) == true } ?? .applications
      model.requestedKey = nil
    }
    // A recording left running on a page no longer shown would swallow every key typed.
    .onChange(of: page) {
      model.stopRecording()
      model.editingAlias = nil
    }
  }
}

/// The pages, on the translucent sidebar material: General, then a gap, then the extensions.
/// ↑ and ↓ step through the pages, as in Raycast's settings.
private struct Sidebar: View {
  @Binding var page: SettingsPage

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        row(.general)
        row(.permissions)
        Spacer().frame(height: 14)
        ForEach(SettingsPage.allCases.filter { $0 != .general && $0 != .permissions }) { row($0) }
      }
      .padding(.horizontal, 10)
      // Below the window's traffic lights.
      .padding(.top, 52)
      .padding(.bottom, 12)
    }
    .scrollIndicators(.never)
    .background(SidebarMaterial())
    .onReceive(NotificationCenter.default.publisher(for: SettingsWindowController.nextPage)) { _ in
      step(1)
    }
    .onReceive(NotificationCenter.default.publisher(for: SettingsWindowController.previousPage)) {
      _ in step(-1)
    }
  }

  private func step(_ offset: Int) {
    let pages = SettingsPage.allCases
    guard let index = pages.firstIndex(of: page) else { return }
    page = pages[min(max(index + offset, 0), pages.count - 1)]
  }

  private func row(_ item: SettingsPage) -> some View {
    Button {
      page = item
      // Out of a field on the page, so the arrows step through pages again.
      NSApp.keyWindow?.makeFirstResponder(nil)
    } label: {
      HStack(spacing: 10) {
        PageIcon(page: item, size: 22)
        Text(item.rawValue).font(.system(size: 13)).lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .frame(height: 32)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(item == page ? Color.primary.opacity(0.09) : .clear)
      )
      .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(item == page ? .isSelected : [])
  }
}

/// macOS's translucent sidebar background.
private struct SidebarMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .sidebar
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A page's symbol on its colored tile, as the sidebar and page headers draw it.
private struct PageIcon: View {
  let page: SettingsPage
  let size: CGFloat

  var body: some View {
    Image(systemName: page.symbol)
      .font(.system(size: size * 0.55, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(page.color.gradient, in: RoundedRectangle(cornerRadius: size / 4))
  }
}

/// The page's icon, name and what it's for, above its settings.
private struct PageHeader: View {
  let page: SettingsPage

  var body: some View {
    HStack(spacing: 12) {
      PageIcon(page: page, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(page.rawValue).font(.system(size: 15, weight: .semibold))
        Text(page.summary).font(.system(size: 12)).foregroundStyle(.secondary)
      }
    }
  }
}

/// A scrolling page with the config's load error on top, for every page but Applications,
/// whose long list scrolls on its own.
private struct PageScroll<Content: View>: View {
  @Bindable var model: SettingsModel
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        LoadErrorBanner(model: model)
        content
      }
      .padding(.horizontal, 28)
      // Clear of the title bar, which the content runs under.
      .padding(.top, 44)
      .padding(.bottom, 28)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .thinScroller()
  }
}

private struct LoadErrorBanner: View {
  @Bindable var model: SettingsModel

  var body: some View {
    if let loadError = model.loadError {
      Label(loadError, systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 12))
        .foregroundStyle(.red)
    }
  }
}

private struct GeneralPage: View {
  @Bindable var model: SettingsModel
  @State private var inputSources: [InputSource.Option] = []

  /// The enabled sources, plus a saved one that was since disabled, so the picker never goes blank.
  private var inputSourceOptions: [InputSource.Option] {
    guard let id = model.config.inputSource, !inputSources.contains(where: { $0.id == id }) else {
      return inputSources
    }
    return inputSources + [InputSource.Option(id: id, name: "\(id) (not enabled)")]
  }

  var body: some View {
    Card {
      SettingRow(
        title: "Launch at Login",
        description: "Start Ripcord when you log in, so the hotkey always works."
      ) {
        Toggle("Launch at Login", isOn: $model.config.launchAtLogin)
          .toggleStyle(.switch)
          .labelsHidden()
      }
      Divider()
      SettingRow(
        title: "Ripcord Hotkey",
        description: "Shows the panel from any app. Click, then press the new keys; Esc cancels."
      ) {
        HotkeyRecorder(target: .launcher, model: model, clearable: false)
      }
      Divider()
      SettingRow(
        title: "Auto-switch Input Source",
        description:
          "Switches to this input source while the panel is open, and back when it closes."
      ) {
        Picker("Auto-switch Input Source", selection: $model.config.inputSource) {
          Text("Off").tag(String?.none)
          ForEach(inputSourceOptions) { Text($0.name).tag(Optional($0.id)) }
        }
        .labelsHidden()
        .fixedSize()
        // Read on each visit, so a source enabled meanwhile shows up.
        .onAppear { inputSources = InputSource.selectable() }
      }
    }
    Card {
      SettingRow(
        title: "Config File",
        description: "Every change here is saved to this file, and edits to the file show up here.",
        detail: (model.configURL.path as NSString).abbreviatingWithTildeInPath
      ) {
        HStack(spacing: 8) {
          Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([model.configURL])
          }
          Button("Open in Editor") { NSWorkspace.shared.open(model.configURL) }
            .buttonStyle(.borderedProminent)
        }
      }
    }
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") {
      Text("Ripcord \(String(describing: version))")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
  }
}

private struct QuicklinksPage: View {
  @Bindable var model: SettingsModel

  var body: some View {
    HStack {
      Spacer()
      Button("Add Quicklink", systemImage: "plus") {
        model.config.quicklinks.append(Quicklink(name: "", url: ""))
      }
      .buttonStyle(.borderedProminent)
    }
    Card {
      HStack(spacing: 10) {
        Text("Name").frame(width: 170, alignment: .leading)
        Text("Keyword").frame(width: 90, alignment: .leading)
        Text("URL").frame(maxWidth: .infinity, alignment: .leading)
        Color.clear.frame(width: 24)
      }
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      if model.config.quicklinks.isEmpty {
        Divider()
        Text("No Quicklinks yet. Add one to search a site from the panel.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .padding(16)
      }
      ForEach(model.config.quicklinks.indices, id: \.self) { index in
        Divider()
        QuicklinkRow(link: link(at: index)) {
          if model.config.quicklinks.indices.contains(index) {
            model.config.quicklinks.remove(at: index)
          }
        }
      }
    }
    // Their hotkeys and on/off switches; the Keyword above is their alias, so no Alias column.
    let shortcuts =
      Search.catalog(apps: [], quicklinks: model.config.quicklinks)
      .first { $0.title == "Quicklinks" }?.entries ?? []
    if !shortcuts.isEmpty {
      ShortcutsCard(
        title: "Shortcuts", entries: shortcuts, model: model, page: .quicklinks, showsAlias: false)
    }
  }

  /// Bounds-checked, because SwiftUI can still render a row for a link that was just removed.
  private func link(at index: Int) -> Binding<Quicklink> {
    Binding {
      model.config.quicklinks.indices.contains(index)
        ? model.config.quicklinks[index] : Quicklink(name: "", url: "")
    } set: { newValue in
      if model.config.quicklinks.indices.contains(index) {
        model.config.quicklinks[index] = newValue
      }
    }
  }
}

private struct QuicklinkRow: View {
  @Binding var link: Quicklink
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      TextField("Name", text: $link.name)
        .frame(width: 170)
      TextField(
        "Keyword",
        text: Binding {
          link.keyword ?? ""
        } set: {
          link.keyword = $0.isEmpty ? nil : $0
        }
      )
      .frame(width: 90)
      TextField("https://example.com/search?q={query}", text: $link.url)
        .font(.system(size: 12, design: .monospaced))
      Button(action: onDelete) {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Delete \(link.name.isEmpty ? "Quicklink" : link.name)")
      .frame(width: 24)
    }
    .textFieldStyle(.roundedBorder)
    .font(.system(size: 13))
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }
}

/// A page's commands, each with its alias, hotkey and on/off switch.
private struct CommandsList: View {
  @Bindable var model: SettingsModel
  let page: SettingsPage

  var body: some View {
    let keys = page.commandKeys ?? []
    let entries = Search.catalog(apps: [], quicklinks: []).flatMap(\.entries).filter {
      if case .item(let key) = $0.target { keys.contains(key) } else { false }
    }
    ShortcutsCard(title: "Commands", entries: entries, model: model, page: page)
  }
}

/// Column headings over rows of a page's items.
private struct ShortcutsCard: View {
  let title: String
  let entries: [CatalogEntry]
  @Bindable var model: SettingsModel
  let page: SettingsPage
  var showsAlias = true

  var body: some View {
    Card {
      ShortcutsHeading(title: title, showsAlias: showsAlias)
      ForEach(entries) { entry in
        Divider()
        ShortcutRow(entry: entry, model: model, page: page, showsAlias: showsAlias)
      }
    }
  }
}

private struct ShortcutsHeading: View {
  let title: String
  var showsAlias = true

  var body: some View {
    HStack(spacing: 10) {
      Text(title).frame(maxWidth: .infinity, alignment: .leading)
      if showsAlias { Text("Alias").frame(width: 110, alignment: .leading) }
      Text("Hotkey").frame(width: 170, alignment: .leading)
      Text("On").frame(width: 24)
    }
    .font(.system(size: 12))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
  }
}

/// Every app, in a List: it reuses its rows, so a few hundred scroll smoothly where a stack of
/// them all, each with fields and an icon, stuttered.
private struct ApplicationsPage: View {
  @Bindable var model: SettingsModel
  @State private var filter = ""

  private var entries: [CatalogEntry] {
    filter.isEmpty
      ? model.appEntries
      : model.appEntries.filter {
        $0.title.localizedCaseInsensitiveContains(filter)
          || model.alias(of: $0.target).localizedCaseInsensitiveContains(filter)
      }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      LoadErrorBanner(model: model)
      HStack(alignment: .center) {
        PageHeader(page: .applications)
        Spacer(minLength: 16)
        TextField("Search apps", text: $filter)
          .textFieldStyle(.roundedBorder)
          .frame(width: 180)
      }
      VStack(spacing: 0) {
        ShortcutsHeading(title: "Application")
        Divider()
        List(entries) { entry in
          ShortcutRow(entry: entry, model: model, page: .applications)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .thinScroller()
      }
      .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .padding(.horizontal, 28)
    .padding(.top, 44)
    .padding(.bottom, 20)
    .onAppear { if model.apps.isEmpty { model.loadApps() } }
  }
}

private struct ShortcutRow: View {
  let entry: CatalogEntry
  @Bindable var model: SettingsModel
  let page: SettingsPage
  var showsAlias = true

  var body: some View {
    HStack(spacing: 10) {
      icon.frame(width: 20, height: 20)
      Text(entry.title)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      // Drawn by SwiftUI until clicked: an AppKit text field, button and checkbox in every row
      // made scrolling a few hundred apps stutter.
      if showsAlias {
        AliasField(target: entry.target, model: model)
          .frame(width: 110)
      }
      HotkeyRecorder(target: entry.target, model: model)
        .frame(width: 170, alignment: .leading)
      Checkbox(isOn: model.isEnabled(entry.target)) {
        model.setEnabled(!model.isEnabled(entry.target), for: entry.target)
      }
      .frame(width: 24)
    }
    .font(.system(size: 13))
    .padding(.horizontal, 14)
    .frame(height: 36)
  }

  @ViewBuilder private var icon: some View {
    if let appURL = entry.appURL {
      Image(nsImage: appIcon(appURL)).resizable()
    } else {
      PageIcon(page: page, size: 20)
    }
  }

}

/// An alias shown as text, turning into a field when clicked. Saved as typed: switching pages
/// or closing the window doesn't take focus, so waiting for focus to leave could drop the edit.
private struct AliasField: View {
  let target: HotkeyTarget
  @Bindable var model: SettingsModel

  private var isEditing: Bool { model.editingAlias == target }

  var body: some View {
    let alias = model.alias(of: target)
    Group {
      if isEditing {
        // The panel's bare AppKit field: no white well, and it takes focus as it appears.
        SearchField(
          text: alias, placeholder: "Alias", fontSize: 13,
          onChange: { model.setAlias($0, for: target) },
          onCommand: { command in
            switch command {
            case .submit, .cancel: model.editingAlias = nil
            default: break
            }
          },
          onEnd: { if model.editingAlias == target { model.editingAlias = nil } })
      } else {
        // A plain button: drawn by SwiftUI, yet reachable with Tab and Full Keyboard Access.
        Button {
          model.stopRecording()
          model.editingAlias = target
        } label: {
          Text(alias.isEmpty ? "Alias" : alias)
            .foregroundStyle(alias.isEmpty ? .tertiary : .primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(alias.isEmpty ? "Add alias" : "Alias \(alias)")
      }
    }
    .settingsCell(isActive: isEditing)
  }
}

extension View {
  /// The alias and hotkey cells' shared shape: bare until active, then an outlined pill, as
  /// Raycast draws a field being edited.
  fileprivate func settingsCell(isActive: Bool) -> some View {
    padding(.horizontal, 9)
      .frame(height: 28)
      .background(
        Color.primary.opacity(isActive ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        if isActive {
          RoundedRectangle(cornerRadius: 8).strokeBorder(
            Color.primary.opacity(0.28), lineWidth: 1.5)
        }
      }
  }
}

/// A checkbox SwiftUI draws itself, for the same reason as AliasField.
private struct Checkbox: View {
  let isOn: Bool
  let onToggle: () -> Void

  var body: some View {
    Button(action: onToggle) {
      Image(systemName: isOn ? "checkmark.square.fill" : "square")
        .font(.system(size: 15))
        .foregroundStyle(isOn ? Color.accentColor : .secondary)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Enabled")
    .accessibilityValue(isOn ? "On" : "Off")
  }
}

/// Click to record: the next key press with a modifier becomes the hotkey.
private struct HotkeyRecorder: View {
  let target: HotkeyTarget
  @Bindable var model: SettingsModel
  var clearable = true

  var body: some View {
    let spec = model.hotkey(of: target)
    let isRecording = model.recordingTarget == target
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Button {
          isRecording ? model.stopRecording() : model.startRecording(for: target)
        } label: {
          HStack(spacing: 4) {
            if isRecording {
              Text("Press keys…").foregroundStyle(.secondary)
            } else if let keycaps = spec.flatMap(Hotkey.init)?.keycaps {
              ForEach(keycaps, id: \.self) { Keycap($0) }
            } else {
              Text(spec ?? "Add Hotkey").foregroundStyle(.tertiary)
            }
          }
          .contentShape(Rectangle())
        }
        // Plain and SwiftUI-drawn, like the alias beside it; recording shows as its soft fill.
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .settingsCell(isActive: isRecording)
        .accessibilityLabel(
          isRecording ? "Recording hotkey" : "Record hotkey, currently \(spec ?? "none")")
        if clearable, spec != nil, !isRecording {
          Button {
            model.setHotkey(nil, for: target)
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.borderless)
          .foregroundStyle(.tertiary)
          .accessibilityLabel("Remove hotkey")
        }
        if model.failedHotkeys.contains(target) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .help("macOS refused this hotkey.")
            .accessibilityLabel("macOS refused this hotkey")
        }
      }
      if let message = model.recorderMessage, message.target == target {
        Text(message.text).font(.system(size: 11)).foregroundStyle(.orange)
      }
    }
  }
}

/// Git Repositories' folders, scan depth and the app each Return opens a repository in.
private struct RepositoriesSettings: View {
  @Bindable var model: SettingsModel

  private var settings: RepositorySettings { model.config.repositories }

  var body: some View {
    Card {
      SettingRow(
        title: "Folders", description: "Where to look for repositories, and how many folders down."
      ) {
        Stepper(
          "Depth \(settings.depth)", value: $model.config.repositories.depth, in: 1...6)
      }
      ForEach(Array(settings.folders.enumerated()), id: \.offset) { index, folder in
        Divider()
        HStack {
          Image(systemName: "folder").foregroundStyle(.secondary)
          Text(folder).font(.system(size: 13, design: .monospaced))
          Spacer()
          Button {
            model.config.repositories.folders = settings.folders.enumerated()
              .filter { $0.offset != index }.map(\.element)
          } label: {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
          .accessibilityLabel("Remove \(folder)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
      }
      Divider()
      HStack {
        Spacer()
        Button("Add Folder…", action: addFolder)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
    }
    Card {
      SettingRow(
        title: "Open With",
        description: "The app each Return opens a repository in; ↵ without one shows it in Finder."
      ) { EmptyView() }
      ForEach(RepositorySettings.OpenKey.allCases, id: \.self) { key in
        Divider()
        OpenWithRow(key: key, model: model)
      }
    }
  }

  private func addFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = "Add"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let home = NSHomeDirectory()
    // Kept with ~, so the config reads the same on another account.
    let path = Search.tildePath(url.path, home: home)
    if !settings.folders.contains(path) {
      model.config.repositories.folders = settings.folders + [path]
    }
  }
}

/// App icons at 20pt, drawn once each from the full icon (up to 1024px), so a list of them
/// scrolls without scaling a big image per row. NSCache is thread-safe, and the icons are
/// rendered off the main thread before a list needs them.
nonisolated(unsafe) private let appIcons = NSCache<NSString, NSImage>()

nonisolated func appIcon(_ app: URL) -> NSImage {
  if let cached = appIcons.object(forKey: app.path as NSString) { return cached }
  let full = NSWorkspace.shared.icon(forFile: app.path)
  // 2× for Retina.
  let side = 40
  let small = NSImage(size: NSSize(width: 20, height: 20))
  if let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)
  {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    full.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    small.addRepresentation(bitmap)
  }
  appIcons.setObject(small, forKey: app.path as NSString)
  return small
}

/// One Return's app, picked from a dropdown of the installed apps as Raycast's settings do.
private struct OpenWithRow: View {
  let key: RepositorySettings.OpenKey
  @Bindable var model: SettingsModel
  @State private var isPicking = false

  private var app: URL? {
    model.config.repositories.openWith[key.rawValue].map { URL(fileURLWithPath: $0) }
  }

  var body: some View {
    HStack(spacing: 10) {
      Text("Shortcut").foregroundStyle(.secondary)
      Keycap(key.shortcut)
      Spacer()
      Button {
        isPicking.toggle()
      } label: {
        HStack(spacing: 6) {
          if let app {
            Image(nsImage: appIcon(app)).resizable().frame(width: 18, height: 18)
            Text(app.deletingPathExtension().lastPathComponent)
          } else {
            Text(key == .plain ? "Finder" : "–").foregroundStyle(.secondary)
          }
          Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
      }
      .buttonStyle(.plain)
      .popover(isPresented: $isPicking, arrowEdge: .bottom) {
        AppPicker(model: model, noneLabel: key == .plain ? "Finder" : "–") { picked in
          model.config.repositories.openWith[key.rawValue] = picked?.path
          isPicking = false
        }
        // Frosted, between the default glass that let what's behind wash out the names and opaque.
        .presentationBackground(.regularMaterial)
      }
    }
    .font(.system(size: 13))
    .padding(.horizontal, 18)
    .padding(.vertical, 8)
  }
}

/// The installed apps, laid out like Raycast's dropdown: rounded rows with a soft highlight that
/// follows the pointer and the arrows, and the search field at the bottom, focused as it opens.
private struct AppPicker: View {
  @Bindable var model: SettingsModel
  let noneLabel: String
  let onPick: (URL?) -> Void
  @State private var query = ""
  @State private var highlighted = 0
  /// macOS's popover corner is about 20pt; rows inset 8pt round at 12pt to sit inside it evenly.
  private static let inset: CGFloat = 8
  private static let rowRadius: CGFloat = 12
  @FocusState private var isSearchFocused: Bool

  /// nil stands for the "none" row.
  private var rows: [AppEntry?] {
    let unique = Dictionary(model.apps.map { ($0.settingsKey, $0) }) { first, _ in first }.values
    let apps =
      unique
      .filter { query.isEmpty || $0.names.contains { $0.localizedStandardContains(query) } }
      .sorted { $0.names[0].localizedStandardCompare($1.names[0]) == .orderedAscending }
    return (query.isEmpty ? [nil] : []) + apps.map(Optional.some)
  }

  var body: some View {
    let rows = rows
    VStack(spacing: 0) {
      // A lazy stack with icons rendered ahead scrolls smoothly; a List brought the system
      // scroller, thick and in its own gutter when scroll bars are set to always show.
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, app in
              row(app, isHighlighted: index == highlighted)
                .id(index)
                .onHover { if $0 { highlighted = index } }
                .onTapGesture { onPick(app?.url) }
            }
          }
          // The popover's corner radius less this inset is the rows', so the corners nest.
          .padding(Self.inset)
        }
        .thinScroller()
        .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
      }
      // At the bottom, as Raycast's: the list's top and bottom corners stay clear for the thumb.
      Divider().opacity(0.5)
      TextField("Search…", text: $query)
        .textFieldStyle(.plain)
        .focused($isSearchFocused)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .onChange(of: query) { highlighted = 0 }
        .onKeyPress(keys: [.downArrow, .upArrow], phases: [.down, .repeat]) { press in
          let next = highlighted + (press.key == .downArrow ? 1 : -1)
          highlighted = min(max(next, 0), max(rows.count - 1, 0))
          return .handled
        }
        .onSubmit { if rows.indices.contains(highlighted) { onPick(rows[highlighted]?.url) } }
    }
    .font(.system(size: 13))
    .frame(width: 280, height: 320)
    .onAppear {
      if model.apps.isEmpty { model.loadApps() }
      DispatchQueue.main.async { isSearchFocused = true }
      prerenderIcons()
    }
    .onChange(of: model.apps) { prerenderIcons() }
  }

  /// Every icon drawn before the list asks for it, so scrolling never waits on one.
  private func prerenderIcons() {
    let urls = model.apps.map(\.url)
    Task.detached(priority: .userInitiated) { for url in urls { _ = appIcon(url) } }
  }

  private func row(_ app: AppEntry?, isHighlighted: Bool) -> some View {
    HStack(spacing: 10) {
      if let app {
        Image(nsImage: appIcon(app.url)).frame(width: 20, height: 20)
        Text(app.names[0]).lineLimit(1)
      } else {
        Text(noneLabel).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(height: 34)
    .background(
      RoundedRectangle(cornerRadius: Self.rowRadius)
        .fill(Color.primary.opacity(isHighlighted ? 0.08 : 0))
    )
    .contentShape(RoundedRectangle(cornerRadius: Self.rowRadius))
  }
}

/// Each permission with its state and a button to grant it; rechecked whenever Ripcord comes
/// back to the front, so a change made in System Settings shows up when the user returns.
private struct PermissionsCard: View {
  /// The reset note, for the Permissions page; a first run has nothing to reset.
  var showsReset = true
  @State private var statuses: [Permission: Permission.Status] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Card {
        ForEach(Array(Permission.allCases.enumerated()), id: \.element) { index, permission in
          if index > 0 { Divider() }
          PermissionRow(permission: permission, status: statuses[permission]) {
            await refresh()
          }
        }
      }
      if showsReset {
        HStack(alignment: .firstTextBaseline) {
          Text(
            "Accessibility on but not working after an update? This resets only Accessibility and restarts Ripcord; then grant it again."
          )
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 12)
          Button("Reset Accessibility") {
            Task { await Permission.resetAccessibilityAndRelaunch() }
          }
        }
        .padding(.horizontal, 4)
      }
    }
    .task { await refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in Task { await refresh() } }
  }

  private func refresh() async {
    for permission in Permission.allCases {
      statuses[permission] = await permission.status()
    }
  }
}

private struct PermissionRow: View {
  let permission: Permission
  let status: Permission.Status?
  let onChange: () async -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: permission.symbol)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(Color.gray.gradient, in: RoundedRectangle(cornerRadius: 6))
      VStack(alignment: .leading, spacing: 2) {
        Text(permission.title).font(.system(size: 13))
        Text(permission.purpose).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      control
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
  }

  /// "Granted" or "Not Granted", as apps commonly put it, and the button that grants it.
  @ViewBuilder private var control: some View {
    switch status {
    case .granted:
      state("Granted", "checkmark.circle.fill", .green)
    case .denied:
      state("Not Granted", "xmark.circle.fill", .red)
      // macOS won't ask again once it's been turned down; only System Settings can change it.
      Button("Open System Settings") { permission.openSystemSettings() }
    case .notAsked:
      state("Not Granted", "xmark.circle.fill", .red)
      grantButton
    case .unknown:
      // The app isn't running, so macOS can't say; no red mark for what may well be granted.
      grantButton
    case nil:
      ProgressView().controlSize(.small)
    }
  }

  /// macOS's request; Accessibility's carries its own Open System Settings button.
  private var grantButton: some View {
    Button("Grant Access") {
      Task {
        await permission.request()
        await onChange()
      }
    }
  }

  private func state(_ text: String, _ symbol: String, _ color: Color) -> some View {
    Label(text, systemImage: symbol)
      .font(.system(size: 12))
      .foregroundStyle(color)
      .padding(.trailing, 4)
  }
}

/// The first launch's guide: the hotkey, Launch at Login and the permissions, on one page.
struct WelcomeView: View {
  @Bindable var model: SettingsModel
  let onDone: () -> Void

  var body: some View {
    // Sized to fit, no scrolling: the window takes this view's height.
    VStack(alignment: .leading, spacing: 16) {
      LoadErrorBanner(model: model)
      HStack(spacing: 14) {
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
        VStack(alignment: .leading, spacing: 3) {
          Text("Welcome to Ripcord").font(.system(size: 20, weight: .semibold))
          Text(
            "Open apps, search, paste from your clipboard history and snippets, and move windows, from one hotkey."
          )
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
        }
      }
      Card {
        SettingRow(
          title: "Ripcord Hotkey",
          description: "Shows the panel from any app. Free ⌘Space in System Settings to use it."
        ) {
          HotkeyRecorder(target: .launcher, model: model, clearable: false)
        }
        Divider()
        SettingRow(title: "Launch at Login", description: "Start Ripcord when you log in.") {
          Toggle("Launch at Login", isOn: $model.config.launchAtLogin)
            .toggleStyle(.switch)
            .labelsHidden()
        }
      }
      Text("Permissions").font(.system(size: 13, weight: .semibold))
      PermissionsCard(showsReset: false)
      HStack {
        Text("Everything here is in Settings (⌘,) later.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        Spacer()
        Button("Get Started", action: onDone)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(.horizontal, 28)
    .padding(.top, 36)
    .padding(.bottom, 24)
    .frame(width: 660)
    .fixedSize(horizontal: false, vertical: true)
    .onChange(of: model.config) { model.saveIfChanged() }
  }
}

/// The white rounded group the settings pages are built from.
private struct Card<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    // A soft gray fill rather than an outline, as Raycast's settings group their rows.
    VStack(spacing: 0) { content }
      .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }
}

/// A title with a one-line description on the left and its control on the right.
private struct SettingRow<Control: View>: View {
  let title: String
  let description: String
  var detail: String?
  @ViewBuilder let control: Control

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 13))
        Text(description).font(.system(size: 12)).foregroundStyle(.secondary)
        if let detail {
          Text(detail)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .padding(.top, 3)
        }
      }
      Spacer(minLength: 16)
      control
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 13)
  }
}
