import AppKit
import RipcordCore
import SwiftUI

/// Runs a Script Command off the main thread: no shell between, nothing on stdin, both outputs
/// read as they come and capped, so a chatty script can't stall on a full pipe.
enum ScriptRunner {
  struct Result: Sendable {
    let status: Int32
    let output: String
    let errors: String
  }

  /// Each stream keeps at most this much; a toast shows one line of it.
  static let limit = 256 * 1024

  /// `arguments` go to the script as $1…, as they are: no shell reads them.
  static func run(
    _ script: ScriptCommand, arguments: [String] = [],
    completion: @escaping @Sendable (Result) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let process = Process()
      process.executableURL = script.url
      process.arguments = arguments
      process.currentDirectoryURL = script.directory
      var environment = ProcessInfo.processInfo.environment
      environment["PATH"] = loginPath
      process.environment = environment
      process.standardInput = FileHandle.nullDevice
      let output = Pipe()
      let errors = Pipe()
      process.standardOutput = output
      process.standardError = errors
      let collected = Collected()
      output.fileHandleForReading.readabilityHandler = {
        collected.append($0.availableData, to: .output)
      }
      errors.fileHandleForReading.readabilityHandler = {
        collected.append($0.availableData, to: .errors)
      }
      do {
        try process.run()
      } catch {
        return completion(Result(status: -1, output: "", errors: error.localizedDescription))
      }
      process.waitUntilExit()
      // A moment for the handlers to take what's left, then stop: a child the script left
      // running would hold the pipes open, and reading to their end would wait for it.
      usleep(150_000)
      output.fileHandleForReading.readabilityHandler = nil
      errors.fileHandleForReading.readabilityHandler = nil
      try? output.fileHandleForReading.close()
      try? errors.fileHandleForReading.close()
      let (out, err) = collected.text
      completion(Result(status: process.terminationStatus, output: out, errors: err))
    }
  }

  /// The login shell's PATH, read once, so a script finds what a login shell's profile adds
  /// (Homebrew's or nix's in `.zprofile`; not what only `.zshrc` adds). Ripcord's own PATH plus
  /// /usr/local/bin, as Raycast appends, when the shell can't say.
  static let loginPath: String = {
    let fallback =
      (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
      + ":/usr/local/bin"
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    guard (try? process.run()) != nil else { return fallback }
    // A login shell that hangs mustn't hold the script up.
    let deadline = Date.now.addingTimeInterval(3)
    while process.isRunning, Date.now < deadline { usleep(20_000) }
    if process.isRunning {
      process.terminate()
      return fallback
    }
    let path = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return path.isEmpty ? fallback : path
  }()

  /// Both outputs, appended from the pipes' handlers, which run on their own threads.
  private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var errors = Data()

    enum Stream { case output, errors }

    func append(_ data: Data, to stream: Stream) {
      guard !data.isEmpty else { return }
      lock.lock()
      defer { lock.unlock() }
      let kept = stream == .output ? output : errors
      let added = kept + data.prefix(max(ScriptRunner.limit - kept.count, 0))
      if stream == .output { output = added } else { errors = added }
    }

    var text: (String, String) {
      lock.lock()
      defer { lock.unlock() }
      return (String(decoding: output, as: UTF8.self), String(decoding: errors, as: UTF8.self))
    }
  }
}

/// A line over the screen for a moment, as Raycast's HUD shows a silent script's output after
/// its window closes.
@MainActor
enum HUD {
  private static var window: NSPanel?
  private static var hideTask: DispatchWorkItem?

  static func show(_ text: String, failed: Bool = false) {
    let panel = window ?? makePanel()
    window = panel
    panel.contentView = NSHostingView(rootView: HUDView(text: text, failed: failed))
    panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 300, height: 40))
    if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      panel.setFrameOrigin(
        NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + frame.height * 0.12))
    }
    panel.orderFrontRegardless()
    hideTask?.cancel()
    let task = DispatchWorkItem { MainActor.assumeIsolated { window?.orderOut(nil) } }
    hideTask = task
    DispatchQueue.main.asyncAfter(deadline: .now() + (failed ? 4 : 2), execute: task)
  }

  private static func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    return panel
  }
}

private struct HUDView: View {
  let text: String
  let failed: Bool

  var body: some View {
    HStack(spacing: 8) {
      if failed { Glyph("exclamationmark.triangle.fill", pointSize: 13).foregroundStyle(.red) }
      Text(text).lineLimit(2).font(.system(size: Metrics.scriptHUDFontSize, weight: .medium))
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 40)
    .frame(maxWidth: 480)
    .glassEffect(.regular, in: Capsule())
    .padding(8)
  }
}
