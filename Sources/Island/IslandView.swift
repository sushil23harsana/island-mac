import IslandCore
import SwiftUI

/// Root view: a black island that morphs between the small pill and the full panel.
struct IslandView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var focus: FocusTimer

    private var expanded: Bool { controller.mode == .expanded }

    private var size: CGSize {
        expanded ? IslandGeometry.expandedSize : controller.geometry.pillSize
    }

    private var shape: IslandShape {
        IslandShape(ear: expanded ? IslandGeometry.expandedEar : IslandGeometry.pillEar,
                    radius: expanded ? 30 : 13)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if expanded {
                ExpandedView()
                    .frame(width: IslandGeometry.expandedSize.width,
                           height: IslandGeometry.expandedSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                        .animation(.easeOut(duration: 0.2).delay(0.05)))
            } else {
                CollapsedView()
                    .frame(width: controller.geometry.pillSize.width,
                           height: controller.geometry.pillSize.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .background(
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(expanded ? 0.55 : 0), radius: 22, y: 10)
        )
        .overlay(
            // Hairline rim that fades in toward the bottom, so the island reads as a solid object.
            shape
                .stroke(LinearGradient(colors: [.clear, .white.opacity(0.16)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .opacity(expanded ? 1 : 0)
        )
        .overlay(
            // Glow when a focus block or break finishes.
            shape
                .stroke(focus.phase.tint, lineWidth: 2)
                .shadow(color: focus.phase.tint.opacity(0.8), radius: 6)
                .opacity(controller.flash ? 1 : 0)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// The small pill shown at rest. It shows the most relevant thing right now:
/// an alert, a running timer, the paste stack, a reminder, a meeting, music, or the first module.
struct CollapsedView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var focus: FocusTimer
    @EnvironmentObject private var history: ClipboardHistory
    @EnvironmentObject private var clipboard: ClipboardMonitor
    @EnvironmentObject private var reminders: ReminderStore
    @EnvironmentObject private var calendar: CalendarMonitor
    @EnvironmentObject private var nowPlaying: NowPlayingMonitor
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var keepAwake: KeepAwake
    @State private var hovered = false
    @State private var dropTargeted = false

    private enum Content {
        case alert(PillAlert)
        case timer
        case stack(Int)
        case reminder(Reminder)
        case event(CalendarMonitor.UpcomingEvent)
        case music(NowPlayingInfo)
        case module(IslandController.Tab)
    }

    private var content: Content {
        if let alert = controller.alert { return .alert(alert) }
        if focus.isActive && controller.isEnabled(.focus) { return .timer }
        if clipboard.stackMode && controller.isEnabled(.clipboard) { return .stack(clipboard.stack.count) }
        if controller.isEnabled(.now) {
            if let reminder = reminders.upcoming.first { return .reminder(reminder) }
            if let event = calendar.next, event.start.timeIntervalSinceNow <= 15 * 60 { return .event(event) }
            if let info = nowPlaying.info, info.isPlaying { return .music(info) }
        }
        return .module(controller.visibleTabs[0])
    }

    var body: some View {
        HStack(spacing: 7) {
            leading
            Spacer(minLength: controller.geometry.notchWidth)
            trailing
        }
        .padding(.horizontal, 12 + IslandGeometry.pillEar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropTargeted ? Theme.shelf.opacity(0.35) : Color.white.opacity(hovered ? 0.07 : 0))
        .contentShape(Rectangle())
        .onHover {
            hovered = $0
            controller.pillHoverChanged($0)
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .onTapGesture { controller.expand() }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard controller.isEnabled(.shelf) else { return false }
            FileDrop.load(providers) { controller.addToShelf($0) }
            return true
        }
        .help("Open Island (⌥Space)")
    }

    @ViewBuilder
    private var leading: some View {
        if dropTargeted {
            label("tray.and.arrow.down.fill", Theme.shelf, "Drop to park")
        } else {
            switch content {
            case .alert(let alert): label(alert.symbol, alert.tint, alert.text)
            case .timer: label(focus.phase.symbol, focus.phase.tint, focus.phase.label)
            case .stack: label("square.stack.3d.up.fill", Theme.clipboard, "Paste stack")
            case .reminder(let reminder): label("bell.fill", Theme.now, reminder.title)
            case .event(let event): label("calendar", Theme.now, event.title)
            case .music(let info):
                HStack(spacing: 7) {
                    EqualizerBars(active: true)
                    if !controller.geometry.hasNotch { text(info.title) }
                }
            case .module(let tab): label(tab.symbol, tab.accent, tab.rawValue)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if !dropTargeted {
            switch content {
            case .alert, .music:
                EmptyView()
            case .timer:
                Text(focus.remaining.countdownText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(focus.isPaused ? 0.5 : 0.92))
                MiniRing(progress: focus.progress, tint: focus.phase.tint, paused: focus.isPaused)
            case .stack(let count):
                badge("\(count)")
            case .reminder(let reminder):
                countdown(to: reminder.fireDate)
            case .event(let event):
                if event.isHappeningNow { badge("now") } else { countdown(to: event.start) }
            case .module(let tab):
                if keepAwake.isOn {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.focus)
                        .help("Keep awake is on")
                }
                switch tab {
                case .notes: badge("\(store.notes.count)")
                case .clipboard: badge("\(history.items.count)")
                case .shelf: badge("\(shelf.items.count)")
                case .focus, .now, .ports: EmptyView()
                }
            }
        }
    }

    private func label(_ symbol: String, _ tint: Color, _ title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            if !controller.geometry.hasNotch { text(title) }
        }
    }

    private func text(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func badge(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 6)
            .frame(minWidth: 18, minHeight: 16)
            .background(Capsule().fill(.white.opacity(0.14)))
    }

    private func countdown(to date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(date.timeIntervalSince(context.date).shortDurationText)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize()
        }
    }
}

/// Tiny progress ring for the pill.
private struct MiniRing: View {
    let progress: Double
    let tint: Color
    let paused: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(progress, 0.02))
                .stroke(tint.opacity(paused ? 0.5 : 1), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
        .frame(width: 13, height: 13)
    }
}
