import AppKit
import IslandCore
import SwiftUI

/// A short message the pill shows for a few seconds ("Charging · 54%", a reminder going off…).
struct PillAlert: Equatable {
    var symbol: String
    var text: String
    var tint: Color
}

/// Live activities: alerts, reminders, music, calendar, battery, shelf, text grab, paste stack.
extension IslandController {
    func showAlert(symbol: String, text: String, tint: Color, seconds: Double = 3.5, sound: String? = nil) {
        alertTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            alert = PillAlert(symbol: symbol, text: text, tint: tint)
        }
        if let sound { NSSound(named: sound)?.play() }
        alertTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.alert = nil }
        }
    }

    func startLiveMonitors() {
        nowPlaying.start()
        calendar.start()
        power.start()
        audioOutput.start()

        power.onEvent = { [weak self] event in
            guard let self, self.isEnabled(.now) else { return }
            let level = self.power.percent.map { " · \($0)%" } ?? ""
            switch event {
            case .pluggedIn:
                self.showAlert(symbol: "bolt.fill", text: "Charging\(level)", tint: Theme.rest)
            case .unplugged:
                self.showAlert(symbol: "battery.75percent", text: "On battery\(level)", tint: .white)
            case .low:
                self.showAlert(symbol: "battery.25percent", text: "Battery low\(level)", tint: Theme.alert, seconds: 6)
            }
        }
        audioOutput.onChange = { [weak self] name in
            guard let self, self.isEnabled(.now) else { return }
            let symbol = name.localizedCaseInsensitiveContains("airpods") ? "airpodspro"
                : name.localizedCaseInsensitiveContains("speaker") ? "speaker.wave.2.fill" : "headphones"
            self.showAlert(symbol: symbol, text: name, tint: Theme.clipboard)
        }
    }

    /// Runs once a second alongside the focus timer.
    func tickLive() {
        for reminder in reminders.tick() {
            showAlert(symbol: "bell.fill", text: reminder.title, tint: Theme.now, seconds: 8,
                      sound: focusSound ? "Glass" : nil)
            glow()
        }

        if isEnabled(.now), let event = calendar.next, event.id != alertedEventID,
           event.start.timeIntervalSinceNow <= 60, event.end > Date() {
            alertedEventID = event.id
            showAlert(symbol: "calendar", text: "Now: \(event.title)", tint: Theme.now, seconds: 8,
                      sound: focusSound ? "Glass" : nil)
        }
    }

    // MARK: Reminders

    /// If the text reads like a reminder ("in 20 min call mom"), schedules it and returns true.
    @discardableResult
    func addReminder(from text: String) -> Bool {
        guard isEnabled(.now), let reminder = ReminderParser.parse(text) else { return false }
        reminders.add(reminder)
        let left = reminder.fireDate.timeIntervalSinceNow.shortDurationText
        showAlert(symbol: "bell.badge", text: "\(reminder.title) · in \(left)", tint: Theme.now, seconds: 2.5)
        return true
    }

    // MARK: Shelf

    func addToShelf(_ urls: [URL]) {
        guard isEnabled(.shelf), !urls.isEmpty else { return }
        let added = shelf.add(urls)
        showAlert(symbol: "tray.and.arrow.down.fill",
                  text: added == 0 ? "Already on the Shelf" : added == 1 ? "Added to Shelf" : "Added \(added) files to Shelf",
                  tint: Theme.shelf, seconds: 2)
    }

    // MARK: Grab text

    func grabText() {
        if mode == .expanded { collapse(restoreFocus: true) }
        TextGrabber.grab { [weak self] outcome in
            switch outcome {
            case .text(let text):
                // Putting it on the clipboard also lands it in clipboard history.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self?.showAlert(symbol: "text.viewfinder", text: "Copied \(text.count) characters", tint: Theme.rest)
            case .noText:
                self?.showAlert(symbol: "text.viewfinder", text: "No text found there", tint: .white)
            case .cancelled:
                break
            }
        }
    }

    // MARK: Paste stack

    /// Pastes the oldest queued copy into the frontmost app (⌃⌥B).
    func pasteNextFromStack() {
        guard isEnabled(.clipboard) else { return }
        guard let item = clipboard.popStack() else {
            showAlert(symbol: "square.stack.3d.up.slash", text: "Paste stack is empty", tint: .white, seconds: 2)
            return
        }
        clipboard.copy(item)
        let left = clipboard.stack.count
        if clipboard.canAutoPaste {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                self?.clipboard.sendPasteKeystroke()
            }
            showAlert(symbol: "square.stack.3d.up.fill", text: left == 0 ? "Stack done" : "\(left) left in stack",
                      tint: Theme.clipboard, seconds: 1.5)
        } else {
            showAlert(symbol: "square.stack.3d.up.fill", text: "Copied · press ⌘V (\(left) left)",
                      tint: Theme.clipboard, seconds: 2.5)
        }
    }
}
