import AppKit
import MetalKit
import RipcordCore
import SwiftUI

/// Draws the panel's backdrop shader in an MTKView behind its text. Made only when a shader is
/// chosen, so with the backdrop off there's no Metal device, view or drawing at all.
@MainActor
final class BackdropRenderer: NSObject, MTKViewDelegate {
  /// What the shader is fed each frame besides time and size.
  struct State {
    var lastKeystroke: Date?
    var queryLength = 0
  }

  var state = State()
  /// Why the chosen shader isn't drawing, for Settings; nil while it compiles and draws.
  private(set) var error: String?
  var onError: (String?) -> Void = { _ in }

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private var pipeline: MTLRenderPipelineState?
  /// The body last compiled, so an unchanged file isn't compiled again on every show.
  private var compiled: String?
  private var shownAt = Date()
  /// The panel is showing, so the view draws: set before SwiftUI may have made the view.
  private var isRunning = false
  private weak var view: MTKView?

  init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
    guard let device, let queue = device.makeCommandQueue() else { return nil }
    self.device = device
    self.queue = queue
  }

  /// Compiles `body` off the main thread and draws it once it's ready; one that doesn't compile
  /// leaves the last that did, and says why.
  func load(_ body: String) {
    guard body != compiled else { return }
    compiled = body
    let device = device
    let source = Backdrop.source(body: body)
    Task.detached {
      let result: Result<MTLRenderPipelineState, Error>
      do {
        let library = try await device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "ripcord_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "ripcord_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Premultiplied over what's behind: the panel's glass.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        result = .success(try await device.makeRenderPipelineState(descriptor: descriptor))
      } catch {
        result = .failure(error)
      }
      await MainActor.run { [weak self] in self?.finish(result, for: body) }
    }
  }

  /// Says why a shader can't even be read.
  func fail(_ message: String) {
    compiled = nil
    report(message)
  }

  private func finish(_ result: Result<MTLRenderPipelineState, Error>, for body: String) {
    // One asked for before another, finishing after it, is no longer the one chosen.
    guard body == compiled else { return }
    switch result {
    case .success(let state):
      pipeline = state
      report(nil)
      view?.needsDisplay = true
    case .failure(let failure):
      report(failure.localizedDescription)
    }
  }

  private func report(_ message: String?) {
    error = message
    onError(message)
  }

  /// Starts drawing as the panel shows: animated, or one still frame when the system asks for
  /// less motion or power.
  func start() {
    shownAt = .now
    isRunning = true
    applyRunning()
  }

  /// Stops drawing while the panel is hidden.
  func stop() {
    isRunning = false
    applyRunning()
  }

  private func applyRunning() {
    guard let view else { return }
    let still =
      !isRunning
      || Backdrop.isStill(
        reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    view.enableSetNeedsDisplay = still
    view.isPaused = still
    if isRunning, still { view.needsDisplay = true }
  }

  func makeView() -> MTKView {
    let view = PassThroughMTKView(frame: .zero, device: device)
    view.colorPixelFormat = .bgra8Unorm
    view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    view.layer?.isOpaque = false
    view.preferredFramesPerSecond = 30
    view.delegate = self
    self.view = view
    applyRunning()
    return view
  }

  nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  nonisolated func draw(in view: MTKView) {
    MainActor.assumeIsolated { render(in: view) }
  }

  private func render(in view: MTKView) {
    guard let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
      let buffer = queue.makeCommandBuffer(),
      let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
    else { return }
    if let pipeline {
      let scale = Float(view.window?.backingScaleFactor ?? 2)
      let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
      let dark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      // A still frame is drawn a few seconds in, so a shader that builds up isn't empty.
      let time = view.isPaused ? 4 : Float(Date.now.timeIntervalSince(shownAt))
      var inputs = Inputs(
        size: SIMD2(Float(view.bounds.width), Float(view.bounds.height)), time: time,
        dark: dark ? 1 : 0,
        accent: SIMD4(
          Float(accent.redComponent), Float(accent.greenComponent),
          Float(accent.blueComponent), 1),
        keystroke: Float(
          min(state.lastKeystroke.map { Date.now.timeIntervalSince($0) } ?? 10_000, 10_000)),
        query: Float(state.queryLength), field: Float(LauncherController.fieldHeight),
        scale: scale)
      encoder.setRenderPipelineState(pipeline)
      encoder.setFragmentBytes(&inputs, length: MemoryLayout<Inputs>.stride, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
    encoder.endEncoding()
    buffer.present(drawable)
    buffer.commit()
  }

  /// The shader's `Backdrop`, field for field.
  private struct Inputs {
    var size: SIMD2<Float>
    var time: Float
    var dark: Float
    var accent: SIMD4<Float>
    var keystroke: Float
    var query: Float
    var field: Float
    var scale: Float
  }
}

/// The backdrop never takes a click, a drag or the keys: they go to the panel above and around it.
private final class PassThroughMTKView: MTKView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override var acceptsFirstResponder: Bool { false }
  override var mouseDownCanMoveWindow: Bool { true }
}

/// The renderer's view, in SwiftUI.
struct BackdropView: NSViewRepresentable {
  let renderer: BackdropRenderer

  func makeNSView(context: Context) -> MTKView { renderer.makeView() }
  func updateNSView(_ view: MTKView, context: Context) {}
}

/// The backdrop when one is chosen; nothing at all when it's off.
struct PanelBackdrop: View {
  let model: LauncherModel

  var body: some View {
    if let renderer = model.backdrop {
      BackdropView(renderer: renderer)
        .id(ObjectIdentifier(renderer))
        .allowsHitTesting(false)
    }
  }
}
