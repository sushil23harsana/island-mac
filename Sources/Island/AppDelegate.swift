import AppKit
import Carbon.HIToolbox
import IslandCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: IslandController!
    private var hotKey: HotKey?
    private var clipboardHotKey: HotKey?
    private var stackHotKey: HotKey?
    private var grabHotKey: HotKey?
    private var keepAwakeItem: NSMenuItem!
    private var grabTextItem: NSMenuItem!
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!
    private var pauseClipboardItem: NSMenuItem!
    private var openOnHoverItem: NSMenuItem!
    private var clipboardItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = IslandController()
        controller.start()

        // ⌥Space opens the island from anywhere.
        hotKey = HotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak self] in
            self?.controller.toggle()
        }
        if hotKey == nil {
            NSLog("Island: could not register ⌥Space (another app may be using it)")
        }

        // ⌃⌥V jumps straight to clipboard history.
        clipboardHotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey) { [weak self] in
            self?.controller.toggleClipboard()
        }
        if clipboardHotKey == nil {
            NSLog("Island: could not register ⌃⌥V (another app may be using it)")
        }

        // ⌃⌥B pastes the next item from the paste stack; ⌃⌥T grabs text from the screen.
        stackHotKey = HotKey(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey) { [weak self] in
            self?.controller.pasteNextFromStack()
        }
        grabHotKey = HotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak self] in
            guard let self, self.controller.isEnabled(.now) else { return }
            self.controller.grabText()
        }

        setUpStatusItem()
    }

    // MARK: - Menu bar item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.portrait.fill",
                                           accessibilityDescription: "Island")
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self

        let open = NSMenuItem(title: "Open Island", action: #selector(openIsland), keyEquivalent: " ")
        open.keyEquivalentModifierMask = .option
        menu.addItem(open)
        let clips = NSMenuItem(title: "Clipboard History", action: #selector(openClipboard), keyEquivalent: "v")
        clips.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(clips)
        clipboardItem = clips
        pauseClipboardItem = menu.addItem(withTitle: "Pause Clipboard Recording",
                                          action: #selector(toggleClipboardPause), keyEquivalent: "")
        let grab = NSMenuItem(title: "Grab Text from Screen", action: #selector(grabText), keyEquivalent: "t")
        grab.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(grab)
        grabTextItem = grab
        keepAwakeItem = menu.addItem(withTitle: "Keep Awake", action: #selector(toggleKeepAwake), keyEquivalent: "")
        menu.addItem(withTitle: "Show Notes Folder", action: #selector(showNotesFolder), keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command
        openOnHoverItem = menu.addItem(withTitle: "Open on Hover", action: #selector(toggleOpenOnHover), keyEquivalent: "")
        launchAtLoginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        pauseClipboardItem.state = controller.clipboard.isPaused ? .on : .off
        clipboardItem.isHidden = !controller.isEnabled(.clipboard)
        pauseClipboardItem.isHidden = !controller.isEnabled(.clipboard)
        openOnHoverItem.state = controller.openOnHover ? .on : .off
        keepAwakeItem.state = controller.keepAwake.isOn ? .on : .off
        keepAwakeItem.isHidden = !controller.isEnabled(.now)
        grabTextItem.isHidden = !controller.isEnabled(.now)
    }

    @objc private func openIsland() {
        controller.expand()
    }

    @objc private func openClipboard() {
        controller.expand(tab: .clipboard)
    }

    @objc private func toggleClipboardPause() {
        controller.clipboard.isPaused.toggle()
    }

    @objc private func grabText() {
        controller.grabText()
    }

    @objc private func toggleKeepAwake() {
        controller.keepAwake.toggle()
    }

    @objc private func openSettings() {
        controller.openSettings()
    }

    @objc private func toggleOpenOnHover() {
        controller.openOnHover.toggle()
    }

    @objc private func showNotesFolder() {
        NSWorkspace.shared.open(controller.store.folder)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "Move Island to your Applications folder and try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }
}
