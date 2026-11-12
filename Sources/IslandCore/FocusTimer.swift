import Foundation

public enum FocusPhase: String, Codable, Sendable {
    case focus
    case rest
}

public struct FocusPreset: Equatable, Hashable, Identifiable, Sendable {
    public let focus: TimeInterval
    public let rest: TimeInterval
    public var id: String { "\(Int(focus / 60))/\(Int(rest / 60))" }

    public init(focusMinutes: Int, restMinutes: Int) {
        focus = TimeInterval(focusMinutes * 60)
        rest = TimeInterval(restMinutes * 60)
    }

    /// Parses an id like "45/10". Returns nil if it isn't two sensible numbers.
    public init?(id: String) {
        let parts = id.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 2,
              FocusPreset.focusRange.contains(parts[0]),
              FocusPreset.restRange.contains(parts[1]) else { return nil }
        self.init(focusMinutes: parts[0], restMinutes: parts[1])
    }

    public var focusMinutes: Int { Int(focus / 60) }
    public var restMinutes: Int { Int(rest / 60) }

    /// Allowed lengths for a custom session.
    public static let focusRange = 1...180
    public static let restRange = 1...60

    public static let all: [FocusPreset] = [
        FocusPreset(focusMinutes: 25, restMinutes: 5),   // classic Pomodoro
        FocusPreset(focusMinutes: 50, restMinutes: 10),  // long study block
        FocusPreset(focusMinutes: 15, restMinutes: 3),   // quick sprint
    ]
}

/// A Pomodoro-style timer: focus → break → ready for the next focus block.
///
/// Time is measured against an end date, not by counting ticks, so the timer stays
/// correct even if the Mac sleeps or the UI stops refreshing for a while.
@MainActor
public final class FocusTimer: ObservableObject {
    public enum State: Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    @Published public private(set) var phase: FocusPhase = .focus
    @Published public private(set) var state: State = .idle
    @Published public private(set) var remaining: TimeInterval
    @Published public private(set) var todaySessions = 0
    @Published public private(set) var todayFocusSeconds: TimeInterval = 0
    @Published public var preset: FocusPreset {
        didSet {
            defaults.set(preset.id, forKey: Keys.preset)
            if state == .idle { remaining = duration(of: phase) }
        }
    }

    /// The user's own focus/break length, remembered even while a built-in preset is selected.
    @Published public private(set) var customPreset: FocusPreset

    /// True when the custom length (not one of the built-in presets) is selected.
    public var isCustom: Bool { !FocusPreset.all.contains(preset) }

    /// Changes the custom length (clamped to the allowed ranges) and selects it when idle.
    public func setCustom(focusMinutes: Int, restMinutes: Int) {
        let f = min(max(focusMinutes, FocusPreset.focusRange.lowerBound), FocusPreset.focusRange.upperBound)
        let r = min(max(restMinutes, FocusPreset.restRange.lowerBound), FocusPreset.restRange.upperBound)
        customPreset = FocusPreset(focusMinutes: f, restMinutes: r)
        defaults.set(customPreset.id, forKey: Keys.custom)
        if state == .idle && phase == .focus { preset = customPreset }
    }

    /// Called when a phase runs out (not when it is skipped or reset).
    public var onPhaseFinished: ((FocusPhase) -> Void)?

    private let now: () -> Date
    private let defaults: UserDefaults
    private let calendar = Calendar.current

    private enum Keys {
        static let preset = "focus.preset"
        static let custom = "focus.custom"
        static let day = "focus.day"
        static let sessions = "focus.sessions"
        static let seconds = "focus.seconds"
    }

    public init(now: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard) {
        self.now = now
        self.defaults = defaults
        let savedID = defaults.string(forKey: Keys.preset)
        let custom = defaults.string(forKey: Keys.custom).flatMap(FocusPreset.init(id:))
            ?? FocusPreset(focusMinutes: 45, restMinutes: 10)
        let preset = FocusPreset.all.first { $0.id == savedID }
            ?? (savedID == custom.id ? custom : FocusPreset.all[0])
        customPreset = custom
        self.preset = preset
        remaining = preset.focus
        loadTodayStats()
    }

    // MARK: Derived

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    /// True while a block is running or paused (i.e. worth showing in the pill).
    public var isActive: Bool { state != .idle || phase == .rest }

    /// 0 at the start of a phase, 1 when it ends.
    public var progress: Double {
        let total = duration(of: phase)
        guard total > 0 else { return 0 }
        return min(max(1 - remaining / total, 0), 1)
    }

    public func duration(of phase: FocusPhase) -> TimeInterval {
        phase == .focus ? preset.focus : preset.rest
    }

    // MARK: Controls

    public func start() {
        switch state {
        case .idle: state = .running(endsAt: now().addingTimeInterval(remaining))
        case .paused(let left): state = .running(endsAt: now().addingTimeInterval(left))
        case .running: break
        }
    }

    public func pause() {
        guard case .running(let endsAt) = state else { return }
        remaining = max(endsAt.timeIntervalSince(now()), 0)
        state = .paused(remaining: remaining)
    }

    public func toggle() {
        isRunning ? pause() : start()
    }

    /// Back to a fresh focus block, not running.
    public func reset() {
        phase = .focus
        state = .idle
        remaining = preset.focus
    }

    /// Jump to the next phase without counting the current one.
    public func skip() {
        switch phase {
        case .focus: begin(.rest)
        case .rest: reset()
        }
    }

    /// Call about once a second. Updates `remaining` and handles phase changes.
    public func tick() {
        rollOverDayIfNeeded()
        guard case .running(let endsAt) = state else { return }
        let left = endsAt.timeIntervalSince(now())
        if left > 0 {
            remaining = left
            return
        }

        let finished = phase
        if finished == .focus {
            todaySessions += 1
            todayFocusSeconds += preset.focus
            saveTodayStats()
            begin(.rest)          // breaks start automatically
        } else {
            reset()               // wait for the user to start the next block
        }
        onPhaseFinished?(finished)
    }

    private func begin(_ next: FocusPhase) {
        phase = next
        remaining = duration(of: next)
        state = .running(endsAt: now().addingTimeInterval(remaining))
    }

    // MARK: Daily stats

    private var todayKey: String {
        let c = calendar.dateComponents([.year, .month, .day], from: now())
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    private func loadTodayStats() {
        if defaults.string(forKey: Keys.day) == todayKey {
            todaySessions = defaults.integer(forKey: Keys.sessions)
            todayFocusSeconds = defaults.double(forKey: Keys.seconds)
        } else {
            todaySessions = 0
            todayFocusSeconds = 0
        }
    }

    private func saveTodayStats() {
        defaults.set(todayKey, forKey: Keys.day)
        defaults.set(todaySessions, forKey: Keys.sessions)
        defaults.set(todayFocusSeconds, forKey: Keys.seconds)
    }

    private func rollOverDayIfNeeded() {
        if todaySessions > 0, defaults.string(forKey: Keys.day) != todayKey {
            loadTodayStats()
        }
    }
}

public extension TimeInterval {
    /// "24:59" style countdown text (rounds up so it never shows 0:00 while running).
    var countdownText: String {
        let total = Int(self.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
