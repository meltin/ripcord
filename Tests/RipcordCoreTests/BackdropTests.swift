import Foundation
import Metal
import Testing

@testable import RipcordCore

struct BackdropTests {
  @Test func builtInShadersCompile() throws {
    // Skipped where there's no GPU to compile for.
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    for shader in Backdrop.builtIns {
      let library = try device.makeLibrary(source: Backdrop.source(body: shader.body), options: nil)
      #expect(library.makeFunction(name: "ripcord_fragment") != nil, "\(shader.name)")
    }
  }

  @Test func reportsAnErrorOnTheShadersOwnLine() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let body = "float4 backdrop(float2 p, Backdrop b) {\n  return nope;\n}"
    #expect {
      try device.makeLibrary(source: Backdrop.source(body: body), options: nil)
    } throws: { error in
      "\(error)".contains(":2:")
    }
  }

  @Test func listsOffTheBuiltInsAndTheFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "ripcord-shaders-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: folder.appending(path: "mine.metal"))
    try Data("x".utf8).write(to: folder.appending(path: "notes.txt"))
    #expect(Backdrop.choices(in: folder) == ["off", "glow", "matrix", "mine.metal"])
    #expect(try Backdrop.body(for: "off", in: folder) == nil)
    #expect(try Backdrop.body(for: "mine.metal", in: folder) == "x")
    #expect(throws: (any Error).self) { try Backdrop.body(for: "gone.metal", in: folder) }
  }

  @Test func holdsStillWhenTheSystemAsks() {
    #expect(!Backdrop.isStill(reduceMotion: false, lowPower: false))
    #expect(Backdrop.isStill(reduceMotion: true, lowPower: false))
    #expect(Backdrop.isStill(reduceMotion: false, lowPower: true))
  }

  @Test func isOffUnlessSet() throws {
    let config = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"cmd+space"}"#.utf8))
    #expect(config.backdrop == "off")
  }
}
