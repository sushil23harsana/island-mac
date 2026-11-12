import AppKit
import IslandCore

/// Follows what Music or Spotify is playing.
///
/// Both apps broadcast a system-wide notification whenever playback changes, so showing the
/// track needs no permission at all. Only the play/skip buttons use AppleScript, which makes
/// macOS ask once for permission to control that app.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    enum Command: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    @Published private(set) var info: NowPlayingInfo?
    private var observers: [NSObjectProtocol] = []

    func start() {
        for source in NowPlayingInfo.Source.allCases {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(source.notificationName), object: nil, queue: .main
            ) { [weak self] note in
                let parsed = NowPlayingInfo(userInfo: note.userInfo, source: source)
                MainActor.assumeIsolated { self?.update(parsed, from: source) }
            }
            observers.append(token)
        }

        // When the player quits, stop showing its track.
        let quit = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if let self, self.info?.source.bundleID == bundleID { self.info = nil }
            }
        }
        observers.append(quit)
    }

    private func update(_ parsed: NowPlayingInfo?, from source: NowPlayingInfo.Source) {
        if let parsed {
            // A paused player shouldn't replace another one that is actually playing.
            if !parsed.isPlaying, let current = info, current.source != source, current.isPlaying { return }
            info = parsed
        } else if info?.source == source {
            info = nil
        }
    }

    func send(_ command: Command) {
        guard let info else { return }
        // Flip the button right away; the player's own notification confirms it a moment later.
        if command == .playPause { self.info?.isPlaying.toggle() }
        let script = NSAppleScript(source: "tell application \"\(info.source.rawValue)\" to \(command.rawValue)")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error != nil, command == .playPause { self.info?.isPlaying.toggle() }
    }

    #if DEBUG
    func setForSnapshot(_ info: NowPlayingInfo?) { self.info = info }
    #endif
}
