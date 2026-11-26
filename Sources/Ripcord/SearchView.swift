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
        if model.mode != .root {
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
        if model.mode == .snippetForm {
          // A form has no query; the field would take its keys.
          Spacer()
        } else {
          SearchField(
            text: model.query,
            placeholder: model.mode.placeholder,
            onChange: onQueryChange, onCommand: onCommand)
        }
      }
      .padding(.horizontal, 20)
      .frame(height: LauncherController.fieldHeight)
      .background(DragArea())
      // Raycast's form has no rule under its header.
      if model.mode != .snippetForm { Divider().opacity(0.5) }
      if model.mode == .snippetForm {
        SnippetForm(model: model)
      } else if model.sections.isEmpty {
        EmptyState(query: model.query, mode: model.mode)
      } else if model.mode != .root {
        // Raycast's layout: the list on the left, the selected item and its details on the right.
        HStack(spacing: 0) {
          resultList.frame(width: 300)
          Divider().opacity(0.5)
          if case .clip(let id, _) = model.selected?.action, let history = model.clipboard,
            let item = history.item(id)
          {
            ClipPreview(item: item, imageURL: history.imageURL(of: item))
          } else if let selected = model.selected, case .snippet(let index, _) = selected.action,
            model.snippets.indices.contains(index)
          {
            SnippetPreview(result: selected, text: model.snippets[index].text)
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
      Footer(
        selected: model.selected, mode: model.mode, pasteTarget: model.pasteTarget,
        onCommand: onCommand)
    }
    .overlay {
      if let menu = model.menu {
        ZStack(alignment: menu.isRoot ? .bottomLeading : .bottomTrailing) {
          // A click anywhere outside the card closes it, like a dialog's backdrop.
          Color.clear.contentShape(Rectangle()).onTapGesture { onCommand(.cancel) }
          MenuCard(menu: menu, pasteTarget: model.pasteTarget, onCommand: onCommand)
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
    case .snippets where query.trimmingCharacters(in: .whitespaces).isEmpty:
      "Save text you type again and again with Create Snippet."
    case .snippets:
      "No snippet contains “\(query)”."
    case .snippetForm:
      ""
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
      ForEach(result.tags, id: \.self) { tag in
        Text(tag)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(.quaternary, in: Capsule())
      }
      if showsKind {
        Text(result.kind.label).font(.system(size: 13)).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: LauncherController.rowHeight)
    .background(
      // 0.12 darkens the background as much as Raycast's selected row does.
      RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.primary.opacity(0.12) : .clear)
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
    case .run(let command):
      tile(command.symbol, command.color)
    case .reveal:
      tile("folder", .gray)
    case .snippet:
      // Plain, as Raycast draws a snippet's icon.
      Image(systemName: result.symbol ?? "doc")
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
    case .clip:
      if let thumbnail = result.thumbnail {
        // Cropped to a rounded square, as Raycast draws them.
        Thumbnail(url: thumbnail, maxPixelSize: 64, fill: true)
          .frame(width: 24, height: 24)
          .clipShape(RoundedRectangle(cornerRadius: 5))
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

extension BuiltinCommand {
  /// Its icon: a white SF Symbol on a tile of this color.
  fileprivate var symbol: String {
    switch self {
    case .clipboardHistory: "list.clipboard.fill"
    case .searchSnippets: "doc.plaintext.fill"
    case .createSnippet: "doc.badge.plus"
    case .settings: "gearshape.fill"
    case .resetWindowPosition: "macwindow"
    case .quit: "power"
    }
  }

  fileprivate var color: Color {
    switch self {
    case .clipboardHistory, .quit: .red
    case .searchSnippets, .createSnippet: .blue
    case .settings, .resetWindowPosition: .gray
    }
  }
}

/// The selected clip in full, then its details, as Raycast's Clipboard History shows them.
private struct ClipPreview: View {
  let item: ClipItem
  let imageURL: URL?
  // Worked out when the preview is built rather than in body, which redraws more often.
  private let details: [(label: String, value: String)]
  private let sourceApp: URL?

  init(item: ClipItem, imageURL: URL?) {
    self.item = item
    self.imageURL = imageURL
    let content: [(label: String, value: String)] =
      switch item.content {
      case .text(let text):
        [
          ("Type", "Text"), ("Characters", "\(text.count)"),
          ("Words", "\(text.split(whereSeparator: \.isWhitespace).count)"),
        ]
      case .image(_, let width, let height):
        [("Type", "Image"), ("Dimensions", "\(width)×\(height)")]
          + (item.size.map { [("Size", Int64($0).formatted(.byteCount(style: .file)))] } ?? [])
      }
    details =
      content + [
        ("Times copied", "\(item.copies)"),
        ("Last copied", Self.copiedAt(item.date)),
        ("First copied", Self.copiedAt(item.firstDate)),
      ]
    sourceApp = item.source.flatMap {
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
    }
  }

  /// "Today at 9:39", as Raycast writes it; a full date further back.
  private static func copiedAt(_ date: Date) -> String {
    let time = date.formatted(date: .omitted, time: .shortened)
    if Calendar.current.isDateInToday(date) { return "Today at \(time)" }
    if Calendar.current.isDateInYesterday(date) { return "Yesterday at \(time)" }
    return date.formatted(date: .abbreviated, time: .shortened)
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
            Thumbnail(url: imageURL, maxPixelSize: 800, cornerRadius: 10)
              .padding(16)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      // A fixed share for the clip; the details scroll under the footer, as in Raycast.
      .frame(height: 210)
      Divider().opacity(0.5)
      Information {
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
    }
  }
}

/// Create Snippet's form, as Raycast lays it out: the text on the left, name and keyword on the
/// right. ⌘↵ saves; Return types a new line.
private struct SnippetForm: View {
  @Bindable var model: LauncherModel
  @FocusState private var focus: Field?

  private enum Field { case text, name, keyword, tags }

  var body: some View {
    HStack(alignment: .top, spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        label("Snippet")
        TextEditor(text: $model.draft.text)
          .font(.system(size: 13))
          .scrollContentBackground(.hidden)
          .scrollIndicators(.never)
          .padding(10)
          .frame(height: 230)
          .field(isFocused: focus == .text)
          .focused($focus, equals: .text)
          // Tab moves on to Name, as in Raycast, instead of typing a tab into the snippet.
          .onKeyPress(.tab) {
            focus = .name
            return .handled
          }
        let clipboard = Text(verbatim: "{clipboard}").foregroundStyle(.tint)
        let date = Text(verbatim: "{date}").foregroundStyle(.tint)
        let cursor = Text(verbatim: "{cursor}").foregroundStyle(.tint)
        Text(
          "Include \(clipboard), \(date) (or {time}, {datetime}, {day}, {uuid}) and \(cursor), where the caret lands"
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 8) {
        label("Name & Icon")
        HStack(spacing: 0) {
          TextField("Snippet name", text: $model.draft.name)
            .focused($focus, equals: .name)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
          Divider().frame(height: 20)
          Button {
            model.isPickingIcon.toggle()
          } label: {
            HStack(spacing: 6) {
              Image(systemName: model.draft.icon ?? "doc").font(.system(size: 14))
              Image(systemName: model.isPickingIcon ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Choose an icon")
        }
        .frame(height: 36)
        .field(isFocused: focus == .name)
        // Raycast's picker drops down from the field, over what's below it.
        .overlay(alignment: .topTrailing) {
          if model.isPickingIcon {
            IconPicker(selection: $model.draft.icon) { model.isPickingIcon = false }
              .offset(y: 44)
          }
        }
        .zIndex(1)
        label("Keyword").padding(.top, 14)
        TextField(
          "Keyword",
          text: Binding {
            model.draft.keyword ?? ""
          } set: {
            model.draft.keyword = $0.isEmpty ? nil : $0
          }
        )
        .focused($focus, equals: .keyword)
        .inputField(isFocused: focus == .keyword)
        label("Tags").padding(.top, 14)
        TextField("Tags, separated by commas", text: $model.tagsText)
          .focused($focus, equals: .tags)
          .inputField(isFocused: focus == .tags)
      }
    }
    .font(.system(size: 14))
    // Centered with wide margins, as Raycast's form sits in the panel.
    .padding(.horizontal, 56)
    .padding(.top, 12)
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear { focus = .text }
  }

  private func label(_ text: String) -> some View {
    Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
  }
}

extension View {
  /// A form field's outline, as Raycast draws them: no fill, darker while it has focus.
  fileprivate func field(isFocused: Bool) -> some View {
    overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(Color.primary.opacity(isFocused ? 0.3 : 0.15), lineWidth: isFocused ? 2 : 1))
  }

  fileprivate func inputField(isFocused: Bool) -> some View {
    textFieldStyle(.plain)
      .padding(.horizontal, 12)
      .frame(height: 36)
      .field(isFocused: isFocused)
  }
}

/// SF Symbols to choose a snippet's icon from, named as Raycast names its icons.
private let snippetIcons: [(name: String, symbol: String)] = [
  ("Blank Document", "doc"), ("Text Document", "doc.text"), ("Note", "note.text"),
  ("Quote", "quote.opening"), ("List", "list.bullet"), ("Checklist", "checklist"),
  ("Pencil", "pencil"), ("Signature", "signature"), ("Envelope", "envelope"),
  ("Paper Plane", "paperplane"), ("Message", "message"), ("Phone", "phone"), ("At", "at"),
  ("Person", "person"), ("People", "person.2"), ("Building", "building.2"), ("House", "house"),
  ("Location", "mappin.and.ellipse"), ("Globe", "globe"), ("Link", "link"),
  ("Calendar", "calendar"), ("Clock", "clock"), ("Alarm", "alarm"), ("Bell", "bell"),
  ("Key", "key"), ("Lock", "lock"), ("Number", "number"),
  ("Code", "chevron.left.forwardslash.chevron.right"),
  ("Terminal", "terminal"), ("Command", "command"), ("Keyboard", "keyboard"), ("Bug", "ant"),
  ("Hammer", "hammer"), ("Wrench", "wrench.adjustable"), ("Gear", "gearshape"),
  ("Light Bulb", "lightbulb"), ("Star", "star"), ("Heart", "heart"), ("Flag", "flag"),
  ("Bookmark", "bookmark"), ("Tag", "tag"), ("Pin", "pin"), ("Bolt", "bolt"), ("Flame", "flame"),
  ("Sparkles", "sparkles"), ("Magic Wand", "wand.and.stars"), ("Leaf", "leaf"),
  ("Sun", "sun.max"), ("Moon", "moon"), ("Cloud", "cloud"), ("Umbrella", "umbrella"),
  ("Coffee", "cup.and.saucer"), ("Fork & Knife", "fork.knife"), ("Cart", "cart"),
  ("Bag", "bag"), ("Credit Card", "creditcard"), ("Gift", "gift"), ("Book", "book"),
  ("Graduation Cap", "graduationcap"), ("Briefcase", "briefcase"), ("Folder", "folder"),
  ("Tray", "tray"), ("Archive", "archivebox"), ("Paperclip", "paperclip"),
  ("Checkmark", "checkmark.circle"), ("Question Mark", "questionmark.circle"),
  ("Info", "info.circle"), ("Warning", "exclamationmark.triangle"), ("Smile", "face.smiling"),
  ("Hand Wave", "hand.wave"), ("Thumbs Up", "hand.thumbsup"), ("Camera", "camera"),
  ("Photo", "photo"), ("Music", "music.note"), ("Film", "film"), ("Microphone", "mic"),
  ("Car", "car"), ("Airplane", "airplane"), ("Bike", "bicycle"), ("Bird", "bird"),
  ("Paw", "pawprint"), ("Brain", "brain"),
]

/// A searchable list of `snippetIcons`. ↑↓ move, Return picks, a click picks.
private struct IconPicker: View {
  @Binding var selection: String?
  let onClose: () -> Void
  @State private var query = ""
  @State private var highlighted = 0
  @FocusState private var isSearchFocused: Bool

  private var matches: [(name: String, symbol: String)] {
    query.isEmpty ? snippetIcons : snippetIcons.filter { $0.name.localizedStandardContains(query) }
  }

  var body: some View {
    VStack(spacing: 0) {
      TextField("Search…", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .padding(.horizontal, 14)
        .frame(height: 40)
        .focused($isSearchFocused)
        .onChange(of: query) { highlighted = 0 }
        .onKeyPress(.downArrow) {
          highlighted = min(highlighted + 1, max(matches.count - 1, 0))
          return .handled
        }
        .onKeyPress(.upArrow) {
          highlighted = max(highlighted - 1, 0)
          return .handled
        }
        .onSubmit { pick(highlighted) }
      Divider().opacity(0.5)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element.symbol) { index, icon in
              HStack(spacing: 10) {
                Image(systemName: icon.symbol).frame(width: 20)
                Text(icon.name)
                Spacer()
              }
              .font(.system(size: 14))
              .padding(.horizontal, 10)
              .frame(height: 34)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(index == highlighted ? Color.primary.opacity(0.1) : .clear)
              )
              .contentShape(Rectangle())
              .onHover { if $0 { highlighted = index } }
              .onTapGesture { pick(index) }
              .id(index)
            }
          }
          .padding(6)
        }
        .scrollIndicators(.never)
        .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
      }
    }
    .frame(width: 240, height: 300)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    .onAppear { isSearchFocused = true }
  }

  private func pick(_ index: Int) {
    guard matches.indices.contains(index) else { return }
    // The blank document is the default, so it's stored as no icon.
    selection = matches[index].symbol == "doc" ? nil : matches[index].symbol
    onClose()
  }
}

/// The selected snippet's text as saved, placeholders and all, then its details.
private struct SnippetPreview: View {
  let result: SearchResult
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
        Text(text)
          .font(.system(size: 12))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(16)
      }
      .frame(height: 210)
      Divider().opacity(0.5)
      Information {
        detailRow("Name", index: 0) { Text(result.title) }
        if let keyword = result.keyword {
          detailRow("Keyword", index: 1) { Text(keyword) }
        }
        if !result.tags.isEmpty {
          detailRow("Tags", index: result.keyword == nil ? 1 : 2) {
            Text(result.tags.joined(separator: ", "))
          }
        }
      }
    }
  }
}

/// A preview's "Information" rows, scrolling under the floating footer as in Raycast.
private struct Information<Rows: View>: View {
  @ViewBuilder let rows: Rows

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        Text("Information")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.bottom, 4)
        rows
      }
      .font(.system(size: 12))
      .padding(.horizontal, 8)
      .padding(.top, 10)
      // Clear of the floating footer.
      .padding(.bottom, LauncherController.footerHeight)
    }
    .scrollIndicators(.never)
  }
}

/// One striped label-and-value row of a preview's details.
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
    index.isMultiple(of: 2) ? Color.primary.opacity(0.025) : .clear,
    in: RoundedRectangle(cornerRadius: 6))
}

/// A clipboard image, decoded off the main thread at `maxPixelSize` and cached, so a screenshot
/// in the history never sits in memory at full size.
private struct Thumbnail: View {
  let url: URL
  let maxPixelSize: Int
  /// Fills its frame for the caller to crop, instead of fitting inside it.
  var fill = false
  var cornerRadius: CGFloat = 0
  @State private var image: NSImage?

  private static let cache = NSCache<NSString, NSImage>()
  private var key: NSString { "\(maxPixelSize)/\(url.path)" as NSString }

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable()
          .aspectRatio(contentMode: fill ? .fill : .fit)
          .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      } else {
        Color.clear
      }
    }
    .task(id: key) {
      // Cleared first: the view is reused when the selection moves to another image.
      image = Self.cache.object(forKey: key)
      if image != nil { return }
      let made = await Task.detached(priority: .userInitiated) {
        [url, maxPixelSize, fill] () -> CGImage? in
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Filling a square crops the long side, so decode with the short side at maxPixelSize.
        let fullSize = CGImageSourceCreateImageAtIndex(source, 0, nil).map {
          (long: max($0.width, $0.height), short: max(min($0.width, $0.height), 1))
        }
        let size =
          fill ? min(maxPixelSize * (fullSize.map { $0.long / $0.short } ?? 1), 2048) : maxPixelSize
        let options: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: size,
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
  let pasteTarget: String?
  let onCommand: (SearchCommand) -> Void

  var body: some View {
    HStack {
      if let command = mode.command {
        // Names the command the panel is in, as Raycast's footer does.
        HStack(spacing: 8) {
          Image(systemName: command.symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(command.color.gradient, in: RoundedRectangle(cornerRadius: 5))
          Text(command.title).foregroundStyle(.secondary)
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
        if mode == .snippetForm {
          HoverButton {
            onCommand(.submit)
          } label: {
            HStack(spacing: 6) {
              Text("Save Snippet")
              HStack(spacing: 2) {
                Keycap("⌘")
                Keycap("↵")
              }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
          }
        } else if let selected {
          HoverButton {
            onCommand(.submit)
          } label: {
            HStack(spacing: 6) {
              Text(title(of: selected.action, else: selected.kind.primaryAction, pasteTarget))
              Keycap("↵")
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
          }
        }
        if mode != .snippetForm {
          actionsButton
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

  private var actionsButton: some View {
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
  let pasteTarget: String?
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
            Text(title(of: item.action, else: item.title, pasteTarget))
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

/// "Paste to Rex" rather than "Paste to App", naming the app the paste lands in.
private func title(
  of action: SearchResult.Action, else fallback: String, _ pasteTarget: String?
) -> String {
  guard action.isPaste, let pasteTarget else { return fallback }
  return "Paste to \(pasteTarget)"
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
    case .snippet: "Snippet"
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

extension SearchResult.Action {
  fileprivate var isPaste: Bool {
    switch self {
    case .clip(_, .paste), .snippet(_, .paste): true
    default: false
    }
  }
}

extension LauncherMode {
  fileprivate var placeholder: String {
    switch self {
    case .root: "Search apps, calculate, open Quicklinks…"
    case .clipboard: "Search Clipboard History…"
    case .snippets: "Search Snippets…"
    case .snippetForm: ""
    }
  }
}
