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
  private var saved = Config.default

  init(configURL: URL) { self.configURL = configURL }

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
    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  /// Picks up edits made to the file in an editor while the window was in the background.
  func windowDidBecomeKey(_ notification: Notification) {
    model.load()
  }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
  case general = "General"
  case quicklinks = "Quicklinks"

  var id: Self { self }

  var symbol: String {
    switch self {
    case .general: "slider.horizontal.3"
    case .quicklinks: "link"
    }
  }

  var color: Color {
    switch self {
    case .general: .gray
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
        HotkeyRecorder(spec: $model.config.hotkey, onRecordingChange: model.onRecordingChange)
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

/// Click to record: the next key press with a modifier becomes the hotkey.
private struct HotkeyRecorder: View {
  @Binding var spec: String
  let onRecordingChange: (Bool) -> Void
  @State private var monitor: Any?

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 4) {
        if monitor != nil {
          Text("Press keys…").foregroundStyle(.secondary)
        } else {
          ForEach(Hotkey(spec)?.keycaps ?? [spec], id: \.self) { Keycap($0) }
        }
      }
      .frame(minWidth: 80, minHeight: 22)
    }
    .accessibilityLabel(monitor == nil ? "Record hotkey, currently \(spec)" : "Recording hotkey")
    .onDisappear(perform: stop)
    // Switching away mid-recording must not leave the global hotkey unregistered.
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
      stop()
    }
  }

  private func toggle() {
    monitor == nil ? start() : stop()
  }

  private func start() {
    onRecordingChange(true)
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == UInt16(kVK_Escape) {
        stop()
      } else if let hotkey = Hotkey(
        keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(event.modifierFlags))
      {
        spec = hotkey.spec
        stop()
      }
      return nil
    }
  }

  private func stop() {
    guard let monitor else { return }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
    onRecordingChange(false)
  }

  private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    let pairs: [(NSEvent.ModifierFlags, Int)] = [
      (.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey),
    ]
    return pairs.filter { flags.contains($0.0) }.map { UInt32($0.1) }.reduce(0, |)
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
