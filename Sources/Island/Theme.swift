import IslandCore
import SwiftUI

/// Shared colors and surfaces so every tab looks like part of the same app.
enum Theme {
    static let notes = Color(red: 1.00, green: 0.80, blue: 0.26)
    static let focus = Color(red: 1.00, green: 0.56, blue: 0.24)
    static let rest = Color(red: 0.42, green: 0.90, blue: 0.74)
    static let clipboard = Color(red: 0.44, green: 0.72, blue: 1.00)
    static let shelf = Color(red: 0.72, green: 0.58, blue: 1.00)
    static let now = Color(red: 1.00, green: 0.47, blue: 0.62)
    static let ports = Color(red: 0.45, green: 0.88, blue: 0.52)
    static let alert = Color(red: 1.00, green: 0.40, blue: 0.36)
}

extension IslandController.Tab {
    var accent: Color {
        switch self {
        case .notes: Theme.notes
        case .focus: Theme.focus
        case .clipboard: Theme.clipboard
        case .shelf: Theme.shelf
        case .now: Theme.now
        case .ports: Theme.ports
        }
    }
}

extension FocusPhase {
    var tint: Color { self == .focus ? Theme.focus : Theme.rest }
    var label: String { self == .focus ? "Focus" : "Break" }
    var symbol: String { self == .focus ? "brain.head.profile" : "cup.and.saucer.fill" }
}

// MARK: - Surfaces

/// Raised panel: soft top-lit gradient with a hairline border.
private struct Surface: ViewModifier {
    let radius: CGFloat
    let strength: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                shape.fill(LinearGradient(
                    colors: [.white.opacity(0.075 * strength), .white.opacity(0.035 * strength)],
                    startPoint: .top, endPoint: .bottom))
            )
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.16), .white.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }
}

/// List row highlight: accent tint when selected, faint lift on hover.
private struct RowBackground: ViewModifier {
    let selected: Bool
    let accent: Color
    @State private var hovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        content
            .background(
                shape.fill(selected ? accent.opacity(0.17) : .white.opacity(hovered ? 0.06 : 0))
            )
            .overlay(shape.strokeBorder(accent.opacity(selected ? 0.28 : 0), lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
            .animation(.easeOut(duration: 0.12), value: selected)
    }
}

extension View {
    /// Main content panel of a tab.
    func card(radius: CGFloat = 16) -> some View {
        modifier(Surface(radius: radius, strength: 1))
    }

    /// Input bars (capture, search).
    func field(radius: CGFloat = 12) -> some View {
        modifier(Surface(radius: radius, strength: 1.5))
    }

    func rowBackground(selected: Bool, accent: Color) -> some View {
        modifier(RowBackground(selected: selected, accent: accent))
    }
}

// MARK: - Island shape

/// The island outline: hangs from the top edge with small outward "ears" (like the
/// MacBook notch) and rounded bottom corners. Both radii animate.
struct IslandShape: Shape {
    var ear: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, radius) }
        set { ear = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height - ear, rect.width / 2 - ear)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
                       control: CGPoint(x: rect.minX + ear, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ear + r, y: rect.maxY),
                       control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ear - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - r),
                       control: CGPoint(x: rect.maxX - ear, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
