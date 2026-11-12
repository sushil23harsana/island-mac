import IslandCore
import SwiftUI

/// The open island: tab bar (beside the notch, if any) and the selected module.
struct ExpandedView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var focus: FocusTimer

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 6)
            Group {
                switch controller.tab {
                case .notes: NotesView()
                case .focus: FocusView()
                case .clipboard: ClipboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(IslandController.Tab.allCases, id: \.self) { tab in
                TabButton(tab: tab, selected: controller.tab == tab) {
                    withAnimation(.easeOut(duration: 0.15)) { controller.tab = tab }
                }
            }
            Spacer(minLength: controller.geometry.notchWidth + 20)
            if focus.isActive && controller.tab != .focus {
                // Keep an eye on the timer from the Notes tab.
                Button { controller.tab = .focus } label: {
                    Label(focus.remaining.countdownText,
                          systemImage: focus.phase == .focus ? "brain.head.profile" : "cup.and.saucer.fill")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(focus.phase.tint.opacity(focus.isPaused ? 0.5 : 1))
                .padding(.trailing, 6)
            }
            Text(Date.now, style: .time)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(height: max(controller.geometry.pillSize.height, 30))
    }
}

private struct TabButton: View {
    let tab: IslandController.Tab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tab.rawValue, systemImage: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(selected ? 0.14 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(tab.rawValue) (⌘\(IslandController.Tab.allCases.firstIndex(of: tab)! + 1))")
    }
}

extension FocusPhase {
    var tint: Color { self == .focus ? .orange : .mint }
    var label: String { self == .focus ? "Focus" : "Break" }
    var symbol: String { self == .focus ? "brain.head.profile" : "cup.and.saucer.fill" }
}
