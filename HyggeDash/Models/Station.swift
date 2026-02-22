import Foundation

enum StationSource: String, Codable, CaseIterable {
    case spotify = "spotify"
    case appleMusic = "apple_music"
    case tidal = "tidal"
    case deezer = "deezer"
    case stream = "stream"

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .tidal: return "TIDAL"
        case .deezer: return "Deezer"
        case .stream: return "Stream"
        }
    }

    var iconName: String {
        switch self {
        case .spotify: return "dot.radiowaves.left.and.right"
        case .appleMusic: return "apple.logo"
        case .tidal: return "waveform"
        case .deezer: return "waveform.circle"
        case .stream: return "antenna.radiowaves.left.and.right"
        }
    }

    var accentColorName: String {
        switch self {
        case .spotify: return "spotify"     // green
        case .appleMusic: return "apple"    // pink/red
        case .tidal: return "tidal"         // blue
        case .deezer: return "deezer"       // purple
        case .stream: return "stream"       // default accent
        }
    }

    /// Detect source from a URL string
    static func detect(from url: String) -> StationSource {
        let lower = url.lowercased()
        if lower.contains("spotify.com") || lower.hasPrefix("spotify:") {
            return .spotify
        } else if lower.contains("music.apple.com") {
            return .appleMusic
        } else if lower.contains("tidal.com") || lower.hasPrefix("tidal:") {
            return .tidal
        } else if lower.contains("deezer.com") || lower.hasPrefix("deezer:") {
            return .deezer
        }
        return .stream
    }
}

/// Content type hint for music service links
enum StationContentType: String, Codable {
    case track
    case album
    case playlist
    case show
    case episode
    case station
    case unknown
}

struct Station: Identifiable, Codable, Hashable {
    let id: String  // String UUID for cross-process compatibility with Share Extension
    var name: String
    var url: String
    var source: StationSource
    var contentType: StationContentType
    var addedAt: String  // ISO8601 string for cross-process compatibility

    init(id: String? = nil, name: String, url: String, source: StationSource? = nil, contentType: StationContentType? = nil) {
        self.id = id ?? UUID().uuidString
        self.name = name
        self.url = url
        self.source = source ?? StationSource.detect(from: url)
        self.addedAt = ISO8601DateFormatter().string(from: Date())

        // Auto-detect content type from URL
        if let ct = contentType {
            self.contentType = ct
        } else if let parsed = ShareLinkParser.parse(url) {
            self.contentType = StationContentType(rawValue: parsed.type) ?? .unknown
        } else {
            self.contentType = .station
        }
    }

    /// Subtitle for display
    var subtitle: String {
        if source == .stream {
            return url
        }
        var parts: [String] = [source.displayName]
        if contentType != .unknown {
            parts.append(contentType.rawValue.capitalized)
        }
        return parts.joined(separator: " · ")
    }
}
