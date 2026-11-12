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

    private var shape: UnevenRoundedRectangle {
        let r: CGFloat = expanded ? 26 : 14
        return UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r,
                                      bottomTrailingRadius: r, topTrailingRadius: 0,
                                      style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if expanded {
                ExpandedView()
                    .frame(width: IslandGeometry.expandedSize.width,
                           height: IslandGeometry.expandedSize.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.06)))
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
                .shadow(color: .black.opacity(expanded ? 0.5 : 0), radius: 18, y: 8)
        )
        .overlay(
            // Glow when a focus block or break finishes.
            shape
                .stroke(focus.phase.tint, lineWidth: 2)
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

    private var showTimer: Bool { focus.isActive }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: showTimer ? focus.phase.symbol : "note.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(showTimer ? focus.phase.tint : .yellow)
            if !controller.geometry.hasNotch {
                Text(showTimer ? focus.phase.label : "Notes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: controller.geometry.notchWidth)
            if showTimer {
                HStack(spacing: 3) {
                    if focus.isPaused {
                        Image(systemName: "pause.fill").font(.system(size: 8))
                    }
                    Text(focus.remaining.countdownText)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(focus.isPaused ? 0.5 : 0.9))
            } else {
                Text("\(store.notes.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showTimer {
                // Thin progress line along the bottom of the pill.
                GeometryReader { geo in
                    Capsule()
                        .fill(focus.phase.tint)
                        .frame(width: max(geo.size.width * focus.progress, 3), height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 14)
                .padding(.bottom, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { controller.expand() }
        .help("Open Island (⌥Space)")
    }
}
