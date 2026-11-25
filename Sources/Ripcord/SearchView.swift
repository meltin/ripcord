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
        if let logo = Bundle.main.image(forResource: "MenuBarIcon") {
          Image(nsImage: logo).renderingMode(.template).foregroundStyle(.secondary)
        }
        SearchField(text: model.query, onChange: onQueryChange, onCommand: onCommand)
      }
      .padding(.horizontal, 20)
      .frame(height: LauncherController.fieldHeight)
      Divider().opacity(0.5)
      if model.sections.isEmpty {
        EmptyState(query: model.query)
      } else {
        resultList
      }
    }
    // Floats over the list like Raycast's footer, so rows scroll on underneath it.
    .overlay(alignment: .bottom) { Footer(selected: model.selected, onCommand: onCommand) }
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
              ResultRow(result: result, isSelected: result.id == selectedID)
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

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 34, weight: .light))
        .foregroundStyle(.tertiary)
      Text("No Results").font(.system(size: 15, weight: .semibold))
      Text("Nothing matches “\(query)”. Add a Quicklink in Settings to search the web with it.")
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
      Text(result.kind.label).font(.system(size: 13)).foregroundStyle(.secondary)
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
    case .run(.quit):
      tile("power", .red)
    case .reveal:
      tile("folder", .gray)
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

private struct Footer: View {
  let selected: SearchResult?
  let onCommand: (SearchCommand) -> Void

  var body: some View {
    HStack {
      HoverButton {
        onCommand(.toggleMenu(root: true))
      } label: {
        Image(systemName: "equal")
          .font(.system(size: 15, weight: .medium))
          .frame(width: 32, height: 32)
      }
      .glassEffect(.regular.interactive(), in: Circle())
      .accessibilityLabel("Ripcord menu")
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
            Image(systemName: item.symbol).frame(width: 18)
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
    Text(label)
      .font(.system(size: 10))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
      .frame(minWidth: 18, minHeight: 18)
      .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.45)))
  }
}

extension SearchResult.Kind {
  fileprivate var label: String {
    switch self {
    case .application: "Application"
    case .calculator: "Calculator"
    case .quicklink: "Quicklink"
    case .command: "Command"
    }
  }
}

/// An AppKit text field, because only `doCommandBy` hands over arrows and Return after the input
/// method has had them, so Japanese IME composition keeps working.
private struct SearchField: NSViewRepresentable {
  let text: String
  let onChange: (String) -> Void
  let onCommand: (SearchCommand) -> Void

  func makeNSView(context: Context) -> FocusingTextField {
    let field = FocusingTextField()
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 18)
    field.placeholderString = "Search apps, calculate, open Quicklinks…"
    field.cell?.isScrollable = true
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ field: FocusingTextField, context: Context) {
    context.coordinator.parent = self
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
