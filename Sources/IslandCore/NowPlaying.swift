import Foundation

/// What a music app says it is playing.
public struct NowPlayingInfo: Equatable, Sendable {
    public enum Source: String, Sendable, CaseIterable {
        case music = "Music"
        case spotify = "Spotify"

        public var bundleID: String {
            switch self {
            case .music: "com.apple.Music"
            case .spotify: "com.spotify.client"
            }
        }

        /// The system-wide notification each app posts when its playback changes.
        public var notificationName: String {
            switch self {
            case .music: "com.apple.Music.playerInfo"
            case .spotify: "com.spotify.client.PlaybackStateChanged"
            }
        }
    }

    public var source: Source
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool

    public init(source: Source, title: String, artist: String = "", album: String = "", isPlaying: Bool) {
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
    }

    /// Reads the notification payload. Returns nil when playback stopped or there is no track.
    public init?(userInfo: [AnyHashable: Any]?, source: Source) {
        guard let userInfo else { return nil }
        let state = (userInfo["Player State"] as? String ?? "").lowercased()
        guard state != "stopped",
              let title = userInfo["Name"] as? String, !title.isEmpty else { return nil }
        self.init(source: source,
                  title: title,
                  artist: userInfo["Artist"] as? String ?? "",
                  album: userInfo["Album"] as? String ?? "",
                  isPlaying: state == "playing")
    }
}
