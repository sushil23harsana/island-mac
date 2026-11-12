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

/// The small pill shown at rest. Shows the timer while one is active, otherwise notes.
struct CollapsedView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var focus: FocusTimer
    @EnvironmentObject private var history: ClipboardHistory
    @State private var hovered = false

    private var showTimer: Bool { focus.isActive && controller.isEnabled(.focus) }
    /// What the pill shows when no timer is running: the first enabled module.
    private var primary: IslandController.Tab { controller.visibleTabs[0] }
    private var badge: String? {
        switch primary {
        case .notes: "\(store.notes.count)"
        case .clipboard: "\(history.items.count)"
        case .focus: nil
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: showTimer ? focus.phase.symbol : primary.symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(showTimer ? focus.phase.tint : primary.accent)
            if !controller.geometry.hasNotch {
                Text(showTimer ? focus.phase.label : primary.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: controller.geometry.notchWidth)
            if showTimer {
                Text(focus.remaining.countdownText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(focus.isPaused ? 0.5 : 0.92))
                MiniRing(progress: focus.progress, tint: focus.phase.tint, paused: focus.isPaused)
            } else if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(Capsule().fill(.white.opacity(0.14)))
            }
        }
        .padding(.horizontal, 12 + IslandGeometry.pillEar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(hovered ? 0.07 : 0))
        .contentShape(Rectangle())
        .onHover {
            hovered = $0
            controller.pillHoverChanged($0)
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .onTapGesture { controller.expand() }
        .help("Open Island (⌥Space)")
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
