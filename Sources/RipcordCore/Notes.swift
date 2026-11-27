import Foundation

/// A note: one Markdown file in the notes folder, titled by its first line as Raycast Notes are.
public struct Note: Equatable, Sendable {
  public let url: URL
  /// The text as last read from or written to the file; "" for a new one not saved yet.
  public let text: String
  public let modified: Date
  /// Whether the file exists yet: a new note is written only once something is typed.
  public let isSaved: Bool

  public init(url: URL, text: String, modified: Date, isSaved: Bool) {
    self.url = url
    self.text = text
    self.modified = modified
    self.isSaved = isSaved
  }

  public var title: String { Self.title(of: text) }

  /// The first line with text, as the editor shows it: without a heading's `#`s or the marks of
  /// its emphasis; "Untitled" for none.
  public static func title(of text: String) -> String {
    let line = text.split(whereSeparator: \.isNewline).lazy
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty }
    let title = line.map {
      String(MarkdownEditing.shown($0).drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
    }
    return title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
  }
}

/// The notes in `folder`, one `.md` file each, so they stay readable and editable outside Ripcord.
public struct NoteStore: Sendable {
  public let folder: URL

  public init(folder: URL) {
    self.folder = folder
  }

  /// ~/.config/ripcord/notes, beside the config.
  public static let userFolder = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".config/ripcord/notes")

  public enum SaveError: Error, Equatable, LocalizedError {
    /// The file no longer holds what was read: edited elsewhere, so it isn't written over.
    case changedOutside
    /// A new note's name is taken.
    case exists

    public var errorDescription: String? {
      switch self {
      case .changedOutside:
        "This note changed outside Ripcord, so what you typed wasn't saved over it."
      case .exists: "A note with that file name already exists."
      }
    }
  }

  /// Every note that reads as UTF-8, the most recently changed first; other files are left be.
  public func list() -> [Note] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    return names.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
      .compactMap { read(folder.appending(path: $0)) }
      .sorted { $0.modified > $1.modified }
  }

  /// The note at `url` as it is on disk; nil when it's gone or isn't UTF-8 text.
  public func read(_ url: URL) -> Note? {
    guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8)
    else { return nil }
    let modified =
      (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? .distantPast
    return Note(url: url, text: text, modified: modified, isSaved: true)
  }

  /// A new, empty note under a name no file has; nothing is written until it's saved.
  public func newNote(at date: Date = .now) -> Note {
    let stamp = date.formatted(
      .verbatim(
        "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
        timeZone: .current, calendar: .current))
    let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    let name =
      ([""] + (2...99).map { " \($0)" }).lazy.map { "Note \(stamp)\($0).md" }
      .first { !taken.contains($0) } ?? "Note \(stamp) \(UUID().uuidString).md"
    return Note(url: folder.appending(path: name), text: "", modified: date, isSaved: false)
  }

  /// Writes `text` over `note`, which must still be what's on disk; returns the note as saved.
  /// Unchanged text writes nothing, and neither does a new note left empty.
  public func save(_ text: String, over note: Note) throws -> Note {
    guard text != note.text else { return note }
    let data = Data(text.utf8)
    if note.isSaved {
      guard read(note.url)?.text == note.text else { throw SaveError.changedOutside }
      try data.write(to: note.url, options: .atomic)
    } else {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      do {
        try data.write(to: note.url, options: .withoutOverwriting)
      } catch CocoaError.fileWriteFileExists {
        throw SaveError.exists
      }
    }
    return read(note.url) ?? Note(url: note.url, text: text, modified: .now, isSaved: true)
  }

  /// Moves the note's file to the Trash, where it can be put back; where it is in the Trash.
  @discardableResult
  public func trash(_ note: Note) throws -> URL? {
    guard note.isSaved else { return nil }
    var trashed: NSURL?
    try FileManager.default.trashItem(at: note.url, resultingItemURL: &trashed)
    return trashed as URL?
  }

  /// Puts a note moved to the Trash back where it was, as Undo does; the note as it is then.
  public func restore(_ trashed: URL, to url: URL) throws -> Note? {
    try FileManager.default.moveItem(at: trashed, to: url)
    return read(url)
  }
}

extension Search {
  /// Search Notes: every note matching `query` in its title or text, the most recent first.
  public static func noteSections(for query: String, notes: [Note]) -> [SearchSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let rows = notes.filter { trimmed.isEmpty || $0.text.localizedStandardContains(trimmed) }
      .map(result(for:))
    return rows.isEmpty ? [] : [SearchSection(title: "Notes", results: rows)]
  }

  private static func result(for note: Note) -> SearchResult {
    let menu = [
      MenuAction(title: "Open Note", symbol: "return", shortcut: "↵", action: .openNote(note.url)),
      MenuAction(
        title: "Show in Finder", symbol: "folder", shortcut: "⌘↵", action: .reveal(note.url)),
      MenuAction(
        title: "Delete Note", symbol: "trash", shortcut: "⌃X", action: .deleteNote(note.url),
        isDestructive: true, startsSection: true),
    ]
    // The second line with text, as a preview.
    let preview = note.text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.dropFirst().first
    return SearchResult(
      id: "note:\(note.url.path):\(note.title)", title: note.title, subtitle: preview ?? "",
      keyword: nil, kind: .note, action: menu[0].action, menu: menu)
  }
}
