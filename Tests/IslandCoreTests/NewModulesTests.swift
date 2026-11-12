import XCTest
@testable import IslandCore

final class ReminderParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func delay(_ text: String) -> TimeInterval? {
        ReminderParser.parse(text, now: now)?.fireDate.timeIntervalSince(now)
    }

    func testRelativePhrases() {
        XCTAssertEqual(delay("remind me in 20 min to call mom"), 20 * 60)
        XCTAssertEqual(ReminderParser.parse("remind me in 20 min to call mom", now: now)?.title, "Call mom")
        XCTAssertEqual(ReminderParser.parse("Remind me to submit the lab in 2 hours", now: now)?.title, "Submit the lab")
        XCTAssertEqual(delay("Remind me to submit the lab in 2 hours"), 7200)
        XCTAssertEqual(delay("in 90s"), 90)
        XCTAssertEqual(delay("in 1.5h stretch"), 5400)
        XCTAssertEqual(delay("in 2 days renew pass"), 2 * 86_400)
        XCTAssertEqual(ReminderParser.parse("in 5m", now: now)?.title, "Reminder")
    }

    func testTimerPhrases() {
        XCTAssertEqual(delay("timer 10 min tea"), 600)
        XCTAssertEqual(ReminderParser.parse("timer 10 min tea", now: now)?.title, "Tea")
        XCTAssertEqual(ReminderParser.parse("Timer 45s", now: now)?.title, "Timer")
    }

    func testAbsoluteTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // `now` is 2027-01-15 08:00 UTC.
        let fivePM = try XCTUnwrap(ReminderParser.parse("remind me at 5:30pm to leave", now: now, calendar: calendar))
        XCTAssertEqual(fivePM.title, "Leave")
        XCTAssertEqual(calendar.dateComponents([.day, .hour, .minute], from: fivePM.fireDate),
                       DateComponents(day: 15, hour: 17, minute: 30))
        // A time that already passed today means tomorrow.
        let seven = try XCTUnwrap(ReminderParser.parse("remind me at 7 to wake up", now: now, calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: seven.fireDate), 16)
    }

    func testOrdinaryNotesAreNotReminders() {
        XCTAssertNil(ReminderParser.parse("buy milk", now: now))
        XCTAssertNil(ReminderParser.parse("meeting notes: ship in 2 weeks", now: now))
        XCTAssertNil(ReminderParser.parse("interesting idea in 3d printing", now: now))
        XCTAssertNil(ReminderParser.parse("in 0 min", now: now))
        XCTAssertNil(ReminderParser.parse("remind me at 25:00", now: now))
        XCTAssertNil(ReminderParser.parse("line one\nin 5 min", now: now))
    }

    func testShortDurationText() {
        XCTAssertEqual(TimeInterval(42).shortDurationText, "42s")
        XCTAssertEqual(TimeInterval(61).shortDurationText, "2m")
        XCTAssertEqual(TimeInterval(3900).shortDurationText, "1h 05m")
        XCTAssertEqual(TimeInterval(-5).shortDurationText, "0s")
    }
}

@MainActor
final class StoresTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IslandStores-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testRemindersFireOnceAndPersist() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = ReminderStore(directory: folder, now: { clock })
        store.add(Reminder(title: "Tea", fireDate: clock.addingTimeInterval(60)))
        store.add(Reminder(title: "Later", fireDate: clock.addingTimeInterval(600)))
        XCTAssertTrue(store.tick().isEmpty)

        clock.addTimeInterval(61)
        XCTAssertEqual(store.tick().map(\.title), ["Tea"])
        XCTAssertTrue(store.tick().isEmpty, "a reminder must only fire once")
        XCTAssertEqual(store.upcoming.map(\.title), ["Later"])
        XCTAssertEqual(store.fired.map(\.title), ["Tea"])

        let reopened = ReminderStore(directory: folder, now: { clock })
        XCTAssertEqual(reopened.items.count, 2)
        reopened.clearFired()
        XCTAssertEqual(reopened.items.map(\.title), ["Later"])
    }

    func testShelfAddsExistingFilesOnceAndForgetsDeletedOnes() throws {
        let a = folder.appendingPathComponent("a.txt")
        let b = folder.appendingPathComponent("b.txt")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "b".write(to: b, atomically: true, encoding: .utf8)

        let shelf = ShelfStore(directory: folder)
        XCTAssertEqual(shelf.add([a, b, a, folder.appendingPathComponent("missing.txt")]), 2)
        XCTAssertEqual(shelf.add([a]), 0)
        XCTAssertEqual(shelf.items.map(\.name), ["a.txt", "b.txt"])

        try FileManager.default.removeItem(at: a)
        XCTAssertEqual(ShelfStore(directory: folder).items.map(\.name), ["b.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path), "the shelf never touches the files")
    }
}

final class PortScannerTests: XCTestCase {
    func testParsesLsofOutput() {
        let output = """
        p412
        cControlCenter
        f9
        n*:7000
        f10
        n*:7000
        p9321
        cnode
        f23
        n127.0.0.1:3000
        p9400
        cGoogle\\x20Chrome\\x20H
        f40
        n[::1]:9222
        p77
        cpostgres
        f7
        n[::1]:5432
        f8
        n127.0.0.1:5432
        """
        let ports = PortScanner.parse(output)
        XCTAssertEqual(ports.map(\.port), [3000, 5432, 7000, 9222])
        XCTAssertEqual(ports[0].command, "node")
        XCTAssertEqual(ports[0].pid, 9321)
        XCTAssertTrue(ports[0].isLocalOnly)
        XCTAssertEqual(ports[0].hint, "Node / React / Rails")
        XCTAssertFalse(ports[2].isLocalOnly)
        XCTAssertEqual(ports[3].command, "Google Chrome H")
        XCTAssertTrue(PortScanner.parse("").isEmpty)
    }
}

final class NowPlayingTests: XCTestCase {
    func testReadsPlayerNotifications() {
        let playing = NowPlayingInfo(userInfo: ["Name": "Song", "Artist": "Band", "Album": "LP",
                                                "Player State": "Playing"], source: .spotify)
        XCTAssertEqual(playing, NowPlayingInfo(source: .spotify, title: "Song", artist: "Band",
                                               album: "LP", isPlaying: true))
        XCTAssertEqual(NowPlayingInfo(userInfo: ["Name": "Song", "Player State": "Paused"],
                                      source: .music)?.isPlaying, false)
        XCTAssertNil(NowPlayingInfo(userInfo: ["Name": "Song", "Player State": "Stopped"], source: .music))
        XCTAssertNil(NowPlayingInfo(userInfo: ["Player State": "Playing"], source: .music))
        XCTAssertNil(NowPlayingInfo(userInfo: nil, source: .music))
    }
}
