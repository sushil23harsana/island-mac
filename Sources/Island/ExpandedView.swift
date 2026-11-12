import IslandCore
import SwiftUI

/// The open island: tab bar (beside the notch, if any) and the selected module.
struct ExpandedView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var focus: FocusTimer
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 8)
            Group {
                switch controller.tab {
                case .notes: NotesView()
                case .focus: FocusView()
                case .clipboard: ClipboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(controller.tab)
            .transition(.opacity)
        }
        .padding(.horizontal, 16 + IslandGeometry.expandedEar)
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.16), value: controller.tab)
    }

    private var header: some View {
        HStack(spacing: 2) {
            ForEach(IslandController.Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
            Spacer(minLength: controller.geometry.notchWidth + 20)
            if focus.isActive && controller.tab != .focus {
                // Keep an eye on the timer from the other tabs.
                Button { controller.tab = .focus } label: {
                    HStack(spacing: 5) {
                        Image(systemName: focus.phase.symbol)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 10, weight: .semibold))
                        Text(focus.remaining.countdownText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                    .foregroundStyle(focus.phase.tint.opacity(focus.isPaused ? 0.55 : 1))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(focus.phase.tint.opacity(0.14)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .transition(.opacity)
            }
            Text(Date.now, style: .time)
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(height: max(controller.geometry.pillSize.height, 34))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: controller.tab)
    }

    private func tabButton(_ tab: IslandController.Tab) -> some View {
        let selected = controller.tab == tab
        return Button { controller.tab = tab } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(selected ? tab.accent : .white.opacity(0.5))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                if selected {
                    // One capsule that slides between tabs.
                    Capsule()
                        .fill(tab.accent.opacity(0.16))
                        .overlay(Capsule().strokeBorder(tab.accent.opacity(0.22), lineWidth: 1))
                        .matchedGeometryEffect(id: "selectedTab", in: tabNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(tab.rawValue) (⌘\(IslandController.Tab.allCases.firstIndex(of: tab)! + 1))")
    }
}
