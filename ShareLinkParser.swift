import Foundation

/// Parsed share link info for Sonos loadContent API
struct ShareLinkInfo {
    let service: String          // "Spotify", "Apple Music", "Tidal"
    let type: String             // "track", "album", "playlist", "show", "episode"
    let objectId: String         // e.g. "spotify:playlist:37i9dQZF1E4slpGebPnVno"
    let serviceId: String        // Primary service ID to try
    let alternativeServiceIds: [String]  // Fallback service IDs
}

/// Parses music service URLs into Sonos-compatible identifiers
enum ShareLinkParser {

    static func parse(_ urlString: String) -> ShareLinkInfo? {
        if let info = parseSpotify(urlString) { return info }
        if let info = parseAppleMusic(urlString) { return info }
        if let info = parseTidal(urlString) { return info }
        if let info = parseDeezer(urlString) { return info }
        return nil
    }

    // MARK: - Spotify

    /// Matches:
    /// - https://open.spotify.com/playlist/37i9dQZF1E4slpGebPnVno
    /// - https://open.spotify.com/track/abc123?si=...
    /// - https://open.spotify.com/album/xyz789
    /// - spotify:track:abc123
    private static func parseSpotify(_ urlString: String) -> ShareLinkInfo? {
        // Pattern matches both URLs and URIs
        let pattern = #"spotify.*[:/](album|episode|playlist|show|track)[:/](\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let typeRange = Range(match.range(at: 1), in: urlString),
              let idRange = Range(match.range(at: 2), in: urlString) else {
            return nil
        }

        let type = String(urlString[typeRange])
        let id = String(urlString[idRange])
        let objectId = "spotify:\(type):\(id)"

        return ShareLinkInfo(
            service: "Spotify",
            type: type,
            objectId: objectId,
            serviceId: "2311",                          // Spotify EU
            alternativeServiceIds: ["3079", "12", "9"]  // Spotify US, other known IDs
        )
    }

    // MARK: - Apple Music

    /// Matches:
    /// - https://music.apple.com/us/album/album-name/123456789
    /// - https://music.apple.com/us/playlist/playlist-name/pl.abc123
    private static func parseAppleMusic(_ urlString: String) -> ShareLinkInfo? {
        let pattern = #"music\.apple\.com/\w+/(album|playlist|station)/[^/]+/([^\?]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let typeRange = Range(match.range(at: 1), in: urlString),
              let idRange = Range(match.range(at: 2), in: urlString) else {
            return nil
        }

        let type = String(urlString[typeRange])
        let id = String(urlString[idRange])

        return ShareLinkInfo(
            service: "Apple Music",
            type: type,
            objectId: id,
            serviceId: "204",
            alternativeServiceIds: ["52"]
        )
    }

    // MARK: - Tidal

    /// Matches:
    /// - https://tidal.com/browse/album/157273956
    /// - https://tidal.com/browse/track/123456
    /// - https://tidal.com/browse/playlist/uuid
    private static func parseTidal(_ urlString: String) -> ShareLinkInfo? {
        let pattern = #"tidal.*[:/](album|track|playlist)[:/]([\w-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let typeRange = Range(match.range(at: 1), in: urlString),
              let idRange = Range(match.range(at: 2), in: urlString) else {
            return nil
        }

        let type = String(urlString[typeRange])
        let id = String(urlString[idRange])

        return ShareLinkInfo(
            service: "TIDAL",
            type: type,
            objectId: "tidal:\(type):\(id)",
            serviceId: "44551",
            alternativeServiceIds: []
        )
    }

    // MARK: - Deezer

    private static func parseDeezer(_ urlString: String) -> ShareLinkInfo? {
        let pattern = #"deezer.*[:/](album|track|playlist)[:/]([\w-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let typeRange = Range(match.range(at: 1), in: urlString),
              let idRange = Range(match.range(at: 2), in: urlString) else {
            return nil
        }

        let type = String(urlString[typeRange])
        let id = String(urlString[idRange])

        return ShareLinkInfo(
            service: "Deezer",
            type: type,
            objectId: "deezer:\(type):\(id)",
            serviceId: "519",
            alternativeServiceIds: []
        )
    }
}
