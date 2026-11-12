import EventKit
import Foundation

/// Finds the next event in the Mac's calendars (iCloud, Google, Exchange… whatever is set up
/// in the Calendar app). Needs calendar permission, which is only asked for when the user clicks.
@MainActor
final class CalendarMonitor: ObservableObject {
    enum Access { case notAsked, granted, denied }

    struct UpcomingEvent: Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var joinURL: URL?

        var isHappeningNow: Bool { start <= Date() }
    }

    @Published private(set) var access: Access = .notAsked
    @Published private(set) var next: UpcomingEvent?

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        updateAccess()
        refresh()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor in
                self?.updateAccess()
                self?.refresh()
            }
        }
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .notAsked
        default: access = .denied
        }
    }

    func refresh() {
        guard access == .granted else {
            next = nil
            return
        }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .min { $0.startDate < $1.startDate }
        next = event.map {
            UpcomingEvent(id: $0.eventIdentifier ?? UUID().uuidString,
                          title: $0.title ?? "Event",
                          start: $0.startDate,
                          end: $0.endDate,
                          joinURL: Self.joinURL(for: $0))
        }
    }

    /// A video-call link from the event's URL, location or notes.
    private static func joinURL(for event: EKEvent) -> URL? {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com"]
        func isCall(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if let url = event.url, isCall(url) { return url }

        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
            .first(where: isCall)
    }

    #if DEBUG
    func setForSnapshot(_ event: UpcomingEvent?) {
        access = .granted
        next = event
    }
    #endif
}
