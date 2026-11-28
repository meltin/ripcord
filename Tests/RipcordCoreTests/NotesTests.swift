import Foundation
import Testing

@testable import RipcordCore

@Suite struct NotesTests {
  let folder = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)")
  var store: NoteStore { NoteStore(folder: folder) }

  @Test func titlesByTheFirstLineWithText() {
    #expect(Note.title(of: "\n\n# Groceries\n- milk") == "Groceries")
    #expect(Note.title(of: "  plain first line  \nmore") == "plain first line")
    #expect(Note.title(of: "") == "Untitled")
    #expect(Note.title(of: "#\n") == "Untitled")
    #expect(Note.title(of: "# **Big** ~~plan~~\nmore") == "Big plan")
  }

  @Test func writesANewNoteOnlyOnceSomethingIsTyped() throws {
    let new = store.newNote()
    #expect(!new.isSaved)
    // Left empty: nothing is written, not even the folder.
    #expect(try store.save("", over: new) == new)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    let saved = try store.save("# Hello\nworld", over: new)
    #expect(saved.isSaved)
    #expect(try String(contentsOf: new.url, encoding: .utf8) == "# Hello\nworld")
    #expect(store.list().map(\.title) == ["Hello"])
  }

  /// Search Notes' ⌘K, Raycast's with Show in Finder.
  @Test func offersRaycastsNoteActions() throws {
    defer { try? FileManager.default.removeItem(at: folder) }
    let note = try store.save("# Plan\nmore", over: store.newNote())
    let row = try #require(Search.noteSections(for: "", notes: [note]).first?.results.first)
    #expect(
      row.actions.map(\.title) == [
        "Open Note", "Show in Finder", "Copy Content", "Copy Note As…", "Create Note",
        "Duplicate Note", "Delete Note", "Delete All Notes",
      ])
    #expect(row.actions.map(\.shortcut) == ["↵", "⌘↵", "⇧⌘C", "⌥⌘C", "⌘N", "⌘D", "⌃X", "⌃⇧X"])
    #expect(row.actions[2].action == .copy("# Plan\nmore"))
    #expect(
      Search.copyNoteAsMenu(for: note.text).map(\.action) == [
        .copy(note.text), .copy("<h1>Plan</h1>\n<p>more</p>"),
      ])
  }

  /// Copy Note As › HTML keeps the note's structure: headings, paragraphs, lists and tasks,
  /// code, quotes and inline marks, with the text escaped.
  @Test func writesANoteAsHTML() {
    let note = """
      # Plan
      First line with **bold**, *it*, ~~old~~ and a [link](https://a.example/?q=1&b=2).
      Second line <b>.

      - one
      - [ ] todo
      - [x] done
      1. first
      > quoted `x`

      ```
      let a = 1 < 2
      ```
      """
    #expect(
      NoteHTML.html(fromMarkdown: note) == """
        <h1>Plan</h1>
        <p>First line with <strong>bold</strong>, <em>it</em>, <del>old</del> and a \
        <a href="https://a.example/?q=1&amp;b=2">link</a>.<br>Second line &lt;b&gt;.</p>
        <ul><li>one</li><li><input type="checkbox" disabled> todo</li>\
        <li><input type="checkbox" disabled checked> done</li></ul>
        <ol><li>first</li></ol>
        <blockquote>quoted <code>x</code></blockquote>
        <pre><code>let a = 1 &lt; 2</code></pre>
        """)
  }

  /// Duplicate Note: a new file with the same text; the original stays.
  @Test func duplicatesANote() throws {
    defer { try? FileManager.default.removeItem(at: folder) }
    let note = try store.save("# Plan\nmore", over: store.newNote())
    let copy = try store.duplicate(note, at: .now.addingTimeInterval(1))
    #expect(copy.url != note.url)
    #expect(store.list().map(\.text) == ["# Plan\nmore", "# Plan\nmore"])
  }

  /// Delete All Notes moves every note, and nothing else in the folder, to the Trash (here a
  /// stand-in, so the test leaves the real Trash alone).
  @Test func trashesEveryNote() throws {
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = try store.save("a", over: store.newNote(at: .now))
    let b = try store.save("b", over: store.newNote(at: .now.addingTimeInterval(1)))
    let other = folder.appending(path: "keep.txt")
    try Data("x".utf8).write(to: other)
    let bin = folder.appending(path: ".bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let (moved, error) = store.trashAll { url in
      let to = bin.appending(path: url.lastPathComponent)
      try FileManager.default.moveItem(at: url, to: to)
      return to
    }
    #expect(error == nil)
    #expect(Set(moved.map(\.url)) == [a.url, b.url])
    #expect(moved.allSatisfy { $0.trashed != nil })
    #expect(store.list().isEmpty)
    #expect(FileManager.default.fileExists(atPath: other.path))
  }

  /// A note that won't move stops Delete All there; those moved before it are still listed.
  @Test func reportsWhatMovedBeforeAFailure() throws {
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try store.save("a", over: store.newNote(at: .now))
    _ = try store.save("b", over: store.newNote(at: .now.addingTimeInterval(1)))
    var calls = 0
    let (moved, error) = store.trashAll { url in
      calls += 1
      guard calls == 1 else { throw CocoaError(.fileWriteNoPermission) }
      return url
    }
    #expect(moved.count == 1)
    #expect(error != nil)
  }

  @Test func neverWritesOverAFileChangedOutside() throws {
    let saved = try store.save("mine", over: store.newNote())
    try "theirs".write(to: saved.url, atomically: true, encoding: .utf8)
    #expect(throws: NoteStore.SaveError.changedOutside) {
      try store.save("mine, edited", over: saved)
    }
    #expect(try String(contentsOf: saved.url, encoding: .utf8) == "theirs")
    // The same text writes nothing, so it can't fail or touch the file.
    #expect(try store.save("mine", over: saved) == saved)
  }

  @Test func neverCreatesOverAnExistingFile() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let new = store.newNote(at: date)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "already here".write(to: new.url, atomically: true, encoding: .utf8)
    #expect(throws: NoteStore.SaveError.exists) { try store.save("new", over: new) }
    #expect(try String(contentsOf: new.url, encoding: .utf8) == "already here")
    // A name picked at the same second steps past the taken one.
    #expect(store.newNote(at: date).url.lastPathComponent.hasSuffix(" 2.md"))
  }

  @Test func listsUTF8MarkdownOnlyNewestFirst() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let old = folder.appending(path: "old.md")
    try "Old".write(to: old, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: old.path)
    try "New".write(to: folder.appending(path: "new.md"), atomically: true, encoding: .utf8)
    try Data([0xFF, 0xFE, 0x00]).write(to: folder.appending(path: "binary.md"))
    try "x".write(to: folder.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
    #expect(store.list().map(\.title) == ["New", "Old"])
  }

  @Test func searchesTitleAndText() throws {
    let notes = [
      Note(
        url: folder.appending(path: "a.md"), text: "# Trip\nbook the train", modified: .now,
        isSaved: true),
      Note(
        url: folder.appending(path: "b.md"), text: "Groceries\nmilk", modified: .now, isSaved: true),
    ]
    #expect(
      Search.noteSections(for: "", notes: notes).first?.results.map(\.title) == [
        "Trip", "Groceries",
      ])
    let found = Search.noteSections(for: "train", notes: notes).first?.results
    #expect(found?.map(\.title) == ["Trip"])
    #expect(found?.first?.subtitle == "book the train")
    #expect(Search.noteSections(for: "nothing", notes: notes).isEmpty)
  }

  @Test func restoresANoteToWhereItWas() throws {
    // Undo's move back, from a stand-in for the Trash so the test leaves the real one alone.
    let saved = try store.save("# Kept", over: store.newNote())
    let away = folder.appending(path: "away.md")
    try FileManager.default.moveItem(at: saved.url, to: away)
    let back = try store.restore(away, to: saved.url)
    #expect(back?.title == "Kept")
    #expect(!FileManager.default.fileExists(atPath: away.path))
  }

  /// Escape Key Loses Focus is off unless set, as Raycast's is.
  @Test func readsNotesSettings() throws {
    let empty = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"cmd+space"}"#.utf8))
    #expect(!empty.notes.escapeLosesFocus)
    #expect(!empty.notes.moveCheckedTasksToBottom)
    let set = try JSONDecoder().decode(
      Config.self, from: Data(#"{"hotkey":"cmd+space","notes":{"escapeLosesFocus":true}}"#.utf8))
    #expect(set.notes.escapeLosesFocus)
  }

  /// Zoom steps 5% between 75% and 200%, as Raycast Notes' does, and lands back on 100%.
  @Test func stepsTheZoom() {
    #expect(NotesZoom.stepped(1, by: 2) == 1.1)
    #expect(NotesZoom.stepped(1.1, by: -2) == 1)
    #expect(NotesZoom.stepped(1.95, by: 3) == 2)
    #expect(NotesZoom.stepped(0.8, by: -3) == 0.75)
    // An older build's ×1.1 step.
    #expect(NotesZoom.stepped(1.21, by: 0) == 1.2)
  }
}
