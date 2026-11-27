import AppKit
import SwiftUI

/// One of Ripcord Notes' actions, listed as Raycast Notes' ⌘K panel lists them and run by its
/// keys whether the panel is open or not.
struct NotesAction {
  let title: String
  let symbol: String
  /// The keys, as `charactersIgnoringModifiers` gives them; the first is the one shown.
  let keys: [String]
  let modifiers: NSEvent.ModifierFlags
  /// Matched by where the key is rather than what it types, for keys Shift changes: ⇧⌘7 types
  /// & on a US keyboard and ' on a Japanese one.
  var keyCode: Int?
  var isEnabled = true
  var isDestructive = false
  var startsSection = false
  /// A titled section starting here, as Format as… groups Inline, Block and List.
  var section: String?
  /// Leaves the panel open, as Heading… does to list the levels.
  var keepsPanelOpen = false
  let run: @MainActor () -> Void

  /// As Raycast shows it, modifiers first: ⇧⌘/.
  var shortcut: String {
    let order: [(NSEvent.ModifierFlags, String)] = [
      (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]
    let mods = order.filter { modifiers.contains($0.0) }.map(\.1).joined()
    return mods + (keys.first ?? "").uppercased()
  }

  func matches(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    if let keyCode { return flags == modifiers && Int(event.keyCode) == keyCode }
    guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
    // ⌘+ is typed as ⌘= on most layouts; either works, as in Raycast.
    let pressed = flags.subtracting(key == "+" ? .shift : [])
    return pressed == modifiers && keys.contains(key)
  }
}

/// What the actions panel shows: the actions, narrowed by "Search for actions…".
@MainActor
@Observable
final class NotesActionsModel {
  var actions: [NotesAction] = []
  /// "Search for actions…", or Format as… for the formats.
  var placeholder = "Search for actions…"
  var filter = "" {
    didSet { selection = shown.firstIndex(where: \.isEnabled) ?? 0 }
  }
  var selection = 0

  var shown: [NotesAction] {
    let query = filter.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return actions }
    return actions.filter { $0.title.localizedStandardContains(query) }
  }

  /// The next enabled row up or down, staying put at either end.
  func move(by step: Int) {
    let rows = shown
    var index = selection + step
    while rows.indices.contains(index), !rows[index].isEnabled { index += step }
    if rows.indices.contains(index) { selection = index }
  }
}

/// Raycast Notes' action panel: "Search for actions…" over the actions with their keys.
struct NotesActionsView: View {
  @Bindable var model: NotesActionsModel
  let onRun: (NotesAction) -> Void
  let onClose: () -> Void

  static let width: CGFloat = 320
  private static let visibleRows = 10

  var body: some View {
    VStack(spacing: 0) {
      SearchField(
        text: model.filter, placeholder: model.placeholder, fontSize: Metrics.cardFieldFontSize,
        onChange: { model.filter = $0 },
        onCommand: { command in
          switch command {
          case .up: model.move(by: -1)
          case .down: model.move(by: 1)
          case .submit:
            let rows = model.shown
            if rows.indices.contains(model.selection), rows[model.selection].isEnabled {
              onRun(rows[model.selection])
            }
          case .cancel, .back: onClose()
          default: break
          }
        }
      )
      .padding(.horizontal, 16)
      .frame(height: 44)
      Divider().opacity(0.5)
      let rows = model.shown
      Group {
        if rows.isEmpty {
          Text("No Results").font(.system(size: Metrics.cardFontSize)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).frame(height: 40)
        } else if rows.count > Self.visibleRows {
          ScrollView { items(rows) }.thinScroller()
            .frame(height: CGFloat(Self.visibleRows) * 36)
        } else {
          items(rows)
        }
      }
      .padding(Metrics.cardPadding)
    }
    .frame(width: Self.width)
    // Frosted over whatever is behind the note, as CONTRIBUTING's popovers are.
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.cardRadius))
  }

  private func items(_ rows: [NotesAction]) -> some View {
    VStack(alignment: .leading, spacing: Metrics.cardRowSpacing) {
      ForEach(Array(rows.enumerated()), id: \.offset) { index, action in
        if action.startsSection || action.section != nil, index > 0, model.filter.isEmpty {
          Divider().opacity(0.5).padding(.vertical, 4)
        }
        if let section = action.section, model.filter.isEmpty {
          Text(section)
            .font(.system(size: Metrics.cardTitleFontSize, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Metrics.cardRowPadding)
            .padding(.vertical, 4)
        }
        Button {
          onRun(action)
        } label: {
          HStack(spacing: 10) {
            Glyph(action.symbol, pointSize: 14).frame(width: 18)
            Text(action.title).lineLimit(1)
            Spacer(minLength: 16)
            HStack(spacing: 3) {
              ForEach(Array(action.shortcut.map(String.init).enumerated()), id: \.offset) {
                Keycap($0.element)
              }
            }
          }
          .font(.system(size: Metrics.cardFontSize))
          .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
          .opacity(action.isEnabled ? 1 : 0.4)
          .padding(.horizontal, Metrics.cardRowPadding)
          .frame(height: Metrics.cardRowHeight)
          .background(
            RoundedRectangle(cornerRadius: Metrics.cardRowRadius)
              .fill(index == model.selection ? Color.primary.opacity(0.1) : .clear)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        // The pointer moves the selection, so Return and the click agree.
        .onHover { if $0, action.isEnabled { model.selection = index } }
      }
    }
  }
}

/// The panel the actions float in, over the note's window as Raycast's does, taking keys for
/// its search field without bringing Ripcord forward.
final class NotesActionsPanel: NSPanel {
  var onEscape: () -> Void = {}

  override var canBecomeKey: Bool { true }

  override func cancelOperation(_ sender: Any?) { onEscape() }
}
