import IslandCore
import ServiceManagement
import SwiftUI

/// Settings, shown inside the island in place of the current tab (gear button or ⌘,).
struct SettingsView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var monitor: ClipboardMonitor
    @EnvironmentObject private var store: NotesStore

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var canAutoPaste = false

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    modules
                    general
                }
                VStack(spacing: 12) {
                    moduleOptions
                    about
                }
            }
        }
        .scrollIndicators(.never)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { canAutoPaste = monitor.canAutoPaste }
    }

    // MARK: Sections

    private var modules: some View {
        SettingsCard(title: "Modules") {
            ForEach(IslandController.Tab.allCases, id: \.self) { tab in
                let isOn = controller.isEnabled(tab)
                let isLastOne = isOn && controller.visibleTabs.count == 1
                SettingRow(symbol: tab.symbol, tint: tab.accent, title: tab.rawValue,
                           detail: isLastOne ? "At least one module stays on" : tab.summary) {
                    Toggle("", isOn: Binding(get: { isOn },
                                             set: { controller.setEnabled(tab, $0) }))
                        .disabled(isLastOne)
                }
            }
        }
    }

    private var general: some View {
        SettingsCard(title: "General") {
            SettingRow(symbol: "cursorarrow.motionlines", title: "Open on hover",
                       detail: "Rest the mouse on the pill to open") {
                Toggle("", isOn: $controller.openOnHover)
            }
            SettingRow(symbol: "power", title: "Launch at login",
                       detail: launchError ?? "Start Island when you log in") {
                Toggle("", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            }
            if controller.isEnabled(.notes) {
                SettingRow(symbol: "folder", title: "Notes folder",
                           detail: store.folder.path.replacingOccurrences(
                               of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")) {
                    LinkButton("Show") { NSWorkspace.shared.open(store.folder) }
                }
            }
        }
    }

    private var moduleOptions: some View {
        SettingsCard(title: "Options") {
            if controller.isEnabled(.focus) {
                SettingRow(symbol: "speaker.wave.2", title: "Timer sound",
                           detail: "Chime when a block or break ends") {
                    Toggle("", isOn: $controller.focusSound)
                }
            }
            if controller.isEnabled(.clipboard) {
                SettingRow(symbol: "clock.arrow.circlepath", title: "History size",
                           detail: "Items to keep") {
                    Picker("", selection: $controller.clipboardLimit) {
                        ForEach(IslandController.clipboardLimitChoices, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 124)
                }
                SettingRow(symbol: "arrow.turn.down.left", title: "Auto-paste",
                           detail: canAutoPaste ? "On: ⏎ pastes into your app" : "Needs Accessibility permission") {
                    if canAutoPaste {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.rest)
                    } else {
                        LinkButton("Allow…") { monitor.requestAutoPastePermission() }
                    }
                }
            }
        }
    }

    private var about: some View {
        SettingsCard(title: "Shortcuts") {
            ShortcutRow(keys: "⌥ Space", label: "Open or close Island")
            if controller.isEnabled(.clipboard) {
                ShortcutRow(keys: "⌃ ⌥ V", label: "Clipboard history")
            }
            if controller.isEnabled(.clipboard) {
                ShortcutRow(keys: "⌃ ⌥ B", label: "Paste next from stack")
            }
            if controller.isEnabled(.now) {
                ShortcutRow(keys: "⌃ ⌥ T", label: "Grab text from screen")
            }
            ShortcutRow(keys: "⌘ ,", label: "Settings")
            HStack {
                Text("Island \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                LinkButton("Quit Island") { NSApp.terminate(nil) }
            }
            .padding(.top, 2)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Move Island to Applications first"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private extension IslandController.Tab {
    var summary: String {
        switch self {
        case .notes: "Quick capture and Markdown notes"
        case .focus: "Pomodoro timer in the pill"
        case .clipboard: "Remember what you copy"
        case .shelf: "Park files, drag them out later"
        case .now: "Music, meetings, reminders, alerts"
        case .ports: "See and stop local servers"
        }
    }
}

// MARK: - Building blocks

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }
}

private struct SettingRow<Control: View>: View {
    let symbol: String
    var tint: Color = .white.opacity(0.7)
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            control
                .toggleStyle(.switch)
                .tint(Theme.clipboard)
                .controlSize(.mini)
                .labelsHidden()
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let label: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.1)))
        }
    }
}

struct LinkButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
