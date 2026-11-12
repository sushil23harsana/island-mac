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
                if controller.showSettings {
                    SettingsView()
                } else {
                    switch controller.tab {
                    case .notes: NotesView()
                    case .focus: FocusView()
                    case .clipboard: ClipboardView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(controller.showSettings ? "settings" : controller.tab.rawValue)
            .transition(.opacity)
        }
        .padding(.horizontal, 16 + IslandGeometry.expandedEar)
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.16), value: controller.tab)
        .animation(.easeOut(duration: 0.16), value: controller.showSettings)
    }

    private var header: some View {
        HStack(spacing: 2) {
            ForEach(controller.visibleTabs, id: \.self) { tab in
                tabButton(tab)
            }
            Spacer(minLength: controller.geometry.notchWidth + 20)
            if focus.isActive && controller.isEnabled(.focus) && (controller.tab != .focus || controller.showSettings) {
                // Keep an eye on the timer from the other tabs.
                Button {
                    controller.tab = .focus
                    controller.showSettings = false
                } label: {
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
            Button { controller.showSettings.toggle() } label: {
                Image(systemName: "gearshape.fill")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(controller.showSettings ? 0.95 : 0.5))
                    .frame(width: 26, height: 24)
                    .background(Capsule().fill(.white.opacity(controller.showSettings ? 0.16 : 0)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .help("Settings (⌘,)")
        }
        .frame(height: max(controller.geometry.pillSize.height, 34))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: controller.tab)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: controller.visibleTabs)
    }

    private func tabButton(_ tab: IslandController.Tab) -> some View {
        let selected = controller.tab == tab && !controller.showSettings
        return Button {
            controller.tab = tab
            controller.showSettings = false
        } label: {
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
        .help("\(tab.rawValue) (⌘\((controller.visibleTabs.firstIndex(of: tab) ?? 0) + 1))")
    }
}
