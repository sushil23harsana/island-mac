import AppKit

/// Borderless, transparent, always-on-top panel that sits at the top-center of the screen,
/// over the menu bar (or around the notch on MacBooks that have one).
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    // Needed so the text fields inside can receive typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Allow the window to overlap the menu bar instead of being pushed below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Works out pill / expanded sizes and where the window goes on a given screen.
struct IslandGeometry {
    static let expandedSize = CGSize(width: 620, height: 420)
    /// Transparent margin around the expanded island so its shadow isn't clipped.
    static let shadowPadding: CGFloat = 30

    let screen: NSScreen

    /// Prefer the built-in display with a notch, otherwise the menu bar screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    var hasNotch: Bool { screen.safeAreaInsets.top > 0 }

    /// Width of the camera notch (0 when there is none).
    var notchWidth: CGFloat {
        guard hasNotch,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return 0 }
        return screen.frame.width - left.width - right.width
    }

    var pillSize: CGSize {
        if hasNotch {
            return CGSize(width: notchWidth + 90, height: screen.safeAreaInsets.top)
        }
        return CGSize(width: 210, height: 32)
    }

    func windowFrame(expanded: Bool) -> NSRect {
        let size: CGSize
        if expanded {
            size = CGSize(width: Self.expandedSize.width + Self.shadowPadding * 2,
                          height: Self.expandedSize.height + Self.shadowPadding)
        } else {
            size = pillSize
        }
        let f = screen.frame
        return NSRect(x: (f.midX - size.width / 2).rounded(),
                      y: f.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }
}
