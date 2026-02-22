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

    /// Returns (endpoint URL, optional body) for Sonos Cloud REST API
    func restEndpoint(groupId: String, baseURL: String) -> (String, [String: Any]?) {
        switch self {
        case .play:
            return ("\(baseURL)/groups/\(groupId)/playback/play", nil)
        case .pause:
            return ("\(baseURL)/groups/\(groupId)/playback/pause", nil)
        case .pausePlay:
            return ("\(baseURL)/groups/\(groupId)/playback/togglePlayPause", nil)
        case .next:
            return ("\(baseURL)/groups/\(groupId)/playback/skipToNextTrack", nil)
        case .previous:
            return ("\(baseURL)/groups/\(groupId)/playback/skipToPreviousTrack", nil)
        case .volumeUp:
            return ("\(baseURL)/groups/\(groupId)/groupVolume/relative", ["volumeDelta": 5])
        case .volumeDown:
            return ("\(baseURL)/groups/\(groupId)/groupVolume/relative", ["volumeDelta": -5])
        }
    }
}

struct SonosPlayer: Identifiable {
    let id: String
    let name: String
    let ip: String?      // Extracted from websocketUrl for local UPnP access
    let uid: String?     // RINCON_xxx player ID, used as UPnP device UID
}

struct SonosFavorite: Identifiable {
    let id: String
    let name: String
    let description: String?
    let imageUrl: String?
    let service: String?
}

struct SonosZone: Identifiable {
    var id: String { groupId ?? coordinator }
    let coordinator: String
    let coordinatorId: String
    let members: [String]
    let memberIds: [String]
    let groupId: String?

    var isGroup: Bool { memberIds.count > 1 }

    init(coordinator: String, coordinatorId: String = "", members: [String] = [], memberIds: [String] = [], groupId: String? = nil) {
        self.coordinator = coordinator
        self.coordinatorId = coordinatorId
        self.members = members
        self.memberIds = memberIds
        self.groupId = groupId
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
