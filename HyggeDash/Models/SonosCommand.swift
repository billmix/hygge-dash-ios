import Foundation

enum SonosCommand: String {
    case play
    case pause
    case pausePlay
    case next
    case previous
    case volumeUp
    case volumeDown

    var endpoint: String {
        switch self {
        case .play: return "play"
        case .pause: return "pause"
        case .pausePlay: return "pauseplay"
        case .next: return "next"
        case .previous: return "previous"
        case .volumeUp, .volumeDown: return "volume"
        }
    }

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

struct SonosTrackResponse: Codable {
    let speaker: String
    let action: String
    let args: [String]
    let exitCode: Int
    let result: String
    let errorMsg: String
    
    enum CodingKeys: String, CodingKey {
        case speaker
        case action
        case args
        case exitCode = "exit_code"
        case result
        case errorMsg = "error_msg"
    }
}

struct SonosTrackInfo: Codable {
    let artist: String?
    let album: String?
    let title: String?
    let albumArt: String?
    let playlistPosition: Int?
    let duration: String?
    let elapsed: String?
    let isPlaying: Bool

    enum CodingKeys: String, CodingKey {
        case artist
        case album
        case title
        case albumArt = "album_art"
        case playbackState = "playback_state"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        albumArt = try container.decodeIfPresent(String.self, forKey: .albumArt)

        let playbackState = try container.decodeIfPresent(String.self, forKey: .playbackState)
        isPlaying = playbackState == "PLAYING"

        // These aren't in the WebSocket payload
        playlistPosition = nil
        duration = nil
        elapsed = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(albumArt, forKey: .albumArt)
        try container.encode(isPlaying ? "PLAYING" : "PAUSED", forKey: .playbackState)
    }

    init(from response: SonosTrackResponse) {
        // Parse the result string to extract track information
        let result = response.result

        self.isPlaying = result.contains("Playback is in progress")
        self.albumArt = nil

        // Split into lines for easier parsing
        let lines = result.components(separatedBy: .newlines)

        // Extract artist
        if let artistLine = lines.first(where: { $0.contains("Artist:") }) {
            self.artist = artistLine
                .replacingOccurrences(of: "Artist:", with: "")
                .trimmingCharacters(in: .whitespaces)
        } else {
            self.artist = nil
        }

        // Extract album
        if let albumLine = lines.first(where: { $0.contains("Album:") }) {
            self.album = albumLine
                .replacingOccurrences(of: "Album:", with: "")
                .trimmingCharacters(in: .whitespaces)
        } else {
            self.album = nil
        }

        // Extract title
        if let titleLine = lines.first(where: { $0.contains("Title:") }) {
            self.title = titleLine
                .replacingOccurrences(of: "Title:", with: "")
                .trimmingCharacters(in: .whitespaces)
        } else {
            self.title = nil
        }

        // Extract playlist position
        if let positionLine = lines.first(where: { $0.contains("Playlist Position:") }) {
            let positionStr = positionLine
                .replacingOccurrences(of: "Playlist Position:", with: "")
                .trimmingCharacters(in: .whitespaces)
            self.playlistPosition = Int(positionStr)
        } else {
            self.playlistPosition = nil
        }

        // Extract duration
        if let durationLine = lines.first(where: { $0.contains("Duration:") }) {
            self.duration = durationLine
                .replacingOccurrences(of: "Duration:", with: "")
                .trimmingCharacters(in: .whitespaces)
        } else {
            self.duration = nil
        }

        // Extract elapsed time
        if let elapsedLine = lines.first(where: { $0.contains("Elapsed:") }) {
            self.elapsed = elapsedLine
                .replacingOccurrences(of: "Elapsed:", with: "")
                .trimmingCharacters(in: .whitespaces)
        } else {
            self.elapsed = nil
        }
    }
}


