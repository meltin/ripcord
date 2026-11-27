import AppKit
import CryptoKit
import LinkPresentation
import Observation

/// Links' favicons and social images, as Raycast's "Show visual information for links": fetched
/// once with LinkPresentation and kept as PNGs in Ripcord's caches folder. A view asks for what's
/// kept and, when nothing is, starts a fetch; it redraws once the file is there.
@MainActor
@Observable
final class LinkPreviews {
  static let shared = LinkPreviews()

  /// Off, nothing is fetched and no favicon or image is shown.
  var isEnabled = true
  /// Bumped as each fetch lands, so views that asked redraw.
  private(set) var version = 0

  @ObservationIgnored private var requested: Set<URL> = []
  @ObservationIgnored private let folder = URL.cachesDirectory.appending(path: "Ripcord/Links")

  /// The favicon of `url`'s site, once fetched; starts the fetch the first time it's asked.
  func icon(for url: URL) -> URL? {
    guard isEnabled, let site = Self.site(of: url) else { return nil }
    _ = version
    let file = folder.appending(path: "icon-\(Self.key(site)).png")
    if FileManager.default.fileExists(atPath: file.path) { return file }
    fetch(site)
    return nil
  }

  /// The social image of the page at `url`, once fetched; starts the fetch the first time.
  func image(for url: URL) -> URL? {
    guard isEnabled, Self.site(of: url) != nil else { return nil }
    _ = version
    let file = folder.appending(path: "image-\(Self.key(url)).png")
    if FileManager.default.fileExists(atPath: file.path) { return file }
    fetch(url)
    return nil
  }

  /// Fetches `url`'s metadata once per launch, keeping its icon for the site and its image for
  /// the page.
  private func fetch(_ url: URL) {
    guard !requested.contains(url) else { return }
    requested.insert(url)
    Task {
      let provider = LPMetadataProvider()
      provider.timeout = 10
      guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return }
      let site = Self.site(of: url) ?? url
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      if let icon = await Self.png(from: metadata.iconProvider) {
        try? icon.write(to: folder.appending(path: "icon-\(Self.key(site)).png"))
      }
      if let image = await Self.png(from: metadata.imageProvider) {
        try? image.write(to: folder.appending(path: "image-\(Self.key(url)).png"))
      }
      version += 1
    }
  }

  /// The site's home page, port and all, for its favicon; nil for anything but a web address.
  private static func site(of url: URL) -> URL? {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host()
    else { return nil }
    return URL(string: "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? ""))
  }

  private static func key(_ url: URL) -> String {
    SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(12)
      .map { String(format: "%02x", $0) }.joined()
  }

  /// An item provider's image as PNG, scaled down so a huge social image stays small on disk.
  private static func png(from provider: NSItemProvider?) async -> Data? {
    guard let provider, provider.canLoadObject(ofClass: NSImage.self) else { return nil }
    let data: Data? = await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(for: .image) { data, _ in
        continuation.resume(returning: data)
      }
    }
    guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 800,
        ] as CFDictionary)
    else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }
}
