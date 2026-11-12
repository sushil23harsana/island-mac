import XCTest
@testable import IslandCore

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private var folder: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeHistory(limit: Int = 200) -> ClipboardHistory {
        ClipboardHistory(directory: folder, limit: limit, now: { [unowned self] in
            self.clock.addTimeInterval(1) // every event is one second later
            return self.clock
        })
    }

    func testAddsNewestFirstAndIgnoresBlankText() {
        let h = makeHistory()
        h.addText("first")
        h.addText("second", sourceApp: "Safari")
        h.addText("   \n ")
        XCTAssertEqual(h.items.map(\.text), ["second", "first"])
        XCTAssertEqual(h.items.first?.sourceApp, "Safari")
    }

    func testCopyingSameTextAgainMovesItToTop() {
        let h = makeHistory()
        h.addText("a")
        h.addText("b")
        h.addText("a")
        XCTAssertEqual(h.items.map(\.text), ["a", "b"])
    }

    func testLimitTrimsOldestButKeepsPinned() {
        let h = makeHistory(limit: 2)
        h.addText("old pinned")
        h.togglePin(h.items[0].id)
        h.addText("1")
        h.addText("2")
        h.addText("3")
        XCTAssertEqual(Set(h.items.map(\.text)), ["old pinned", "2", "3"])
    }

    func testLoweringLimitTrimsExistingHistory() {
        let h = makeHistory(limit: 10)
        for i in 1...5 { h.addText("item \(i)") }
        h.limit = 2
        XCTAssertEqual(h.items.map(\.text), ["item 5", "item 4"])
        XCTAssertEqual(makeHistory().items.count, 2)
    }

    func testSearchPutsPinnedFirst() {
        let h = makeHistory()
        h.addText("git push origin main")
        h.addText("npm run dev")
        h.addText("git status")
        h.togglePin(h.items.first { $0.text == "git push origin main" }!.id)
        XCTAssertEqual(h.search("git").map(\.text), ["git push origin main", "git status"])
        XCTAssertEqual(h.search("").first?.text, "git push origin main")
    }

    func testClearKeepsPinned() {
        let h = makeHistory()
        h.addText("keep")
        h.togglePin(h.items[0].id)
        h.addText("drop")
        h.clearUnpinned()
        XCTAssertEqual(h.items.map(\.text), ["keep"])
    }

    func testPersistsAcrossLaunches() {
        let h = makeHistory()
        h.addText("hello")
        h.addFiles(["/Users/me/a.pdf", "/Users/me/b.pdf"])
        h.togglePin(h.items[0].id)
        let reopened = makeHistory()
        XCTAssertEqual(reopened.items.count, 2)
        XCTAssertEqual(reopened.items.first?.title, "a.pdf + 1 more")
        XCTAssertTrue(reopened.items.first?.pinned ?? false)
    }

    func testImagesAreStoredDedupedAndDeleted() throws {
        let h = makeHistory()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        h.addImage(png: png, width: 640, height: 480)
        h.addText("between")
        h.addImage(png: png, width: 640, height: 480)
        XCTAssertEqual(h.items.count, 2)
        let image = try XCTUnwrap(h.items.first)
        XCTAssertEqual(image.title, "Image 640×480")
        let url = try XCTUnwrap(h.imageURL(for: image))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        h.delete(image.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testTrimmedImagesRemoveTheirFiles() throws {
        let h = makeHistory(limit: 1)
        h.addImage(png: Data([1, 2, 3]), width: 1, height: 1)
        let url = try XCTUnwrap(h.imageURL(for: h.items[0]))
        h.addText("newer")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDetectsLinksAndColors() {
        func item(_ text: String) -> ClipItem {
            ClipItem(id: UUID(), kind: .text, text: text, date: .now, pinned: false)
        }
        XCTAssertTrue(item("https://github.com/apple/swift").isLink)
        XCTAssertFalse(item("see https://x.com later").isLink)
        XCTAssertFalse(item("ftp://files").isLink)
        XCTAssertNotNil(item("#FF8800").hexColor)
        XCTAssertNotNil(item("#f80").hexColor)
        XCTAssertNil(item("#hello").hexColor)
        XCTAssertEqual(item("\n\n  first line  \nsecond").title, "first line")
    }
}
