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
}
