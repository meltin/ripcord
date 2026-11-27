import AppKit
import RipcordCore
import SwiftUI

/// Raycast's inline emoji picker on one of Ripcord's text views: `:` and a word open a list of
/// the emoji it names under the caret; ↑↓ choose, Return or Tab put the emoji in place of the
/// word, Esc closes the list.
@MainActor
final class InlineEmojiPicker: NSObject {
  /// Off with Settings › Emoji & Symbols' Disable Inline Emoji Picker.
  static var isEnabled = true

  /// Bundled with the app, read the first time a picker needs it.
  static let catalog: EmojiCatalog? = Bundle.main
    .url(forResource: "emoji", withExtension: "json", subdirectory: "Emoji")
    .flatMap { try? EmojiCatalog(data: Data(contentsOf: $0)) }

  private weak var textView: NSTextView?
  private var observers: [NSObjectProtocol] = []
  private var keyMonitor: Any?
  private var panel: NSPanel?
  private let list = SuggestionList()
  private var token: NSRange?

  func attach(to textView: NSTextView) {
    guard self.textView !== textView else { return }
    detach()
    self.textView = textView
    let center = NotificationCenter.default
    observers = [
      center.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) {
        [weak self] _ in MainActor.assumeIsolated { self?.update() }
      },
      // A click elsewhere in the text, or the window going away, closes the list.
      center.addObserver(
        forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.update() } },
      center.addObserver(
        forName: NSWindow.didResignKeyNotification, object: textView.window, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.hide() } },
    ]
  }

  private func detach() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    hide()
  }

  isolated deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    panel?.orderOut(nil)
  }

  private func update() {
    guard Self.isEnabled, let textView, let catalog = Self.catalog, !textView.hasMarkedText(),
      textView.selectedRange().length == 0,
      let found = InlineEmoji.token(in: textView.string, caret: textView.selectedRange().location)
    else { return hide() }
    let items = InlineEmoji.suggestions(for: found.word, catalog: catalog)
    guard !items.isEmpty else { return hide() }
    token = found.range
    if list.items.map(\.character) != items.map(\.character) { list.selection = 0 }
    list.items = items
    show(under: found.range, in: textView)
  }

  private func show(under range: NSRange, in textView: NSTextView) {
    let panel = panel ?? makePanel()
    self.panel = panel
    // Just under the word, in screen coordinates.
    let word = textView.firstRect(forCharacterRange: range, actualRange: nil)
    let size = NSSize(width: 260, height: CGFloat(list.items.count) * 28 + 12)
    panel.setFrame(
      NSRect(x: word.minX, y: word.minY - size.height - 4, width: size.width, height: size.height),
      display: true)
    if panel.parent == nil { textView.window?.addChildWindow(panel, ordered: .above) }
    panel.orderFront(nil)
    if keyMonitor == nil {
      keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        let taken = MainActor.assumeIsolated { self?.takes(event) ?? false }
        return taken ? nil : event
      }
    }
  }

  private func hide() {
    token = nil
    if let panel {
      panel.parent?.removeChildWindow(panel)
      panel.orderOut(nil)
    }
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
  }

  /// Whether the list takes this key while it's up; the rest go on to the text.
  private func takes(_ event: NSEvent) -> Bool {
    guard let textView, event.window === textView.window, token != nil,
      event.modifierFlags.intersection([.command, .control, .option]).isEmpty
    else { return false }
    switch Int(event.keyCode) {
    case 125:  // ↓
      list.selection = (list.selection + 1) % list.items.count
    case 126:  // ↑
      list.selection = (list.selection + list.items.count - 1) % list.items.count
    case 36, 76, 48:  // Return, Enter, Tab
      insert(list.selection)
    case 53:  // Esc
      hide()
    default:
      return false
    }
    return true
  }

  private func insert(_ index: Int) {
    guard let textView, let token, list.items.indices.contains(index) else { return }
    let emoji = list.items[index].character
    hide()
    // As typed, so it can be undone and the editor formats it.
    if textView.shouldChangeText(in: token, replacementString: emoji) {
      textView.textStorage?.replaceCharacters(in: token, with: emoji)
      textView.didChangeText()
      textView.setSelectedRange(
        NSRange(location: token.location + (emoji as NSString).length, length: 0))
    }
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.contentView = NSHostingView(
      rootView: SuggestionListView(list: list) { [weak self] in self?.insert($0) })
    return panel
  }
}

@MainActor
@Observable
private final class SuggestionList {
  var items: [(character: String, name: String)] = []
  var selection = 0
}

private struct SuggestionListView: View {
  let list: SuggestionList
  let onPick: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
        HStack(spacing: 8) {
          Text(item.character).font(.system(size: Metrics.cardFieldFontSize))
          Text(item.name).font(.system(size: Metrics.cardFontSize)).lineLimit(1)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.cardRowPadding)
        .frame(height: 28)
        .background(
          RoundedRectangle(cornerRadius: Metrics.cardRowRadius)
            .fill(index == list.selection ? Color.primary.opacity(0.1) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onPick(index) }
      }
    }
    .padding(Metrics.cardPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.cardRadius))
  }
}
