import AppKit
import Combine
import IslandCore
import SwiftUI

/// Owns the island window and decides when it is collapsed (pill) or expanded.
@MainActor
final class IslandController: ObservableObject {
    enum Mode { case collapsed, expanded }

    enum Tab: String, CaseIterable {
        case notes = "Notes"
        case focus = "Focus"
        case clipboard = "Clipboard"

        var symbol: String {
            switch self {
            case .notes: "note.text"
            case .focus: "timer"
            case .clipboard: "doc.on.clipboard"
            }
        }
    }

    enum Command {
        /// Put the cursor in the tab's main field (capture bar / clipboard search).
        case focusCapture
        case focusSearch
        case newNote
        case saveCaptureAndClose
        // Clipboard tab
        case moveSelection(Int)
        case pasteSelection
        case togglePinSelection
        case deleteSelection
    }

    @Published private(set) var mode: Mode = .collapsed
    @Published private(set) var geometry: IslandGeometry
    @Published var tab: Tab = .notes
    /// Briefly true when a focus block or break ends, so the pill can glow.
    @Published private(set) var flash = false
    let commands = PassthroughSubject<Command, Never>()
    let store = NotesStore()
    let focus = FocusTimer()
    let clipboard: ClipboardMonitor

    private var panel: IslandPanel!
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var shrinkTask: Task<Void, Never>?
    private var ticker: Timer?
    private var outsideClickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?

    init() {
        geometry = IslandGeometry(screen: IslandGeometry.preferredScreen() ?? NSScreen.main!)
        clipboard = ClipboardMonitor(history: Self.makeClipboardHistory())
    }

    private static func makeClipboardHistory() -> ClipboardHistory {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT"] != nil {
            // Snapshots use made-up items, never the real clipboard history.
            let demo = ClipboardHistory(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("IslandSnapshot-\(UUID().uuidString)"))
            demo.addText("https://developer.apple.com/documentation/swiftui", sourceApp: "Safari")
            demo.addText("#FF9F0A", sourceApp: "Figma")
            demo.addFiles(["/Users/me/Documents/Lecture 4 slides.pdf"], sourceApp: "Finder")
            demo.addText("git commit -m \"Add focus timer\" && git push", sourceApp: "Terminal")
            demo.togglePin(demo.items[0].id)
            demo.addText("func greet(_ name: String) -> String {\n    \"Hello, \\(name)!\"\n}", sourceApp: "Xcode")
            return demo
        }
        #endif
        return ClipboardHistory()
    }

    func start() {
        panel = IslandPanel(contentRect: geometry.windowFrame(expanded: false))
        watchForLeavingTheIsland()

        let root = IslandView()
            .environmentObject(self)
            .environmentObject(store)
            .environmentObject(focus)
            .environmentObject(clipboard)
            .environmentObject(clipboard.history)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.repositionForScreenChange() }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors always run on the main thread.
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let isOurs = event.window is IslandPanel
            let handled = MainActor.assumeIsolated {
                self?.handleKey(keyCode: keyCode, flags: flags, inIsland: isOurs) ?? false
            }
            return handled ? nil : event
        }

        startFocusTicker()

        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT"] {
            snapshotForDebugging(to: path)
            return // don't record the real clipboard while taking snapshots
        }
        #endif
        clipboard.start()
    }

    #if DEBUG
    /// Dev aid: expands, writes PNGs of the island window itself, then quits.
    /// Lets you check the UI without granting Screen Recording permission.
    private func snapshotForDebugging(to directory: String) {
        Task { @MainActor in
            @MainActor func write(_ name: String) {
                guard let view = panel.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
            try? await Task.sleep(for: .milliseconds(500))
            write("collapsed")
            // Second opinion on colors: SwiftUI's own renderer (cacheDisplay can mis-tint SF Symbols).
            let pill = CollapsedView()
                .frame(width: geometry.pillSize.width, height: geometry.pillSize.height)
                .background(Color.black)
                .environmentObject(self).environmentObject(store).environmentObject(focus)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: pill)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("pill-swiftui.png"))
            }
            expand()
            try? await Task.sleep(for: .milliseconds(800))
            write("expanded")
            tab = .focus
            focus.start()
            try? await Task.sleep(for: .milliseconds(1500))
            write("focus")
            tab = .clipboard
            try? await Task.sleep(for: .milliseconds(600))
            write("clipboard")
            commands.send(.moveSelection(1))
            try? await Task.sleep(for: .milliseconds(400))
            write("clipboard-color")
            collapse(restoreFocus: false)
            try? await Task.sleep(for: .milliseconds(700))
            write("collapsed-running")
            focus.reset()
            NSApp.terminate(nil)
        }
    }
    #endif

    // MARK: - Expand / collapse

    func toggle() {
        mode == .expanded ? collapse(restoreFocus: true) : expand()
    }

    /// Opens straight to the clipboard; pressing the shortcut again closes it.
    func toggleClipboard() {
        if mode == .expanded && tab == .clipboard {
            collapse(restoreFocus: true)
        } else {
            expand(tab: .clipboard)
        }
    }

    func expand(tab newTab: Tab? = nil) {
        if let newTab { tab = newTab }
        guard mode == .collapsed else {
            commands.send(.focusCapture)
            return
        }
        shrinkTask?.cancel()

        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        store.reload()
        panel.setFrame(geometry.windowFrame(expanded: true), display: true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            mode = .expanded
        }
    }

    func collapse(restoreFocus: Bool) {
        guard mode == .expanded else { return }
        store.removeBlankNotes()

        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            mode = .collapsed
        }

        // Shrink the window only after the SwiftUI shape has animated down.
        shrinkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(340))
            guard let self, !Task.isCancelled, self.mode == .collapsed else { return }
            self.panel.setFrame(self.geometry.windowFrame(expanded: false), display: true)
        }

        if restoreFocus {
            previousApp?.activate()
        }
        previousApp = nil
    }

    /// Folds the island up when you click outside it or switch to another app.
    /// (More reliable than "window lost key", which can fire without any user action.)
    private func watchForLeavingTheIsland() {
        // Global monitors only see events going to *other* apps, i.e. clicks outside Island.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse(restoreFocus: false) }
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            guard pid != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.collapse(restoreFocus: false) }
        }
    }

    // MARK: - Clipboard

    /// Copies the item, returns to the previous app and, if allowed, pastes it there.
    func paste(_ item: ClipItem) {
        clipboard.copy(item)
        collapse(restoreFocus: true)
        guard clipboard.canAutoPaste else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180)) // let the other app come forward
            self?.clipboard.sendPasteKeystroke()
        }
    }

    // MARK: - Focus timer

    private func startFocusTicker() {
        focus.onPhaseFinished = { [weak self] finished in
            self?.phaseFinished(finished)
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.focus.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common) // keep ticking while menus are open
        ticker = timer
    }

    private func phaseFinished(_ phase: FocusPhase) {
        NSSound(named: phase == .focus ? "Glass" : "Hero")?.play()
        withAnimation(.easeInOut(duration: 0.3)) { flash = true }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeInOut(duration: 0.6)) { self?.flash = false }
        }
    }

    // MARK: - Keyboard

    /// Returns true when the key press was handled (and should be swallowed).
    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, inIsland: Bool) -> Bool {
        guard mode == .expanded, inIsland else { return false }
        let flags = flags.intersection([.command, .option, .control, .shift])

        switch (keyCode, flags) {
        case (53, []): // Esc
            collapse(restoreFocus: true)
        case (45, .command) where tab == .notes: // ⌘N
            commands.send(.newNote)
        case (3, .command): // ⌘F
            commands.send(.focusSearch)
        case (36, .command) where tab == .notes: // ⌘Return
            commands.send(.saveCaptureAndClose)
        case (18, .command): // ⌘1
            tab = .notes
        case (19, .command): // ⌘2
            tab = .focus
        case (20, .command): // ⌘3
            tab = .clipboard
        case (49, []) where tab == .focus && !isEditingText: // Space
            focus.toggle()
        case (125, []) where tab == .clipboard: // ↓
            commands.send(.moveSelection(1))
        case (126, []) where tab == .clipboard: // ↑
            commands.send(.moveSelection(-1))
        case (36, []) where tab == .clipboard: // Return
            commands.send(.pasteSelection)
        case (35, .command) where tab == .clipboard: // ⌘P
            commands.send(.togglePinSelection)
        case (51, .command) where tab == .clipboard: // ⌘⌫
            commands.send(.deleteSelection)
        default:
            return false
        }
        return true
    }

    private var isEditingText: Bool {
        panel.firstResponder is NSText
    }

    // MARK: - Screens

    private func repositionForScreenChange() {
        guard let screen = IslandGeometry.preferredScreen() else { return }
        geometry = IslandGeometry(screen: screen)
        panel.setFrame(geometry.windowFrame(expanded: mode == .expanded), display: true)
    }
}
