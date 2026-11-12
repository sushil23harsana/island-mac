import Foundation

public struct Reminder: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var fireDate: Date
    /// True once it has gone off; it then stays in the list until dismissed.
    public var fired: Bool

    public init(id: UUID = UUID(), title: String, fireDate: Date, fired: Bool = false) {
        self.id = id
        self.title = title
        self.fireDate = fireDate
        self.fired = fired
    }
}

/// Turns quick phrases into reminders:
/// "remind me in 20 min to call mom", "in 2h stretch", "timer 10 min tea", "remind me at 5:30pm to leave".
public enum ReminderParser {
    private static let unit = "(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d)"

    private static let relative = try! NSRegularExpression(
        pattern: "^(?:remind(?:er)?(?:\\s+me)?\\s+|timer\\s+)?(?:to\\s+(.+?)\\s+)?in\\s+(\\d+(?:\\.\\d+)?)\\s*\(unit)(?:\\s+(?:to\\s+)?(.+))?$",
        options: [.caseInsensitive])
    private static let timerOnly = try! NSRegularExpression(
        pattern: "^timer\\s+(\\d+(?:\\.\\d+)?)\\s*\(unit)(?:\\s+(.+))?$",
        options: [.caseInsensitive])
    private static let absolute = try! NSRegularExpression(
        pattern: "^remind(?:er)?(?:\\s+me)?\\s+(?:to\\s+(.+?)\\s+)?at\\s+(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?(?:\\s+(?:to\\s+)?(.+))?$",
        options: [.caseInsensitive])

    /// Longest delay accepted for "in …" reminders.
    public static let maxDelay: TimeInterval = 30 * 86_400

    public static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> Reminder? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("\n") else { return nil }

        if let g = groups(relative, text), let amount = Double(g[2] ?? ""), let seconds = seconds(amount, g[3]) {
            return make(title: g[1] ?? g[4], after: seconds, now: now, fallback: "Reminder")
        }
        if let g = groups(timerOnly, text), let amount = Double(g[1] ?? ""), let seconds = seconds(amount, g[2]) {
            return make(title: g[3], after: seconds, now: now, fallback: "Timer")
        }
        if let g = groups(absolute, text), var hour = Int(g[2] ?? "") {
            let minute = Int(g[3] ?? "0") ?? 0
            let meridiem = g[4]?.lowercased()
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
            guard (0...23).contains(hour), (0...59).contains(minute),
                  var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
            if date <= now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
            return Reminder(title: clean(g[1] ?? g[5]) ?? "Reminder", fireDate: date)
        }
        return nil
    }

    private static func make(title: String?, after seconds: TimeInterval, now: Date, fallback: String) -> Reminder? {
        guard seconds > 0, seconds <= maxDelay else { return nil }
        return Reminder(title: clean(title) ?? fallback, fireDate: now.addingTimeInterval(seconds))
    }

    private static func clean(_ title: String?) -> String? {
        guard let t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private static func seconds(_ amount: Double, _ unit: String?) -> TimeInterval? {
        guard let first = unit?.lowercased().first else { return nil }
        switch first {
        case "s": return amount
        case "m": return amount * 60
        case "h": return amount * 3600
        case "d": return amount * 86_400
        default: return nil
        }
    }

    /// Capture groups of the first match (index 0 is the whole match), nil where a group didn't take part.
    private static func groups(_ regex: NSRegularExpression, _ text: String) -> [String?]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) }
        }
    }
}

/// Reminders saved on this Mac. Call `tick()` regularly; it reports the ones that just came due.
@MainActor
public final class ReminderStore: ObservableObject {
    @Published public private(set) var items: [Reminder] = []

    private let file: URL
    private let now: () -> Date

    public init(directory: URL, now: @escaping () -> Date = Date.init) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("reminders.json")
        self.now = now
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Reminder].self, from: data) {
            items = saved
        }
    }

    /// Not yet fired, soonest first.
    public var upcoming: [Reminder] {
        items.filter { !$0.fired }.sorted { $0.fireDate < $1.fireDate }
    }

    public var fired: [Reminder] { items.filter(\.fired) }

    public func add(_ reminder: Reminder) {
        items.append(reminder)
        save()
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func clearFired() {
        items.removeAll(where: \.fired)
        save()
    }

    /// Marks due reminders as fired and returns them (each reminder is returned once).
    @discardableResult
    public func tick() -> [Reminder] {
        let current = now()
        var due: [Reminder] = []
        for i in items.indices where !items[i].fired && items[i].fireDate <= current {
            items[i].fired = true
            due.append(items[i])
        }
        if !due.isEmpty { save() }
        return due
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

public extension TimeInterval {
    /// Compact "time left" text: "45s", "12m", "1h 05m", "2d 3h".
    var shortDurationText: String {
        let total = max(Int(self.rounded(.up)), 0)
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(Int((Double(total) / 60).rounded(.up)))m" }
        if total < 86_400 { return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60) }
        return "\(total / 86_400)d \((total % 86_400) / 3600)h"
    }
}
