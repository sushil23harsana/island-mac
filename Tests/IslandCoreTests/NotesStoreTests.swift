import XCTest
@testable import IslandCore

@MainActor
final class NotesStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IslandTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testCreateWritesMarkdownFile() throws {
        let store = NotesStore(folder: folder)
        let note = try XCTUnwrap(store.create(body: "# Groceries\nmilk"))
        XCTAssertEqual(note.id.pathExtension, "md")
        XCTAssertEqual(try String(contentsOf: note.id, encoding: .utf8), "# Groceries\nmilk")
        XCTAssertEqual(store.notes.count, 1)
    }

    func testTitleAndPreviewStripMarkdown() {
        let note = Note(id: URL(fileURLWithPath: "/x.md"), body: "\n## Lecture 4  \n- [ ] read ch. 3\n", modified: .now)
        XCTAssertEqual(note.title, "Lecture 4")
        XCTAssertEqual(note.preview, "read ch. 3")
        XCTAssertEqual(Note(id: URL(fileURLWithPath: "/y.md"), body: "  \n", modified: .now).title, "Untitled")
    }

    func testSaveMovesNoteToTopAndPersists() throws {
        let store = NotesStore(folder: folder)
        let a = try XCTUnwrap(store.create(body: "a"))
        _ = store.create(body: "b")
        store.save(a.id, body: "a edited")
        XCTAssertEqual(store.notes.first?.id, a.id)

        let reloaded = NotesStore(folder: folder)
        XCTAssertTrue(reloaded.notes.contains { $0.body == "a edited" })
    }

    func testCreateTwiceInSameSecondGetsUniqueFiles() {
        let store = NotesStore(folder: folder)
        let a = store.create(body: "1")
        let b = store.create(body: "2")
        XCTAssertNotEqual(a?.id, b?.id)
    }

    func testSearchIsCaseInsensitive() {
        let store = NotesStore(folder: folder)
        store.create(body: "Physics formulas")
        store.create(body: "Shopping list")
        XCTAssertEqual(store.search("PHYSICS").count, 1)
        XCTAssertEqual(store.search("  ").count, 2)
    }

    func testRemoveBlankNotes() {
        let store = NotesStore(folder: folder)
        let blank = store.create(body: "   ")
        store.create(body: "keep")
        store.removeBlankNotes()
        XCTAssertEqual(store.notes.map(\.body), ["keep"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: blank!.id.path))
    }

    func testIgnoresNonMarkdownFiles() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
        try "hello".write(to: folder.appendingPathComponent("hand-made.md"), atomically: true, encoding: .utf8)
        let store = NotesStore(folder: folder)
        XCTAssertEqual(store.notes.map(\.body), ["hello"])
    }
}
