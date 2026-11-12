import XCTest
@testable import IslandCore

@MainActor
final class FocusTimerTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "FocusTimerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeTimer() -> FocusTimer {
        FocusTimer(now: { [unowned self] in self.clock }, defaults: defaults)
    }

    private func advance(_ seconds: TimeInterval, _ timer: FocusTimer) {
        clock.addTimeInterval(seconds)
        timer.tick()
    }

    func testStartsIdleWithClassicPreset() {
        let t = makeTimer()
        XCTAssertEqual(t.state, .idle)
        XCTAssertEqual(t.phase, .focus)
        XCTAssertEqual(t.remaining, 25 * 60)
        XCTAssertFalse(t.isActive)
    }

    func testCountsDownAndPauses() {
        let t = makeTimer()
        t.start()
        advance(60, t)
        XCTAssertEqual(t.remaining, 24 * 60)
        t.pause()
        advance(600, t) // paused time doesn't count
        XCTAssertEqual(t.remaining, 24 * 60)
        t.start()
        advance(30, t)
        XCTAssertEqual(t.remaining, 23 * 60 + 30)
    }

    func testFocusEndingStartsBreakAndCountsSession() {
        let t = makeTimer()
        var finished: [FocusPhase] = []
        t.onPhaseFinished = { finished.append($0) }
        t.start()
        advance(25 * 60, t)
        XCTAssertEqual(t.phase, .rest)
        XCTAssertTrue(t.isRunning)
        XCTAssertEqual(t.remaining, 5 * 60)
        XCTAssertEqual(t.todaySessions, 1)
        XCTAssertEqual(t.todayFocusSeconds, 25 * 60)
        XCTAssertEqual(finished, [.focus])

        advance(5 * 60, t)
        XCTAssertEqual(t.phase, .focus)
        XCTAssertEqual(t.state, .idle)
        XCTAssertEqual(finished, [.focus, .rest])
    }

    func testSleepingThroughTheEndStillFinishes() {
        let t = makeTimer()
        t.start()
        advance(3 * 3600, t) // Mac was asleep for hours
        XCTAssertEqual(t.todaySessions, 1)
        XCTAssertEqual(t.phase, .rest)
    }

    func testSkipDoesNotCountSession() {
        let t = makeTimer()
        t.start()
        advance(60, t)
        t.skip()
        XCTAssertEqual(t.phase, .rest)
        XCTAssertEqual(t.todaySessions, 0)
        t.skip()
        XCTAssertEqual(t.phase, .focus)
        XCTAssertEqual(t.state, .idle)
    }

    func testChangingPresetWhileIdleUpdatesRemainingAndPersists() {
        let t = makeTimer()
        t.preset = FocusPreset(focusMinutes: 50, restMinutes: 10)
        XCTAssertEqual(t.remaining, 50 * 60)
        XCTAssertEqual(makeTimer().preset.id, "50/10")
    }

    func testCustomLengthIsUsedClampedAndRemembered() {
        let t = makeTimer()
        XCTAssertFalse(t.isCustom)
        t.setCustom(focusMinutes: 40, restMinutes: 8)
        XCTAssertTrue(t.isCustom)
        XCTAssertEqual(t.remaining, 40 * 60)

        t.start()
        advance(40 * 60, t)
        XCTAssertEqual(t.phase, .rest)
        XCTAssertEqual(t.remaining, 8 * 60)
        XCTAssertEqual(t.todayFocusSeconds, 40 * 60)

        let reopened = makeTimer()
        XCTAssertTrue(reopened.isCustom)
        XCTAssertEqual(reopened.preset.id, "40/8")

        reopened.setCustom(focusMinutes: 999, restMinutes: 0)
        XCTAssertEqual(reopened.customPreset.id, "180/1")
    }

    func testCustomLengthIsKeptWhileBuiltInPresetIsSelected() {
        let t = makeTimer()
        t.setCustom(focusMinutes: 33, restMinutes: 7)
        t.preset = FocusPreset.all[0]
        let reopened = makeTimer()
        XCTAssertFalse(reopened.isCustom)
        XCTAssertEqual(reopened.customPreset.id, "33/7")
    }

    func testChangingCustomWhileRunningDoesNotDisturbTheTimer() {
        let t = makeTimer()
        t.start()
        advance(60, t)
        t.setCustom(focusMinutes: 90, restMinutes: 15)
        XCTAssertEqual(t.remaining, 24 * 60)
        XCTAssertEqual(t.preset.id, "25/5")
    }

    func testStatsPersistForTodayButResetNextDay() {
        let t = makeTimer()
        t.start()
        advance(25 * 60, t)
        XCTAssertEqual(makeTimer().todaySessions, 1)

        clock.addTimeInterval(86_400)
        XCTAssertEqual(makeTimer().todaySessions, 0)
    }

    func testProgressAndCountdownText() {
        let t = makeTimer()
        XCTAssertEqual(t.progress, 0)
        t.start()
        advance(12.5 * 60, t)
        XCTAssertEqual(t.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(TimeInterval(754.2).countdownText, "12:35")
        XCTAssertEqual(TimeInterval(0).countdownText, "0:00")
    }
}
