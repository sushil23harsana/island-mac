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
        .card()
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.07), lineWidth: 10)
            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(timer.phase.tint.gradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: timer.phase.tint.opacity(0.55), radius: 9)
                .animation(.linear(duration: 1), value: timer.progress)

            VStack(spacing: 4) {
                Label(timer.phase.label, systemImage: timer.phase.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                    .background(Capsule().fill(timer.phase.tint.gradient)
                        .shadow(color: timer.phase.tint.opacity(0.45), radius: 8, y: 2))
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
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(FocusPreset.all) { preset in
                            presetChip(preset.id, selected: preset == timer.preset) { timer.preset = preset }
                        }
                    }
                    HStack(spacing: 6) {
                        presetChip("Custom", symbol: "slider.horizontal.3", selected: timer.isCustom) {
                            timer.preset = timer.customPreset
                        }
                        if !timer.isCustom {
                            Text(timer.customPreset.id)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    if timer.isCustom {
                        MinuteStepper(label: "Focus", value: timer.customPreset.focusMinutes, step: 5,
                                      range: FocusPreset.focusRange, tint: Theme.focus) {
                            timer.setCustom(focusMinutes: $0, restMinutes: timer.customPreset.restMinutes)
                        }
                        MinuteStepper(label: "Break", value: timer.customPreset.restMinutes, step: 1,
                                      range: FocusPreset.restRange, tint: Theme.rest) {
                            timer.setCustom(focusMinutes: timer.customPreset.focusMinutes, restMinutes: $0)
                        }
                    }
                }
                .disabled(timer.isActive)
                .opacity(timer.isActive ? 0.5 : 1)
                Text(timer.isActive ? "Reset to change length"
                     : timer.isCustom ? "Type a number or use − +" : "Focus / break minutes")
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

    private func presetChip(_ title: String, symbol: String? = nil, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(selected ? Theme.focus : .white.opacity(0.55))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected ? Theme.focus.opacity(0.18) : .white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Theme.focus.opacity(selected ? 0.3 : 0), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
                    .fill(i < count ? Theme.focus : .white.opacity(0.1))
                    .shadow(color: Theme.focus.opacity(i < count ? 0.6 : 0), radius: 3)
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

/// "Focus  −  [45]  +  min": type a number or nudge it with the buttons.
private struct MinuteStepper: View {
    let label: String
    let value: Int
    let step: Int
    let range: ClosedRange<Int>
    let tint: Color
    let onChange: (Int) -> Void

    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38, alignment: .leading)
            nudge("minus", by: -step)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 38, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.1)))
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { _, isEditing in if !isEditing { commit() } }
            nudge("plus", by: step)
            Text("min")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, new in text = "\(new)" }
    }

    private func nudge(_ symbol: String, by delta: Int) -> some View {
        Button {
            // Snap to the step grid first (e.g. 42 → 45 with a step of 5).
            let snapped = delta > 0 ? (value / step + 1) * step : ((value - 1) / step) * step
            onChange(min(max(snapped, range.lowerBound), range.upperBound))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func commit() {
        if let typed = Int(text.trimmingCharacters(in: .whitespaces)) {
            onChange(typed) // the timer clamps it to the allowed range
        }
        text = "\(value)"
    }
}
