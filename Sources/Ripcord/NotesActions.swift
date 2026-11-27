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
  var isEnabled = true
  var isDestructive = false
  var startsSection = false
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
        text: model.filter, placeholder: "Search for actions…", fontSize: 14,
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
          Text("No Results").font(.system(size: 13)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).frame(height: 40)
        } else if rows.count > Self.visibleRows {
          ScrollView { items(rows) }.thinScroller()
            .frame(height: CGFloat(Self.visibleRows) * 36)
        } else {
          items(rows)
        }
      }
      .padding(6)
    }
    .frame(width: Self.width)
    // Frosted, as Raycast's panel is over whatever is behind the note.
    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func items(_ rows: [NotesAction]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(rows.enumerated()), id: \.offset) { index, action in
        if action.startsSection, index > 0, model.filter.isEmpty {
          Divider().opacity(0.5).padding(.vertical, 4)
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
          .font(.system(size: 13))
          .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
          .opacity(action.isEnabled ? 1 : 0.4)
          .padding(.horizontal, 10)
          .frame(height: 34)
          .background(
            RoundedRectangle(cornerRadius: 8)
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
