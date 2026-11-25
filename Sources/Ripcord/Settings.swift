import AppKit
import Carbon.HIToolbox
import RipcordCore
import SwiftUI

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
  /// Hotkeys macOS refused at the last registration, shown on their rows.
  var failedHotkeys: Set<HotkeyTarget> = []
  /// Scanned when the Shortcuts page first appears, so the window costs nothing until then.
  var apps: [AppEntry] = []
  /// The one row recording a hotkey; starting another row stops it.
  private(set) var recordingTarget: HotkeyTarget?
  private(set) var recorderMessage: (target: HotkeyTarget, text: String)?
  private var saved = Config.default
  private var keyMonitor: Any?

  init(configURL: URL) { self.configURL = configURL }

  func loadApps() {
    Task { apps = await Task.detached(priority: .userInitiated) { AppIndex.scan() }.value }
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

  func startRecording(for target: HotkeyTarget) {
    stopRecording()
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
    guard
      let hotkey = Hotkey(
        keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(event.modifierFlags))
    else {
      recorderMessage = (target, "Use ⌘, ⌥ or ⌃ (⇧ optional) with a letter, a digit or Space.")
      return
    }
    if let owner = config.owner(of: hotkey, except: target) {
      recorderMessage = (target, "Already used by \(name(of: owner)).")
      return
    }
    setHotkey(hotkey.spec, for: target)
    // Saved before re-registering, so the new hotkey is the one that comes back.
    saveIfChanged()
    stopRecording()
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
        ?? apps.first { $0.settingsKey == key }?.names[0]
        // Before the Shortcuts page has scanned the apps, ask Launch Services.
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
      contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = "Ripcord Settings"
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: SettingsView(model: model))
    window.delegate = self
    window.center()
    return window
  }()

  init(model: SettingsModel) { self.model = model }

  /// Becomes a regular app while the window is open, as Raycast does: macOS 14 only lets an
  /// accessory app ask to come forward, and the request loses to the app the user was in.
  func show() {
    NSApp.setActivationPolicy(.regular)
    // On top of other apps' windows even if macOS turns the activation request down.
    window.orderFrontRegardless()
    window.makeKey()
    // The policy change lands on the next run loop pass; asking before it is asking as an
    // accessory app.
    DispatchQueue.main.async { NSApp.activate() }
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
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
  case shortcuts = "Shortcuts"
  case quicklinks = "Quicklinks"

  var id: Self { self }

  var symbol: String {
    switch self {
    case .general: "slider.horizontal.3"
    case .shortcuts: "command"
    case .quicklinks: "link"
    }
  }

  var color: Color {
    switch self {
    case .general: .gray
    case .shortcuts: .indigo
    case .quicklinks: .blue
    }
  }
}

struct SettingsView: View {
  @Bindable var model: SettingsModel
  @State private var page: SettingsPage? = .general

  var body: some View {
    // The sidebar never collapses, so the toolbar has no toggle to slide the title around.
    NavigationSplitView(columnVisibility: .constant(.all)) {
      List(SettingsPage.allCases, selection: $page) { page in
        Label {
          Text(page.rawValue)
        } icon: {
          Image(systemName: page.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(page.color.gradient, in: RoundedRectangle(cornerRadius: 5))
        }
      }
      .navigationSplitViewColumnWidth(220)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let loadError = model.loadError {
            Label(loadError, systemImage: "exclamationmark.triangle.fill")
              .font(.system(size: 12))
              .foregroundStyle(.red)
          }
          switch page {
          case .general: GeneralPage(model: model)
          case .shortcuts: ShortcutsPage(model: model)
          case .quicklinks: QuicklinksPage(model: model)
          case nil: EmptyView()
          }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .navigationTitle(page?.rawValue ?? "Settings")
    }
    .frame(minWidth: 760, minHeight: 480)
    .onChange(of: model.config) { model.saveIfChanged() }
    // A recording left running on a page no longer shown would swallow every key typed.
    .onChange(of: page) { model.stopRecording() }
  }
}

private struct GeneralPage: View {
  @Bindable var model: SettingsModel

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
    HStack(alignment: .firstTextBaseline) {
      Text(
        "Type a keyword, a space and a query in the panel. {query} in the URL is replaced by what you type."
      )
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
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

/// Lists every app, Quicklink and command with its alias, hotkey and on/off switch.
private struct ShortcutsPage: View {
  @Bindable var model: SettingsModel
  @State private var filter = ""

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(
        "An alias is typed in the panel; a hotkey runs the item from any app; unchecked items never show up in search."
      )
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
      Spacer()
      TextField("Filter", text: $filter)
        .textFieldStyle(.roundedBorder)
        .frame(width: 180)
    }
    .onAppear { if model.apps.isEmpty { model.loadApps() } }
    ForEach(Search.catalog(apps: model.apps, quicklinks: model.config.quicklinks)) { section in
      let entries = section.entries.filter(matches)
      if !entries.isEmpty {
        Card {
          HStack(spacing: 10) {
            Text(section.title).frame(maxWidth: .infinity, alignment: .leading)
            Text("Alias").frame(width: 110, alignment: .leading)
            Text("Hotkey").frame(width: 170, alignment: .leading)
            Text("On").frame(width: 24)
          }
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          // Lazy: the Applications section can hold hundreds of rows.
          LazyVStack(spacing: 0) {
            ForEach(entries) { entry in
              Divider()
              ShortcutRow(entry: entry, model: model)
            }
          }
        }
      }
    }
  }

  private func matches(_ entry: CatalogEntry) -> Bool {
    filter.isEmpty || entry.title.localizedCaseInsensitiveContains(filter)
      || model.alias(of: entry.target).localizedCaseInsensitiveContains(filter)
  }
}

private struct ShortcutRow: View {
  let entry: CatalogEntry
  @Bindable var model: SettingsModel

  var body: some View {
    HStack(spacing: 10) {
      icon.frame(width: 20, height: 20)
      Text(entry.title)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      TextField(
        "Alias",
        text: Binding {
          model.alias(of: entry.target)
        } set: {
          model.setAlias($0, for: entry.target)
        }
      )
      .textFieldStyle(.roundedBorder)
      .frame(width: 110)
      HotkeyRecorder(target: entry.target, model: model)
        .frame(width: 170, alignment: .leading)
      Toggle(
        "Enabled",
        isOn: Binding {
          model.isEnabled(entry.target)
        } set: {
          model.setEnabled($0, for: entry.target)
        }
      )
      .toggleStyle(.checkbox)
      .labelsHidden()
      .frame(width: 24)
    }
    .font(.system(size: 13))
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
  }

  @ViewBuilder private var icon: some View {
    if let appURL = entry.appURL {
      Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path)).resizable()
    } else {
      Image(systemName: entry.kind == .quicklink ? "link" : "command")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 20, height: 20)
        .background(
          (entry.kind == .quicklink ? Color.blue : Color.gray).gradient,
          in: RoundedRectangle(cornerRadius: 5))
    }
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
              Text(spec ?? "Add Hotkey").foregroundStyle(.secondary)
            }
          }
          .frame(minWidth: 80, minHeight: 22)
        }
        .accessibilityLabel(
          isRecording ? "Recording hotkey" : "Record hotkey, currently \(spec ?? "none")")
        if clearable, spec != nil, !isRecording {
          Button {
            model.setHotkey(nil, for: target)
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
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

/// The white rounded group the settings pages are built from.
private struct Card<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) { content }
      .background(.background, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
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
        Text(title).font(.system(size: 13, weight: .medium))
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
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }
}
