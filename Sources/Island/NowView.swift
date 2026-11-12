import IslandCore
import SwiftUI

/// Now tab: what's playing, what's next in the calendar, reminders and a few quick switches.
struct NowView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var nowPlaying: NowPlayingMonitor
    @EnvironmentObject private var calendar: CalendarMonitor
    @EnvironmentObject private var reminders: ReminderStore
    @EnvironmentObject private var power: PowerMonitor
    @EnvironmentObject private var keepAwake: KeepAwake

    @FocusState private var reminderFocused: Bool
    @State private var reminderText = ""
    @State private var reminderHint = false

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    musicCard
                    eventCard
                    quickCard
                }
                remindersCard
            }
        }
        .scrollIndicators(.never)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onReceive(controller.commands) { command in
            if case .focusCapture = command { focusReminderSoon() }
        }
        .onAppear(perform: focusReminderSoon)
    }

    // MARK: Music

    private var musicCard: some View {
        NowCard(title: "Now playing", symbol: "music.note") {
            if let info = nowPlaying.info {
                HStack(spacing: 10) {
                    EqualizerBars(active: info.isPlaying)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.now.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                        Text([info.artist, info.source.rawValue].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 14) {
                    Spacer()
                    mediaButton("backward.fill", help: "Previous") { nowPlaying.send(.previous) }
                    mediaButton(info.isPlaying ? "pause.fill" : "play.fill", size: 15, filled: true,
                                help: info.isPlaying ? "Pause" : "Play") { nowPlaying.send(.playPause) }
                    mediaButton("forward.fill", help: "Next") { nowPlaying.send(.next) }
                    Spacer()
                }
            } else {
                Text("Play something in Music or Spotify and it shows up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func mediaButton(_ symbol: String, size: CGFloat = 12, filled: Bool = false, help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(filled ? .black : .white.opacity(0.85))
                .frame(width: filled ? 36 : 30, height: filled ? 36 : 30)
                .background(Circle().fill(filled ? AnyShapeStyle(Theme.now.gradient) : AnyShapeStyle(.white.opacity(0.1))))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Calendar

    private var eventCard: some View {
        NowCard(title: "Up next", symbol: "calendar") {
            switch calendar.access {
            case .notAsked:
                HStack {
                    Text("Show your next meeting here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    LinkButton("Allow calendar") { calendar.requestAccess() }
                }
            case .denied:
                Text("Calendar access is off. Turn it on in System Settings → Privacy & Security → Calendars.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            case .granted:
                if let event = calendar.next {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(Self.timing(of: event, at: context.date))
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        Spacer(minLength: 0)
                        if let url = event.joinURL {
                            Button { NSWorkspace.shared.open(url) } label: {
                                Label("Join", systemImage: "video.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 11)
                                    .frame(height: 26)
                                    .background(Capsule().fill(Theme.rest))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Nothing in the next 24 hours.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    static func timing(of event: CalendarMonitor.UpcomingEvent, at date: Date) -> String {
        let range = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        let left = event.start.timeIntervalSince(date)
        return left <= 0 ? "\(range) · happening now" : "\(range) · in \(left.shortDurationText)"
    }

    // MARK: Reminders

    private var remindersCard: some View {
        NowCard(title: "Reminders", symbol: "bell") {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.now)
                TextField("in 20 min call mom", text: $reminderText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($reminderFocused)
                    .onSubmit(addReminder)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .field(radius: 10)

            Text(reminderHint ? "Try: “in 20 min call mom”, “timer 10 min”, or “remind me at 5pm to leave”"
                 : "Also works from the Notes capture bar")
                .font(.system(size: 10.5))
                .foregroundStyle(reminderHint ? Theme.now : .white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(reminders.fired) { reminder in
                reminderRow(reminder, done: true)
            }
            ForEach(reminders.upcoming) { reminder in
                reminderRow(reminder, done: false)
            }
            if reminders.items.isEmpty {
                Text("No reminders")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private func reminderRow(_ reminder: Reminder, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "bell.fill" : "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(done ? Theme.now : .white.opacity(0.5))
                .frame(width: 18)
            Text(reminder.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            if done {
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.now)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(reminder.fireDate.timeIntervalSince(context.date).shortDurationText)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Button { reminders.remove(reminder.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(done ? "Dismiss" : "Cancel reminder")
        }
        .padding(.vertical, 2)
    }

    private func addReminder() {
        let text = reminderText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        // "20 min call mom" without the leading "in" is close enough.
        if controller.addReminder(from: text) || controller.addReminder(from: "in " + text) {
            reminderText = ""
            reminderHint = false
        } else {
            reminderHint = true
        }
    }

    // MARK: Quick switches

    private var quickCard: some View {
        NowCard(title: "Quick", symbol: "bolt") {
            HStack(spacing: 8) {
                quickTile(symbol: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                          title: "Keep awake", detail: keepAwake.isOn ? "On" : "Off",
                          active: keepAwake.isOn, tint: Theme.focus) { keepAwake.toggle() }
                quickTile(symbol: "text.viewfinder", title: "Grab text", detail: "⌃⌥T",
                          active: false, tint: Theme.rest) { controller.grabText() }
            }
            if let percent = power.percent {
                Label("Battery \(percent)%\(power.onACPower ? " · plugged in" : "")",
                      systemImage: power.onACPower ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func quickTile(symbol: String, title: String, detail: String, active: Bool, tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? .black : tint)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.16))))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(active ? tint : .white.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func focusReminderSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { reminderFocused = true }
    }
}

// MARK: - Pieces

private struct NowCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }
}

/// Little bouncing bars, like a music visualizer. Still when paused.
struct EqualizerBars: View {
    let active: Bool
    var tint: Color = Theme.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = active ? (sin(t * (5.0 + Double(i) * 1.7) + Double(i)) + 1) / 2 : 0.25
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5, height: 3 + 9 * wave)
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }
}
