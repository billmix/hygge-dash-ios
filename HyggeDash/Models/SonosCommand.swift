import Foundation

enum SonosCommand: String {
    case play
    case pause
    case pausePlay
    case next
    case previous
    case volumeUp
    case volumeDown

    var systemImage: String {
        switch self {
        case .play: return "play.fill"
        case .pause, .pausePlay: return "pause.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        case .volumeUp: return "speaker.plus.fill"
        case .volumeDown: return "speaker.minus.fill"
        }
    }

    /// Returns (namespace, command) for Sonos WebSocket API
    var webSocketCommand: (String, String) {
        switch self {
        case .play: return ("playback", "play")
        case .pause: return ("playback", "pause")
        case .pausePlay: return ("playback", "togglePlayPause")
        case .next: return ("playback", "skipToNextTrack")
        case .previous: return ("playback", "skipToPreviousTrack")
        case .volumeUp: return ("playerVolume", "setRelativeVolume")
        case .volumeDown: return ("playerVolume", "setRelativeVolume")
        }
    }
}

struct SonosZone: Identifiable, Codable {
    var id: String { coordinator }
    let coordinator: String
    let members: [String]
    let isPlaying: Bool?

    enum CodingKeys: String, CodingKey {
        case coordinator
        case members
        case isPlaying = "is_playing"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coordinator = try container.decode(String.self, forKey: .coordinator)
        members = try container.decodeIfPresent([String].self, forKey: .members) ?? []
        isPlaying = try container.decodeIfPresent(Bool.self, forKey: .isPlaying)
    }

    init(coordinator: String, members: [String] = [], isPlaying: Bool? = nil) {
        self.coordinator = coordinator
        self.members = members
        self.isPlaying = isPlaying
    }
}

struct SonosPlaybackState: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let isPlaying: Bool
    let volume: Int

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case album
        case isPlaying = "is_playing"
        case volume
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        isPlaying = try container.decodeIfPresent(Bool.self, forKey: .isPlaying) ?? false
        volume = try container.decodeIfPresent(Int.self, forKey: .volume) ?? 0
    }

    init(title: String? = nil, artist: String? = nil, album: String? = nil, isPlaying: Bool = false, volume: Int = 0) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.volume = volume
    }
}

struct SonosTrackInfo: Codable {
    let artist: String?
    let album: String?
    let title: String?
    let albumArt: String?
    let isPlaying: Bool

    enum CodingKeys: String, CodingKey {
        case artist
        case album
        case title
        case albumArt = "album_art"
        case playbackState = "playback_state"
    }

    init(artist: String? = nil, album: String? = nil, title: String? = nil, albumArt: String? = nil, isPlaying: Bool = false) {
        self.artist = artist
        self.album = album
        self.title = title
        self.albumArt = albumArt
        self.isPlaying = isPlaying
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        albumArt = try container.decodeIfPresent(String.self, forKey: .albumArt)

        let playbackState = try container.decodeIfPresent(String.self, forKey: .playbackState)
        isPlaying = playbackState == "PLAYING"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(albumArt, forKey: .albumArt)
        try container.encode(isPlaying ? "PLAYING" : "PAUSED", forKey: .playbackState)
    }
}
