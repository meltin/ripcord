import AppKit
import RipcordCore
import SwiftUI

struct SearchView: View {
  let model: LauncherModel
  let onQueryChange: (String) -> Void
  let onCommand: (SearchCommand) -> Void

  private var selectedID: String? { model.selected?.id }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        if model.mode == .clipboard {
          HoverButton {
            onCommand(.back)
          } label: {
            Image(systemName: "chevron.left")
              .font(.system(size: 15, weight: .medium))
              .frame(width: 28, height: 28)
          }
          .accessibilityLabel("Back")
        } else if let logo = Bundle.main.image(forResource: "MenuBarIcon") {
          Image(nsImage: logo).renderingMode(.template).foregroundStyle(.secondary)
        }
        SearchField(
          text: model.query,
          placeholder: model.mode == .clipboard
            ? "Search Clipboard History…" : "Search apps, calculate, open Quicklinks…",
          onChange: onQueryChange, onCommand: onCommand)
      }
      .padding(.horizontal, 20)
      .frame(height: LauncherController.fieldHeight)
      .background(DragArea())
      Divider().opacity(0.5)
      if model.sections.isEmpty {
        EmptyState(query: model.query, mode: model.mode)
      } else if model.mode == .clipboard {
        // Raycast's layout: the list on the left, the selected item and its details on the right.
        HStack(spacing: 0) {
          resultList.frame(width: 300)
          Divider().opacity(0.5)
          if case .clip(let id, _) = model.selected?.action, let history = model.clipboard,
            let item = history.item(id)
          {
            ClipPreview(item: item, imageURL: history.imageURL(of: item))
          } else {
            Spacer()
          }
        }
      } else {
        resultList
      }
    }
    // Floats over the list like Raycast's footer, so rows scroll on underneath it.
    .overlay(alignment: .bottom) {
      Footer(selected: model.selected, mode: model.mode, onCommand: onCommand)
    }
    .overlay {
      if let menu = model.menu {
        ZStack(alignment: menu.isRoot ? .bottomLeading : .bottomTrailing) {
          // A click anywhere outside the card closes it, like a dialog's backdrop.
          Color.clear.contentShape(Rectangle()).onTapGesture { onCommand(.cancel) }
          MenuCard(menu: menu, onCommand: onCommand)
            // Covers the footer, as Raycast's action panel does.
            .padding(8)
        }
      }
    }
  }

  private var resultList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(model.sections) { section in
            Text(section.title)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 12)
              .padding(.top, 10)
              .padding(.bottom, 4)
            ForEach(section.results) { result in
              ResultRow(
                result: result, isSelected: result.id == selectedID,
                showsKind: model.mode == .root
              )
              .id(result.id)
              .onTapGesture { onCommand(.activate(result.id)) }
            }
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, LauncherController.footerHeight)
      }
      .scrollIndicators(.never)
      .onChange(of: model.selection) {
        if let selectedID { proxy.scrollTo(selectedID) }
      }
    }
  }
}

private struct EmptyState: View {
  let query: String
  let mode: LauncherMode

  private var message: String {
    switch mode {
    case .root:
      "Nothing matches “\(query)”. Add a Quicklink in Settings to search the web with it."
    case .clipboard where query.trimmingCharacters(in: .whitespaces).isEmpty:
      "Text and images you copy show up here."
    case .clipboard:
      "Nothing copied contains “\(query)”."
    }
  }

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 34, weight: .light))
        .foregroundStyle(.tertiary)
      Text("No Results").font(.system(size: 15, weight: .semibold))
      Text(message)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ResultRow: View {
  let result: SearchResult
  let isSelected: Bool
  /// Off in Clipboard History, whose narrow list has no room for it.
  var showsKind = true

  var body: some View {
    HStack(spacing: 12) {
      ResultIcon(result: result)
      Text(result.title).font(.system(size: 14)).lineLimit(1)
      if !result.subtitle.isEmpty {
        Text(result.subtitle).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
      }
      if let keyword = result.keyword {
        Text(keyword)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
      }
      Spacer(minLength: 12)
      if showsKind {
        Text(result.kind.label).font(.system(size: 13)).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: LauncherController.rowHeight)
    .background(
      RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.primary.opacity(0.1) : .clear)
    )
    .contentShape(Rectangle())
  }
}

/// App icons as macOS draws them; everything else as a white symbol on a colored tile.
private struct ResultIcon: View {
  let result: SearchResult

  var body: some View {
    switch result.action {
    case .open(let url) where url.isFileURL:
      // App icons carry a transparent margin, so draw them larger than the 24pt slot to match.
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        .frame(width: 30, height: 30)
        .padding(-3)
    case .copy:
      tile("plus.forwardslash.minus", .orange)
    case .open:
      tile("link", .blue)
    case .run(.settings):
      tile("gearshape.fill", .gray)
    case .run(.resetWindowPosition):
      tile("macwindow", .gray)
    case .run(.quit):
      tile("power", .red)
    case .reveal:
      tile("folder", .gray)
    case .run(.clipboardHistory):
      tile("list.clipboard.fill", .red)
    case .clip:
      if let thumbnail = result.thumbnail {
        Thumbnail(url: thumbnail, maxPixelSize: 64).frame(width: 24, height: 24)
      } else {
        tile("doc.text", .gray)
      }
    }
  }

  private func tile(_ symbol: String, _ color: Color) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 24, height: 24)
      .background(color.gradient, in: RoundedRectangle(cornerRadius: 6))
  }
}

/// The selected clip in full, then its details, as Raycast's Clipboard History shows them.
private struct ClipPreview: View {
  let item: ClipItem
  let imageURL: URL?

  private var details: [(label: String, value: String)] {
    var rows = [(label: String, value: String)]()
    switch item.content {
    case .text(let text):
      rows.append(("Type", "Text"))
      rows.append(("Characters", "\(text.count)"))
      rows.append(("Words", "\(text.split(whereSeparator: \.isWhitespace).count)"))
    case .image(_, let width, let height):
      rows.append(("Type", "Image"))
      rows.append(("Dimensions", "\(width)×\(height)"))
    }
    rows.append(("Times copied", "\(item.copies)"))
    rows.append(("Last copied", item.date.formatted(date: .abbreviated, time: .shortened)))
    rows.append(("First copied", item.firstDate.formatted(date: .abbreviated, time: .shortened)))
    return rows
  }

  private var sourceApp: URL? {
    item.source.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group {
        switch item.content {
        case .text(let text):
          ScrollView {
            // A 1 MB clip would stall layout; the start is what anyone reads here.
            Text(String(text.prefix(20_000)))
              .font(.system(size: 12))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .topLeading)
              .padding(16)
          }
        case .image:
          if let imageURL {
            Thumbnail(url: imageURL, maxPixelSize: 800)
              .padding(16)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .frame(maxHeight: .infinity)
      Divider().opacity(0.5)
      VStack(alignment: .leading, spacing: 2) {
        Text("Information")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.bottom, 4)
        if let sourceApp {
          detailRow("Source", index: 0) {
            HStack(spacing: 6) {
              Image(nsImage: NSWorkspace.shared.icon(forFile: sourceApp.path)).resizable()
                .frame(width: 16, height: 16)
              Text(FileManager.default.displayName(atPath: sourceApp.path))
            }
          }
        }
        ForEach(Array(details.enumerated()), id: \.offset) { index, row in
          detailRow(row.label, index: index + (sourceApp == nil ? 0 : 1)) { Text(row.value) }
        }
      }
      .font(.system(size: 12))
      .padding(.horizontal, 8)
      .padding(.top, 10)
      // Clear of the floating footer.
      .padding(.bottom, LauncherController.footerHeight)
    }
  }

  private func detailRow<Value: View>(
    _ label: String, index: Int, @ViewBuilder value: () -> Value
  ) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      value()
    }
    .padding(.horizontal, 8)
    .frame(height: 24)
    .background(
      index.isMultiple(of: 2) ? Color.primary.opacity(0.05) : .clear,
      in: RoundedRectangle(cornerRadius: 6))
  }
}

/// A clipboard image, decoded off the main thread at `maxPixelSize` and cached, so a screenshot
/// in the history never sits in memory at full size.
private struct Thumbnail: View {
  let url: URL
  let maxPixelSize: Int
  @State private var image: NSImage?

  private static let cache = NSCache<NSString, NSImage>()
  private var key: NSString { "\(maxPixelSize)/\(url.path)" as NSString }

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
      } else {
        Color.clear
      }
    }
    .task(id: key) {
      if let cached = Self.cache.object(forKey: key) {
        image = cached
        return
      }
      let made = await Task.detached(priority: .userInitiated) {
        [url, maxPixelSize] () -> CGImage? in
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
          kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      }.value
      guard let made else { return }
      let thumbnail = NSImage(cgImage: made, size: .zero)
      Self.cache.setObject(thumbnail, forKey: key)
      image = thumbnail
    }
  }
}

private struct Footer: View {
  let selected: SearchResult?
  let mode: LauncherMode
  let onCommand: (SearchCommand) -> Void

  var body: some View {
    HStack {
      if mode == .clipboard {
        // Names the command the panel is in, as Raycast's footer does.
        HStack(spacing: 8) {
          Image(systemName: "list.clipboard.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 5))
          Text("Clipboard History")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .glassEffect(.regular, in: Capsule())
      } else {
        HoverButton {
          onCommand(.toggleMenu(root: true))
        } label: {
          Image(systemName: "equal")
            .font(.system(size: 15, weight: .medium))
            .frame(width: 32, height: 32)
        }
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("Ripcord menu")
      }
      Spacer()
      HStack(spacing: 2) {
        if let selected {
          HoverButton {
            onCommand(.submit)
          } label: {
            HStack(spacing: 6) {
              Text(selected.kind.primaryAction)
              Keycap("↵")
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
          }
        }
        HoverButton {
          onCommand(.toggleMenu(root: false))
        } label: {
          HStack(spacing: 6) {
            Text("Actions").foregroundStyle(.secondary)
            HStack(spacing: 2) {
              Keycap("⌘")
              Keycap("K")
            }
          }
          .padding(.horizontal, 10)
          .frame(height: 26)
        }
      }
      .padding(.horizontal, 3)
      .frame(height: 32)
      .glassEffect(.regular, in: Capsule())
    }
    .font(.system(size: 12))
    .padding(.horizontal, 8)
    .frame(height: LauncherController.footerHeight)
    .background(DragArea())
  }
}

/// Empty space that moves the panel when dragged, like Raycast's window background.
private struct DragArea: View {
  var body: some View {
    Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
  }
}

/// A footer button that lights up a capsule under the pointer, as Raycast's footer does.
private struct HoverButton<Label: View>: View {
  let action: () -> Void
  @ViewBuilder let label: Label
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      label
        .background(Capsule().fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

/// Raycast's action panel: a floating list with a title and each item's shortcut.
private struct MenuCard: View {
  let menu: OpenMenu
  let onCommand: (SearchCommand) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(menu.title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
      ForEach(Array(menu.items.enumerated()), id: \.offset) { index, item in
        Button {
          onCommand(.runMenuItem(index))
        } label: {
          HStack(spacing: 10) {
            Image(systemName: item.symbol)
              .font(.system(size: 13, weight: .light))
              .frame(width: 18)
            Text(item.title)
            Spacer(minLength: 16)
            HStack(spacing: 3) {
              ForEach(Array(item.shortcut.map(String.init).enumerated()), id: \.offset) {
                Keycap($0.element)
              }
            }
          }
          .font(.system(size: 13))
          .padding(.horizontal, 10)
          .frame(height: 34)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(index == menu.selection ? Color.primary.opacity(0.1) : .clear)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The pointer moves the selection, so Return and the click agree.
        .onHover { if $0 { onCommand(.selectMenuItem(index)) } }
      }
    }
    .padding(6)
    .frame(width: 300)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
  }
}

struct Keycap: View {
  let label: String

  init(_ label: String) { self.label = label }

  var body: some View {
    // Filled and softly edged, like Raycast's keycaps.
    Text(label)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
      .frame(minWidth: 18, minHeight: 18)
      .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.12)))
  }
}

extension SearchResult.Kind {
  fileprivate var label: String {
    switch self {
    case .application: "Application"
    case .calculator: "Calculator"
    case .quicklink: "Quicklink"
    case .command: "Command"
    case .text: "Text"
    case .image: "Image"
    }
  }
}

/// An AppKit text field, because only `doCommandBy` hands over arrows and Return after the input
/// method has had them, so Japanese IME composition keeps working.
private struct SearchField: NSViewRepresentable {
  let text: String
  let placeholder: String
  let onChange: (String) -> Void
  let onCommand: (SearchCommand) -> Void

  func makeNSView(context: Context) -> FocusingTextField {
    let field = FocusingTextField()
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 18)
    field.cell?.isScrollable = true
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ field: FocusingTextField, context: Context) {
    context.coordinator.parent = self
    if field.placeholderString != placeholder { field.placeholderString = placeholder }
    let isComposing = (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    if !isComposing, field.stringValue != text { field.stringValue = text }
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: SearchField

    init(parent: SearchField) { self.parent = parent }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.onChange(field.stringValue)
    }

    func control(
      _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
    ) -> Bool {
      let command: SearchCommand? =
        switch selector {
        case #selector(NSResponder.moveUp(_:)): .up
        case #selector(NSResponder.moveDown(_:)): .down
        case #selector(NSResponder.insertNewline(_:)): .submit
        case #selector(NSResponder.cancelOperation(_:)): .cancel
        default: nil
        }
      guard let command else { return false }
      parent.onCommand(command)
      return true
    }
  }
}

final class FocusingTextField: NSTextField {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
  }

  /// The orange caret from the app icon.
  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    (currentEditor() as? NSTextView)?.insertionPointColor = NSColor(
      red: 1, green: 0.353, blue: 0.122, alpha: 1)
    return became
  }
}
