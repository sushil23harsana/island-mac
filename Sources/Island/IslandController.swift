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
        case shelf = "Shelf"
        case now = "Now"
        case ports = "Ports"

        var symbol: String {
            switch self {
            case .notes: "note.text"
            case .focus: "timer"
            case .clipboard: "doc.on.clipboard"
            case .shelf: "tray.full"
            case .now: "sparkles"
            case .ports: "network"
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
    @Published var showSettings = false

    // Settings (all saved in UserDefaults)
    /// Which modules are switched on. At least one always is.
    @Published private(set) var enabledTabs: Set<Tab>
    @Published var focusSound: Bool {
        didSet { UserDefaults.standard.set(focusSound, forKey: "focus.sound") }
    }
    @Published var clipboardLimit: Int {
        didSet {
            UserDefaults.standard.set(clipboardLimit, forKey: "clipboard.limit")
            clipboard.history.limit = clipboardLimit
        }
    }
    static let clipboardLimitChoices = [50, 200, 500]

    /// Enabled modules in display order.
    var visibleTabs: [Tab] { Tab.allCases.filter(enabledTabs.contains) }
    /// Briefly true when a focus block or break ends, so the pill can glow.
    @Published private(set) var flash = false
    /// Setting: open the island by resting the mouse on the pill (no click needed).
    @Published var openOnHover: Bool {
        didSet { UserDefaults.standard.set(openOnHover, forKey: "openOnHover") }
    }
    let commands = PassthroughSubject<Command, Never>()
    let store = NotesStore()
    let focus = FocusTimer()
    let clipboard: ClipboardMonitor
    let reminders: ReminderStore
    let shelf: ShelfStore
    let nowPlaying = NowPlayingMonitor()
    let calendar = CalendarMonitor()
    let power = PowerMonitor()
    let keepAwake = KeepAwake()
    let portsModel = PortsModel()
    let audioOutput = AudioOutputMonitor()
    /// A short message shown in the pill (see IslandController+Live.swift).
    @Published var alert: PillAlert?
    var alertTask: Task<Void, Never>?
    var alertedEventID: String?

    private var panel: IslandPanel!
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var shrinkTask: Task<Void, Never>?
    private var ticker: Timer?
    private var hoverOpenTask: Task<Void, Never>?
    private var hoverWatch: Timer?
    private var clickMonitor: Any?
    /// True while the island was opened by hover and hasn't been used yet;
    /// in that state it closes again when the mouse moves away.
    private var openedByHover = false
    /// After the island closes, hover-open waits until the mouse has left the pill once,
    /// so pressing Esc with the mouse still on the pill doesn't reopen it straight away.
    private var hoverArmed = true
    private var outsideClickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?

    init() {
        geometry = IslandGeometry(screen: IslandGeometry.preferredScreen() ?? NSScreen.main!)
        let defaults = UserDefaults.standard
        openOnHover = defaults.bool(forKey: "openOnHover")
        focusSound = defaults.object(forKey: "focus.sound") as? Bool ?? true
        let savedLimit = defaults.integer(forKey: "clipboard.limit")
        clipboardLimit = Self.clipboardLimitChoices.contains(savedLimit) ? savedLimit : 200

        // All modules are on unless the user switched some off.
        // (Stored as the "off" list so modules added in later versions start switched on.)
        let off = (defaults.stringArray(forKey: "disabledTabs") ?? []).compactMap(Tab.init(rawValue:))
        let on = Set(Tab.allCases).subtracting(off)
        enabledTabs = on.isEmpty ? Set(Tab.allCases) : on

        var dataFolder = ClipboardHistory.defaultDirectory
        #if DEBUG
        if ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT"] != nil {
            // Snapshots use throwaway data, never the real reminders or shelf.
            dataFolder = FileManager.default.temporaryDirectory.appendingPathComponent("IslandSnapshot-\(UUID().uuidString)")
        }
        #endif
        reminders = ReminderStore(directory: dataFolder)
        shelf = ShelfStore(directory: dataFolder)

        clipboard = ClipboardMonitor(history: Self.makeClipboardHistory())
        clipboard.history.limit = clipboardLimit
        clipboard.isEnabled = enabledTabs.contains(.clipboard)
        tab = visibleTabs[0]
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
            .environmentObject(reminders)
            .environmentObject(shelf)
            .environmentObject(nowPlaying)
            .environmentObject(calendar)
            .environmentObject(power)
            .environmentObject(keepAwake)
            .environmentObject(portsModel)
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

        // Clicking inside a hover-opened island means "I'm using this": keep it open.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if event.window is IslandPanel {
                MainActor.assumeIsolated { self?.keepOpenAfterHover() }
            }
            return event
        }

        startFocusTicker()

        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT"] {
            snapshotForDebugging(to: path)
            return // don't record the real clipboard while taking snapshots
        }
        #endif
        clipboard.start()
        startLiveMonitors()
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
                .environmentObject(clipboard).environmentObject(clipboard.history)
                .environmentObject(reminders).environmentObject(shelf).environmentObject(nowPlaying)
                .environmentObject(calendar).environmentObject(keepAwake)
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
            let builtIn = focus.preset
            focus.preset = focus.customPreset
            try? await Task.sleep(for: .milliseconds(600))
            write("focus-custom")
            focus.preset = builtIn
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
            try? await Task.sleep(for: .milliseconds(600))
            openSettings()
            try? await Task.sleep(for: .milliseconds(800))
            write("settings")
            setEnabled(.focus, false)
            try? await Task.sleep(for: .milliseconds(500))
            write("settings-focus-off")
            setEnabled(.focus, true)
            collapse(restoreFocus: false)

            // New modules, with made-up data.
            try? await Task.sleep(for: .milliseconds(600))
            nowPlaying.setForSnapshot(NowPlayingInfo(source: .spotify, title: "Midnight City", artist: "M83", isPlaying: true))
            try? await Task.sleep(for: .milliseconds(400))
            write("pill-music")
            calendar.setForSnapshot(.init(id: "demo", title: "Design review",
                                          start: Date().addingTimeInterval(540), end: Date().addingTimeInterval(2340),
                                          joinURL: URL(string: "https://meet.google.com/demo")))
            try? await Task.sleep(for: .milliseconds(400))
            write("pill-meeting")
            reminders.add(Reminder(title: "Call mom", fireDate: Date().addingTimeInterval(1200)))
            shelf.add(["/Applications/Xcode.app", "/etc/hosts", "/System/Applications/Notes.app",
                       "/System/Applications/Calculator.app", "/Library/Fonts"].map { URL(fileURLWithPath: $0) })
            expand(tab: .now)
            try? await Task.sleep(for: .milliseconds(900))
            write("now")
            tab = .shelf
            try? await Task.sleep(for: .milliseconds(600))
            write("shelf")
            tab = .ports
            try? await Task.sleep(for: .milliseconds(1800))
            write("ports")
            print("ports: \(portsModel.ports.count) found")
            collapse(restoreFocus: false)
            try? await Task.sleep(for: .milliseconds(600))

            // Self-checks for the parts that touch the system.
            let scheduled = addReminder(from: "in 1s self-check ping")
            try? await Task.sleep(for: .milliseconds(2600))
            let fired = reminders.fired.contains { $0.title == "Self-check ping" }
            print("reminder: \(scheduled && fired ? "fired" : "DID NOT FIRE"), pill alert: \(alert?.text ?? "none")")
            write("pill-alert")

            keepAwake.set(true)
            let pmset = Process()
            pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            pmset.arguments = ["-g", "assertions"]
            let pipe = Pipe()
            pmset.standardOutput = pipe
            try? pmset.run()
            let assertions = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("keep-awake: \(assertions.contains("Island: Keep Awake") ? "system sees it" : "NOT REGISTERED")")
            keepAwake.set(false)

            let sample = NSImage(size: NSSize(width: 640, height: 120), flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                ("Island reads text 12345" as NSString).draw(at: NSPoint(x: 20, y: 40), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black,
                ])
                return true
            }
            if let cg = sample.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                print("text-grab: read \"\(TextGrabber.recognizeText(in: cg))\"")
            }
            alert = nil

            // Hover check: a simulated "mouse entered the pill" should open the island, and since
            // the real mouse is elsewhere it should close again by itself.
            try? await Task.sleep(for: .milliseconds(700))
            openOnHover = true
            pillHoverChanged(true)
            try? await Task.sleep(for: .milliseconds(450))
            print("hover-open: \(mode == .expanded ? "opened" : "DID NOT OPEN")")
            try? await Task.sleep(for: .milliseconds(800))
            print("hover-leave: \(mode == .collapsed ? "closed" : "DID NOT CLOSE")")
            pillHoverChanged(false) // the mouse left, so hover-open is armed again
            pillHoverChanged(true)
            try? await Task.sleep(for: .milliseconds(450))
            keepOpenAfterHover() // as if the user clicked inside
            try? await Task.sleep(for: .milliseconds(800))
            print("hover-then-click: \(mode == .expanded ? "stayed open" : "CLOSED")")
            openOnHover = false
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
        guard isEnabled(.clipboard) else { return }
        if mode == .expanded && tab == .clipboard {
            collapse(restoreFocus: true)
        } else {
            expand(tab: .clipboard)
        }
    }

    func expand(tab newTab: Tab? = nil) {
        if let newTab, isEnabled(newTab) {
            tab = newTab
            showSettings = false
        }
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
        keepOpenAfterHover()
        hoverArmed = false
        showSettings = false
        Task { @MainActor [weak self] in
            // If the mouse is already elsewhere, there will be no "left the pill" event to wait for.
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.mode == .collapsed else { return }
            if !self.panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
                self.hoverArmed = true
            }
        }
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

    // MARK: - Modules

    func isEnabled(_ tab: Tab) -> Bool { enabledTabs.contains(tab) }

    /// Turns a module on or off. The last remaining module can't be turned off.
    func setEnabled(_ module: Tab, _ on: Bool) {
        if on {
            enabledTabs.insert(module)
        } else {
            guard enabledTabs.count > 1 else { return }
            enabledTabs.remove(module)
            if module == .focus { focus.reset() }
            if module == .now { keepAwake.set(false) }
            if module == .clipboard { clipboard.stackMode = false }
            if tab == module { tab = visibleTabs[0] }
        }
        clipboard.isEnabled = enabledTabs.contains(.clipboard)
        UserDefaults.standard.set(Tab.allCases.filter { !enabledTabs.contains($0) }.map(\.rawValue),
                                  forKey: "disabledTabs")
    }

    func openSettings() {
        showSettings = true
        if mode == .collapsed { expand() }
    }

    // MARK: - Open on hover

    /// Called when the mouse enters or leaves the collapsed pill.
    func pillHoverChanged(_ inside: Bool) {
        hoverOpenTask?.cancel()
        guard inside else {
            hoverArmed = true
            return
        }
        guard hoverArmed, openOnHover, mode == .collapsed else { return }
        // Short delay so just passing over the pill on the way to the menu bar doesn't open it.
        hoverOpenTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard let self, !Task.isCancelled, self.mode == .collapsed, self.openOnHover else { return }
            self.expand()
            self.openedByHover = true
            self.startHoverWatch()
        }
    }

    /// While a hover-opened island is untouched, close it once the mouse has moved away.
    private func startHoverWatch() {
        hoverWatch?.invalidate()
        var missesInARow = 0
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.openedByHover, self.mode == .expanded else { return }
                missesInARow = self.mouseIsOverIsland ? 0 : missesInARow + 1
                if missesInARow >= 2 { self.collapse(restoreFocus: true) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverWatch = timer
    }

    private func keepOpenAfterHover() {
        openedByHover = false
        hoverWatch?.invalidate()
        hoverWatch = nil
    }

    private var mouseIsOverIsland: Bool {
        // The window is larger than the island (shadow margin), so shrink to the visible part,
        // then allow a little slack around the edges.
        let pad = IslandGeometry.shadowPadding
        var rect = panel.frame
        rect.origin.x += pad
        rect.size.width -= pad * 2
        rect.origin.y += pad
        rect.size.height -= pad
        return rect.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation)
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
            MainActor.assumeIsolated {
                self?.focus.tick()
                self?.tickLive()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common) // keep ticking while menus are open
        ticker = timer
    }

    private func phaseFinished(_ phase: FocusPhase) {
        if focusSound { NSSound(named: phase == .focus ? "Glass" : "Hero")?.play() }
        glow()
    }

    /// Makes the island's outline glow for a moment.
    func glow() {
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
        keepOpenAfterHover() // typing counts as using the island
        let flags = flags.intersection([.command, .option, .control, .shift])

        if showSettings {
            // Only the general shortcuts work while Settings is showing.
            guard keyCode == 53 || flags == .command && (Self.digitKeys + [43]).contains(keyCode) else { return false }
        }

        switch (keyCode, flags) {
        case (53, []): // Esc
            collapse(restoreFocus: true)
        case (45, .command) where tab == .notes: // ⌘N
            commands.send(.newNote)
        case (3, .command): // ⌘F
            commands.send(.focusSearch)
        case (36, .command) where tab == .notes: // ⌘Return
            commands.send(.saveCaptureAndClose)
        case (43, .command): // ⌘,
            showSettings.toggle()
        case (_, .command) where Self.digitKeys.contains(keyCode): // ⌘1 … ⌘6
            guard let index = Self.digitKeys.firstIndex(of: keyCode), index < visibleTabs.count else { return false }
            tab = visibleTabs[index]
            showSettings = false
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

    /// Key codes of the number-row keys 1–6, in order.
    private static let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22]

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
