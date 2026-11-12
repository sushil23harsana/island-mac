import IslandCore
import SwiftUI

/// Focus tab: a Pomodoro ring with controls, session presets and today's stats.
struct FocusView: View {
    @EnvironmentObject private var timer: FocusTimer

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 18) {
                ring
                controls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)

            sidePanel
                .frame(width: 200)
                .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.04)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(timer.phase.tint.gradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timer.progress)

            VStack(spacing: 4) {
                Label(timer.phase.label, systemImage: timer.phase.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(timer.phase.tint)
                Text(timer.remaining.countdownText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: Int(timer.remaining))
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: 190, height: 190)
    }

    private var statusText: String {
        if timer.isPaused { return "Paused" }
        if timer.isRunning { return timer.phase == .focus ? "Stay with it" : "Stretch, drink water" }
        return "space to start"
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            CircleButton(symbol: "arrow.counterclockwise", help: "Reset") { timer.reset() }
                .disabled(!timer.isActive)
                .opacity(timer.isActive ? 1 : 0.35)

            Button { timer.toggle() } label: {
                Label(timer.isRunning ? "Pause" : (timer.isPaused ? "Resume" : "Start"),
                      systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 110, height: 34)
                    .background(Capsule().fill(timer.phase.tint))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Start / pause (space)")

            CircleButton(symbol: "forward.end.fill",
                         help: timer.phase == .focus ? "Skip to break" : "Skip break") { timer.skip() }
        }
    }

    // MARK: Side panel

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Session")
                HStack(spacing: 6) {
                    ForEach(FocusPreset.all) { preset in
                        let selected = preset == timer.preset
                        Button { timer.preset = preset } label: {
                            Text(preset.id)
                                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(.white.opacity(selected ? 0.16 : 0.06)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(timer.isActive)
                    }
                }
                .opacity(timer.isActive ? 0.5 : 1)
                Text(timer.isActive ? "Reset to change length" : "Focus / break minutes")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.35))
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Today")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(timer.todaySessions)")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(timer.todaySessions == 1 ? "session" : "sessions")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                SessionDots(count: timer.todaySessions)
                Text(focusTimeText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("space  start / pause")
                Text("⌘1 ⌘2  switch tabs")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var focusTimeText: String {
        let minutes = Int(timer.todayFocusSeconds / 60)
        if minutes < 60 { return "\(minutes) min focused" }
        return "\(minutes / 60) h \(minutes % 60) min focused"
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.4))
    }
}

/// One dot per session, with a soft goal of 8 a day.
private struct SessionDots: View {
    let count: Int
    private let goal = 8

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(goal, count), id: \.self) { i in
                Circle()
                    .fill(i < count ? Color.orange : .white.opacity(0.1))
                    .frame(width: 9, height: 9)
            }
        }
    }
}

private struct CircleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
