import Foundation
import Combine

@MainActor
class SonosService: ObservableObject {
    @Published var zones: [SonosZone] = []
    @Published var allPlayers: [SonosPlayer] = []
    @Published var selectedZone: SonosZone?
    @Published var playbackState: SonosPlaybackState?
    @Published var trackInfo: SonosTrackInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let baseURL = "https://api.ws.sonos.com/control/api/v1"
    private var authService: SonosAuthService?
    private var householdId: String?
    private var groupId: String?
    private var refreshTimer: Timer?

    func configure(authService: SonosAuthService) {
        self.authService = authService
    }

    // MARK: - API Helpers

    private func authorizedRequest(url: URL, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let token = try await authService?.refreshTokenIfNeeded() else {
            throw SonosAPIError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SonosAPIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw SonosAPIError.notAuthenticated
        }

        return (data, httpResponse)
    }

    // MARK: - Discovery via Cloud API

    func fetchSpeakers() async {
        isLoading = true
        errorMessage = nil

        do {
            // Step 1: Get households
            let (householdData, _) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/households")!
            )

            guard let householdJSON = try JSONSerialization.jsonObject(with: householdData) as? [String: Any],
                  let households = householdJSON["households"] as? [[String: Any]],
                  let firstHousehold = households.first,
                  let hId = firstHousehold["id"] as? String else {
                print("🔊 [SONOS] No households found")
                errorMessage = "No Sonos households found. Check your account."
                isLoading = false
                return
            }

            householdId = hId
            print("🔊 [SONOS] Found household: \(hId)")

            // Step 2: Get groups (which includes players)
            await fetchGroups()

            isLoading = false
        } catch SonosAPIError.notAuthenticated {
            errorMessage = "Not authenticated. Please connect your Sonos account in Settings."
            isLoading = false
        } catch {
            print("🔊 [SONOS] Error fetching speakers: \(error)")
            errorMessage = "Failed to connect to Sonos: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func fetchGroups() async {
        guard let hId = householdId else { return }

        do {
            let (data, _) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/households/\(hId)/groups")!
            )

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            print("🔊 [SONOS] Groups response: \(String(data: data, encoding: .utf8)?.prefix(1000) ?? "nil")")

            // Parse players for display names and store all players
            var playerNames: [String: String] = [:] // playerId -> name
            var parsedPlayers: [SonosPlayer] = []
            if let players = json["players"] as? [[String: Any]] {
                for player in players {
                    if let id = player["id"] as? String,
                       let name = player["name"] as? String {
                        playerNames[id] = name
                        parsedPlayers.append(SonosPlayer(id: id, name: name))
                    }
                }
            }
            allPlayers = parsedPlayers
            print("🔊 [SONOS] All players: \(parsedPlayers.map { $0.name })")

            // Parse groups
            if let groups = json["groups"] as? [[String: Any]] {
                var newZones: [SonosZone] = []

                for group in groups {
                    guard let gId = group["id"] as? String else { continue }

                    // Get the group's coordinator player name
                    let coordId = group["coordinatorId"] as? String ?? ""
                    let coordinatorName = playerNames[coordId] ?? group["name"] as? String ?? "Unknown Room"

                    // Get member IDs and names
                    let mIds = group["playerIds"] as? [String] ?? []
                    let memberNames = mIds.compactMap { playerNames[$0] }

                    let zone = SonosZone(
                        coordinator: coordinatorName,
                        coordinatorId: coordId,
                        members: memberNames,
                        memberIds: mIds,
                        groupId: gId
                    )
                    newZones.append(zone)
                    print("🔊 [SONOS] Found group: \(coordinatorName) (id: \(gId), members: \(memberNames))")
                }

                zones = newZones

                // Auto-select first group or preserve selection
                if let selected = selectedZone,
                   let updated = newZones.first(where: { $0.groupId == selected.groupId }) {
                    selectedZone = updated
                } else {
                    selectedZone = newZones.first(where: { $0.coordinator == "Living Room" }) ?? newZones.first
                }

                // Set the active groupId
                groupId = selectedZone?.groupId
                print("🔊 [SONOS] Selected group: \(selectedZone?.coordinator ?? "none") (id: \(groupId ?? "nil"))")
            }
        } catch {
            print("🔊 [SONOS] Error fetching groups: \(error)")
        }
    }

    // MARK: - Playback State

    func fetchPlaybackState() async {
        guard let gId = groupId else {
            print("🔊 [SONOS] Cannot fetch playback state: no group selected")
            return
        }

        do {
            // Fetch playback state
            let (playbackData, _) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/groups/\(gId)/playback")!
            )

            if let json = try JSONSerialization.jsonObject(with: playbackData) as? [String: Any] {
                let isPlaying = (json["playbackState"] as? String) == "PLAYBACK_STATE_PLAYING"
                let currentVolume = playbackState?.volume ?? 0

                playbackState = SonosPlaybackState(
                    title: playbackState?.title,
                    artist: playbackState?.artist,
                    album: playbackState?.album,
                    isPlaying: isPlaying,
                    volume: currentVolume
                )
            }

            // Fetch playback metadata (track info)
            let (metadataData, _) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/groups/\(gId)/playbackMetadata")!
            )

            if let json = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
                var title: String?
                var artist: String?
                var album: String?
                var imageUrl: String?

                if let container = json["container"] as? [String: Any] {
                    title = container["name"] as? String
                    if let imageUrlVal = container["imageUrl"] as? String {
                        imageUrl = imageUrlVal
                    }
                }

                if let currentItem = json["currentItem"] as? [String: Any],
                   let track = currentItem["track"] as? [String: Any] {
                    title = track["name"] as? String ?? title
                    artist = (track["artist"] as? [String: Any])?["name"] as? String
                    album = (track["album"] as? [String: Any])?["name"] as? String
                    if let trackImageUrl = track["imageUrl"] as? String {
                        imageUrl = trackImageUrl
                    }
                }

                let isPlaying = playbackState?.isPlaying ?? false

                trackInfo = SonosTrackInfo(
                    artist: artist,
                    album: album,
                    title: title,
                    albumArt: imageUrl,
                    isPlaying: isPlaying
                )

                playbackState = SonosPlaybackState(
                    title: title,
                    artist: artist,
                    album: album,
                    isPlaying: isPlaying,
                    volume: playbackState?.volume ?? 0
                )
            }

            // Fetch volume
            let (volumeData, _) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/groups/\(gId)/groupVolume")!
            )

            if let json = try JSONSerialization.jsonObject(with: volumeData) as? [String: Any],
               let volume = json["volume"] as? Int {
                playbackState = SonosPlaybackState(
                    title: playbackState?.title,
                    artist: playbackState?.artist,
                    album: playbackState?.album,
                    isPlaying: playbackState?.isPlaying ?? false,
                    volume: volume
                )
            }

        } catch {
            print("🔊 [SONOS] Error fetching playback state: \(error)")
        }
    }

    // MARK: - Commands

    func sendCommand(_ command: SonosCommand) async {
        guard let gId = groupId else {
            errorMessage = "No group selected"
            print("🔊 [SONOS] Cannot send command: no group selected")
            return
        }

        do {
            let (endpoint, body) = command.restEndpoint(groupId: gId, baseURL: baseURL)
            print("🔊 [SONOS] Sending command: \(command.rawValue) to \(endpoint)")

            let (data, response) = try await authorizedRequest(
                url: URL(string: endpoint)!,
                method: "POST",
                body: body
            )

            print("🔊 [SONOS] Command response: \(response.statusCode)")
            if response.statusCode >= 400 {
                let responseBody = String(data: data, encoding: .utf8) ?? "nil"
                print("🔊 [SONOS] Command error body: \(responseBody)")
            }

            // Refresh state after command
            try? await Task.sleep(for: .milliseconds(500))
            await fetchPlaybackState()
        } catch {
            print("🔊 [SONOS] Command error: \(error)")
            errorMessage = "Command failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Volume

    func setVolume(_ volume: Int) async {
        guard let gId = groupId else { return }

        let clamped = max(0, min(100, volume))
        do {
            let _ = try await authorizedRequest(
                url: URL(string: "\(baseURL)/groups/\(gId)/groupVolume")!,
                method: "POST",
                body: ["volume": clamped]
            )
        } catch {
            print("🔊 [SONOS] Volume error: \(error)")
        }
    }

    func setGroupVolume(to targetVolume: Int) async {
        await setVolume(targetVolume)
    }

    // MARK: - Sonos Favorites

    @Published var favorites: [SonosFavorite] = []

    func fetchFavorites() async {
        guard let hId = householdId else {
            print("🔊 [FAVS] No household ID")
            return
        }

        do {
            let (data, response) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/households/\(hId)/favorites")!
            )

            print("🔊 [FAVS] Response: \(response.statusCode)")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                print("🔊 [FAVS] No items found")
                return
            }

            favorites = items.compactMap { item in
                guard let id = item["id"] as? String,
                      let name = item["name"] as? String else { return nil }
                let description = item["description"] as? String
                let imageUrl = item["imageUrl"] as? String
                let service = (item["service"] as? [String: Any])?["name"] as? String
                print("🔊 [FAVS] Found: \(name) (id: \(id), service: \(service ?? "unknown"))")
                return SonosFavorite(id: id, name: name, description: description, imageUrl: imageUrl, service: service)
            }

            print("🔊 [FAVS] Total favorites: \(favorites.count)")
        } catch {
            print("🔊 [FAVS] Error: \(error)")
        }
    }

    func playFavorite(_ favorite: SonosFavorite) async {
        guard let gId = groupId else {
            errorMessage = "No group selected"
            return
        }

        do {
            print("🔊 [FAVS] Playing favorite: \(favorite.name) (id: \(favorite.id)) on group: \(gId)")

            let (data, response) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/groups/\(gId)/favorites")!,
                method: "POST",
                body: [
                    "favoriteId": favorite.id,
                    "playOnCompletion": true,
                    "action": "REPLACE",
                ]
            )

            print("🔊 [FAVS] Play response: \(response.statusCode)")
            print("🔊 [FAVS] Play body: \(String(data: data, encoding: .utf8) ?? "nil")")

            // Refresh state
            try? await Task.sleep(for: .seconds(2))
            await fetchPlaybackState()
        } catch {
            print("🔊 [FAVS] Play error: \(error)")
            errorMessage = "Failed to play: \(error.localizedDescription)"
        }
    }

    // MARK: - Station Playback

    func playStation(_ station: Station) async {
        guard let gId = groupId else {
            errorMessage = "No group selected"
            return
        }

        print("🔊 [STATION] Playing: \(station.name) on group \(gId)")
        print("🔊 [STATION] URL: \(station.url)")

        // Detect if this is a music service share link (Spotify, Apple Music, etc.)
        if let shareLink = ShareLinkParser.parse(station.url) {
            print("🔊 [STATION] Detected \(shareLink.service) \(shareLink.type): \(shareLink.objectId)")
            await playViaLoadContent(shareLink: shareLink, groupId: gId)
        } else {
            // Direct stream URL (internet radio, etc.)
            print("🔊 [STATION] Treating as direct stream URL")
            await playViaStreamUrl(station: station, groupId: gId)
        }

        // Refresh state
        try? await Task.sleep(for: .seconds(2))
        await fetchPlaybackState()
    }

    /// Play a music service share link via loadContent
    private func playViaLoadContent(shareLink: ShareLinkInfo, groupId gId: String) async {
        do {
            // First, look up the music service account to get the right serviceId/accountId
            let serviceAccounts = await fetchMusicServiceAccounts()
            let accountId = serviceAccounts.first(where: {
                $0.service.lowercased().contains(shareLink.service.lowercased())
            })?.accountId

            var idObject: [String: Any] = [
                "objectId": shareLink.objectId,
                "serviceId": shareLink.serviceId,
                "_objectType": "universalMusicObjectId",
            ]
            if let accountId {
                idObject["accountId"] = accountId
                print("🔊 [STATION] Found account ID: \(accountId) for \(shareLink.service)")
            }

            let body: [String: Any] = [
                "type": shareLink.type,
                "id": idObject,
                "playbackAction": "PLAY",
            ]

            print("🔊 [STATION] loadContent body: \(body)")

            let (data, response) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/groups/\(gId)/playback/content")!,
                method: "POST",
                body: body
            )

            let responseBody = String(data: data, encoding: .utf8) ?? "nil"
            print("🔊 [STATION] loadContent response: \(response.statusCode)")
            print("🔊 [STATION] loadContent body: \(responseBody)")

            if response.statusCode >= 400 {
                print("🔊 [STATION] ❌ loadContent failed, trying alternative serviceId...")
                // Try with alternative service IDs (Spotify has multiple: 2311, 3079, 12)
                for altServiceId in shareLink.alternativeServiceIds {
                    var altIdObject = idObject
                    altIdObject["serviceId"] = altServiceId
                    let altBody: [String: Any] = [
                        "type": shareLink.type,
                        "id": altIdObject,
                        "playbackAction": "PLAY",
                    ]

                    let (altData, altResponse) = try await authorizedRequest(
                        url: URL(string: "\(baseURL)/groups/\(gId)/playback/content")!,
                        method: "POST",
                        body: altBody
                    )
                    print("🔊 [STATION] Alt serviceId \(altServiceId) response: \(altResponse.statusCode)")
                    print("🔊 [STATION] Alt body: \(String(data: altData, encoding: .utf8) ?? "nil")")

                    if altResponse.statusCode < 400 {
                        print("🔊 [STATION] ✅ Success with serviceId \(altServiceId)")
                        return
                    }
                }
                errorMessage = "Failed to play content: \(responseBody)"
            }
        } catch {
            print("🔊 [STATION] ❌ loadContent error: \(error)")
            errorMessage = "Failed to play: \(error.localizedDescription)"
        }
    }

    /// Play a direct stream URL via playbackSession
    private func playViaStreamUrl(station: Station, groupId gId: String) async {
        let clientId = Bundle.main.infoDictionary?["SonosClientID"] as? String ?? ""

        do {
            let sessionURL = "\(baseURL)/groups/\(gId)/playbackSession/joinOrCreate"
            let (sessionData, sessionResponse) = try await authorizedRequest(
                url: URL(string: sessionURL)!,
                method: "POST",
                body: ["appId": clientId, "appContext": station.name]
            )

            print("🔊 [STATION] Session response: \(sessionResponse.statusCode)")

            guard sessionResponse.statusCode == 200,
                  let sessionJSON = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any],
                  let sessionId = sessionJSON["sessionId"] as? String else {
                print("🔊 [STATION] ❌ Failed to create session: \(String(data: sessionData, encoding: .utf8) ?? "nil")")
                return
            }

            let loadURL = "\(baseURL)/playbackSessions/\(sessionId)/playbackSession/loadStreamUrl"
            let (loadData, loadResponse) = try await authorizedRequest(
                url: URL(string: loadURL)!,
                method: "POST",
                body: [
                    "streamUrl": station.url,
                    "itemId": station.url,
                    "stationMetadata": ["name": station.name],
                    "playOnCompletion": true,
                ]
            )

            print("🔊 [STATION] loadStreamUrl response: \(loadResponse.statusCode)")
            if loadResponse.statusCode >= 400 {
                print("🔊 [STATION] ❌ loadStreamUrl error: \(String(data: loadData, encoding: .utf8) ?? "nil")")
            }
        } catch {
            print("🔊 [STATION] ❌ Stream error: \(error)")
            errorMessage = "Failed to play stream: \(error.localizedDescription)"
        }
    }

    // MARK: - Music Service Accounts

    private struct MusicServiceAccount {
        let service: String
        let accountId: String
        let serviceId: String
    }

    private func fetchMusicServiceAccounts() async -> [MusicServiceAccount] {
        guard let hId = householdId else { return [] }

        do {
            let (data, _) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/households/\(hId)/musicServiceAccounts")!
            )

            let responseStr = String(data: data, encoding: .utf8) ?? "nil"
            print("🔊 [STATION] Music service accounts: \(responseStr.prefix(1000))")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accounts = json["accounts"] as? [[String: Any]] else { return [] }

            return accounts.compactMap { account in
                guard let service = (account["service"] as? [String: Any])?["name"] as? String,
                      let accountId = account["id"] as? String else { return nil }
                let serviceId = (account["service"] as? [String: Any])?["id"] as? String ?? ""
                return MusicServiceAccount(service: service, accountId: accountId, serviceId: serviceId)
            }
        } catch {
            print("🔊 [STATION] Failed to fetch music service accounts: \(error)")
            return []
        }
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchPlaybackState()
            }
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Zone Selection

    func selectZone(_ zone: SonosZone) {
        selectedZone = zone
        groupId = zone.groupId
        print("🔊 [SONOS] Selected zone: \(zone.coordinator) (group: \(zone.groupId ?? "nil"))")

        // Fetch new state for this group
        Task {
            await fetchPlaybackState()
        }
    }

    // MARK: - Grouping

    /// Add a player to an existing group
    func addPlayerToGroup(playerId: String, groupId targetGroupId: String) async {
        do {
            print("🔊 [GROUP] Adding player \(playerId) to group \(targetGroupId)")
            let (data, response) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/groups/\(targetGroupId)/groups/modifyGroupMembers")!,
                method: "POST",
                body: [
                    "playerIdsToAdd": [playerId],
                    "playerIdsToRemove": [],
                ]
            )
            print("🔊 [GROUP] Add response: \(response.statusCode)")
            if response.statusCode >= 400 {
                print("🔊 [GROUP] Add error: \(String(data: data, encoding: .utf8) ?? "nil")")
            }
            // Refresh groups after modification
            await fetchGroups()
        } catch {
            print("🔊 [GROUP] Add error: \(error)")
            errorMessage = "Failed to group speakers: \(error.localizedDescription)"
        }
    }

    /// Remove a player from its current group (ungroup it)
    func removePlayerFromGroup(playerId: String, groupId sourceGroupId: String) async {
        do {
            print("🔊 [GROUP] Removing player \(playerId) from group \(sourceGroupId)")
            let (data, response) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/groups/\(sourceGroupId)/groups/modifyGroupMembers")!,
                method: "POST",
                body: [
                    "playerIdsToAdd": [],
                    "playerIdsToRemove": [playerId],
                ]
            )
            print("🔊 [GROUP] Remove response: \(response.statusCode)")
            if response.statusCode >= 400 {
                print("🔊 [GROUP] Remove error: \(String(data: data, encoding: .utf8) ?? "nil")")
            }
            // Refresh groups after modification
            await fetchGroups()
        } catch {
            print("🔊 [GROUP] Remove error: \(error)")
            errorMessage = "Failed to ungroup speaker: \(error.localizedDescription)"
        }
    }

    /// Create a new group from a set of player IDs
    func createGroup(playerIds: [String]) async {
        guard let hId = householdId else { return }

        do {
            print("🔊 [GROUP] Creating group with players: \(playerIds)")
            let (data, response) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/households/\(hId)/groups/createGroup")!,
                method: "POST",
                body: ["playerIds": playerIds]
            )
            print("🔊 [GROUP] Create response: \(response.statusCode)")
            if response.statusCode >= 400 {
                print("🔊 [GROUP] Create error: \(String(data: data, encoding: .utf8) ?? "nil")")
            }
            await fetchGroups()
        } catch {
            print("🔊 [GROUP] Create error: \(error)")
            errorMessage = "Failed to create group: \(error.localizedDescription)"
        }
    }

    /// Get players not in the currently selected group
    func playersNotInGroup(_ zone: SonosZone) -> [SonosPlayer] {
        allPlayers.filter { player in
            !zone.memberIds.contains(player.id)
        }
    }

    // MARK: - Errors

    enum SonosAPIError: LocalizedError {
        case notAuthenticated
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not authenticated. Please connect your Sonos account."
            case .invalidResponse: return "Invalid response from Sonos."
            }
        }
    }
}
