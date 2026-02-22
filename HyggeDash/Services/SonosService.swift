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
    private(set) var spotifyService: SpotifyService?
    private var householdId: String?
    private var groupId: String?
    private var refreshTimer: Timer?
    private let webSocket = SonosWebSocketService()
    private var useWebSocket = false

    func configure(authService: SonosAuthService, spotifyService: SpotifyService? = nil) {
        self.authService = authService
        self.spotifyService = spotifyService
        setupWebSocketCallbacks()
    }

    // MARK: - WebSocket Integration

    private func setupWebSocketCallbacks() {
        webSocket.onPlaybackState = { [weak self] isPlaying in
            guard let self else { return }
            self.playbackState = SonosPlaybackState(
                title: self.playbackState?.title,
                artist: self.playbackState?.artist,
                album: self.playbackState?.album,
                isPlaying: isPlaying,
                volume: self.playbackState?.volume ?? 0
            )
        }

        webSocket.onMetadata = { [weak self] title, artist, album, imageUrl in
            guard let self else { return }
            self.trackInfo = SonosTrackInfo(
                artist: artist,
                album: album,
                title: title,
                albumArt: imageUrl,
                isPlaying: self.playbackState?.isPlaying ?? false
            )
            self.playbackState = SonosPlaybackState(
                title: title,
                artist: artist,
                album: album,
                isPlaying: self.playbackState?.isPlaying ?? false,
                volume: self.playbackState?.volume ?? 0
            )
        }

        webSocket.onVolume = { [weak self] volume in
            guard let self else { return }
            self.playbackState = SonosPlaybackState(
                title: self.playbackState?.title,
                artist: self.playbackState?.artist,
                album: self.playbackState?.album,
                isPlaying: self.playbackState?.isPlaying ?? false,
                volume: volume
            )
        }

        webSocket.onGroupsChanged = { [weak self] in
            Task { [weak self] in
                await self?.fetchGroups()
            }
        }
    }

    /// Connect WebSocket to the coordinator speaker of the selected zone
    private func connectWebSocket() {
        guard let zone = selectedZone,
              let coordinator = allPlayers.first(where: { $0.id == zone.coordinatorId }),
              let ip = coordinator.ip,
              let hId = householdId,
              let gId = zone.groupId else {
            print("🔌 [WS] Cannot connect: missing zone/coordinator/IP")
            return
        }

        let wsUrl = "wss://\(ip):1443/websocket/api"
        Task {
            let token = try? await authService?.refreshTokenIfNeeded()
            webSocket.connect(websocketUrl: wsUrl, householdId: hId, groupId: gId, accessToken: token)
        }
        useWebSocket = true

        // Stop polling when WebSocket is active
        stopPolling()
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

            // Parse players for display names, IPs, and store all players
            var playerNames: [String: String] = [:] // playerId -> name
            var parsedPlayers: [SonosPlayer] = []
            if let players = json["players"] as? [[String: Any]] {
                for player in players {
                    if let id = player["id"] as? String,
                       let name = player["name"] as? String {
                        playerNames[id] = name

                        // Extract IP from websocketUrl (e.g. "wss://192.168.1.25:1443/websocket/api")
                        var ip: String?
                        if let wsUrl = player["websocketUrl"] as? String,
                           let urlComponents = URLComponents(string: wsUrl) {
                            ip = urlComponents.host
                        }

                        parsedPlayers.append(SonosPlayer(id: id, name: name, ip: ip, uid: id))
                        if let ip {
                            print("🔊 [SONOS] Player: \(name) — IP: \(ip), UID: \(id)")
                        }
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
        // Route skip/prev through Spotify if authenticated (try Spotify first, fall back to Sonos)
        if let spotify = spotifyService, spotify.isAuthenticated,
           (command == .next || command == .previous) {
            let cmdName = command == .next ? "next" : "previous"
            print("🔊 [SONOS] Trying skip \(cmdName) via Spotify API first")

            // Refresh devices to find active speaker
            await spotify.fetchDevices()
            let hasActiveDevice = spotify.availableDevices.contains { $0.isActive }

            if hasActiveDevice {
                if command == .next {
                    await spotify.skipNext()
                } else {
                    await spotify.skipPrevious()
                }
                try? await Task.sleep(for: .milliseconds(500))
                await fetchPlaybackState()
                return
            } else {
                print("🔊 [SONOS] No active Spotify device, falling back to Sonos skip")
            }
        }

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

                // Parse Sonos error for user-friendly messages
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorCode = json["errorCode"] as? String {
                    switch errorCode {
                    case "ERROR_SKIP_LIMIT_REACHED":
                        errorMessage = "Skip limit reached (Spotify restriction)"
                    case "ERROR_COMMAND_FAILED":
                        errorMessage = "Command not available right now"
                    default:
                        errorMessage = errorCode.replacingOccurrences(of: "ERROR_", with: "")
                            .replacingOccurrences(of: "_", with: " ").capitalized
                    }
                    // Clear error after 3 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        if self.errorMessage != nil { self.errorMessage = nil }
                    }
                    return
                }
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
        print("🔊 [FAVS] playFavorite called for: \(favorite.name)")
        print("🔊 [FAVS] groupId: \(groupId ?? "NIL")")
        guard let gId = groupId else {
            errorMessage = "No group selected"
            print("🔊 [FAVS] ❌ No group selected, aborting")
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
        print("🔊 [STATION] playStation called for: \(station.name)")
        print("🔊 [STATION] groupId: \(groupId ?? "NIL"), householdId: \(householdId ?? "NIL")")
        print("🔊 [STATION] selectedZone: \(selectedZone?.coordinator ?? "NIL")")

        guard let gId = groupId else {
            errorMessage = "No group selected"
            print("🔊 [STATION] ❌ No group selected, aborting")
            return
        }

        print("🔊 [STATION] Playing: \(station.name) on group \(gId)")
        print("🔊 [STATION] URL: \(station.url)")

        // Detect if this is a music service share link (Spotify, Apple Music, etc.)
        if let shareLink = ShareLinkParser.parse(station.url) {
            print("🔊 [STATION] Detected \(shareLink.service) \(shareLink.type): \(shareLink.objectId)")

            // Use local UPnP for all music service links (Spotify, Apple Music, Tidal, etc.)
            await playViaMusicService(shareLink: shareLink, groupId: gId)
        } else {
            // Direct stream URL (internet radio, etc.)
            print("🔊 [STATION] Treating as direct stream URL")
            await playViaStreamUrl(station: station, groupId: gId)
        }

        // Refresh state
        try? await Task.sleep(for: .seconds(2))
        await fetchPlaybackState()
    }

    /// Play music service content via local UPnP (like soco-cli)
    private func playViaMusicService(shareLink: ShareLinkInfo, groupId gId: String) async {
        // Find the coordinator speaker's IP for the selected zone
        guard let zone = selectedZone,
              let coordinator = allPlayers.first(where: { $0.id == zone.coordinatorId }),
              let ip = coordinator.ip else {
            print("🔊 [UPnP] ❌ Cannot find coordinator IP for zone")
            errorMessage = "Cannot find speaker on local network"
            return
        }

        print("🔊 [UPnP] Playing via local UPnP: \(coordinator.name) at \(ip)")

        // Try with primary service ID, then alternatives
        let allServiceIds = [shareLink.serviceId] + shareLink.alternativeServiceIds

        for serviceId in allServiceIds {
            do {
                let linkWithServiceId = ShareLinkInfo(
                    service: shareLink.service,
                    type: shareLink.type,
                    objectId: shareLink.objectId,
                    serviceId: serviceId,
                    alternativeServiceIds: []
                )

                print("🔊 [UPnP] Trying serviceId \(serviceId)...")
                try await SonosUPnP.playShareLink(
                    speakerIP: ip,
                    speakerUID: coordinator.id,
                    shareLink: linkWithServiceId
                )
                print("🔊 [UPnP] ✅ Playback started with serviceId \(serviceId)!")
                return
            } catch {
                print("🔊 [UPnP] ❌ serviceId \(serviceId) failed: \(error)")
            }
        }

        errorMessage = "Failed to play \(shareLink.service) link"
    }

    /// Play a music service share link — tries multiple Sonos Cloud API approaches
    private func playViaLoadContent(shareLink: ShareLinkInfo, groupId gId: String) async {
        // Approach 1: Try all known service IDs with /playback/content
        let allServiceIds = [shareLink.serviceId] + shareLink.alternativeServiceIds
        for serviceId in allServiceIds {
            let success = await tryLoadContent(shareLink: shareLink, serviceId: serviceId, groupId: gId)
            if success { return }
        }

        // Approach 2: Try matching against Sonos Favorites
        if await tryMatchFavorite(shareLink: shareLink, groupId: gId) {
            return
        }

        print("🔊 [STATION] ❌ All approaches failed for \(shareLink.objectId)")
        errorMessage = "Could not play \(shareLink.service) link. Try adding it as a Sonos Favorite first."
    }

    /// Try loading content via /playback/content endpoint
    private func tryLoadContent(shareLink: ShareLinkInfo, serviceId: String, groupId gId: String) async -> Bool {
        do {
            let idObject: [String: Any] = [
                "objectId": shareLink.objectId,
                "serviceId": serviceId,
                "_objectType": "universalMusicObjectId",
            ]

            let body: [String: Any] = [
                "type": shareLink.type,
                "id": idObject,
                "playbackAction": "PLAY",
            ]

            print("🔊 [STATION] Trying /playback/content with serviceId=\(serviceId)")
            print("🔊 [STATION] Body: \(body)")

            let (data, response) = try await authorizedRequest(
                url: URL(string: "\(baseURL)/groups/\(gId)/playback/content")!,
                method: "POST",
                body: body
            )

            let responseBody = String(data: data, encoding: .utf8) ?? "nil"
            print("🔊 [STATION] Response \(response.statusCode): \(responseBody)")

            if response.statusCode == 200 {
                // 200 with {} might mean "accepted but no-op". Check if playback actually started.
                try await Task.sleep(for: .seconds(2))
                await fetchPlaybackState()

                if playbackState?.isPlaying == true {
                    print("🔊 [STATION] ✅ Playback started with serviceId=\(serviceId)")
                    return true
                } else {
                    // Try sending an explicit play command
                    print("🔊 [STATION] Content loaded but not playing, sending play command...")
                    let (_, playResponse) = try await authorizedRequest(
                        url: URL(string: "\(baseURL)/groups/\(gId)/playback/play")!,
                        method: "POST",
                        body: [:]
                    )
                    print("🔊 [STATION] Play command response: \(playResponse.statusCode)")

                    try await Task.sleep(for: .seconds(2))
                    await fetchPlaybackState()

                    if playbackState?.isPlaying == true {
                        print("🔊 [STATION] ✅ Playback started after explicit play")
                        return true
                    }
                    print("🔊 [STATION] ⚠️ Still not playing with serviceId=\(serviceId)")
                }
            }

            return false
        } catch {
            print("🔊 [STATION] ❌ Error with serviceId=\(serviceId): \(error)")
            return false
        }
    }

    /// Try to match the share link against existing Sonos Favorites and play via that
    private func tryMatchFavorite(shareLink: ShareLinkInfo, groupId gId: String) async -> Bool {
        // Make sure favorites are loaded
        if favorites.isEmpty {
            await fetchFavorites()
        }

        // Try to find a matching favorite by name or URL substring
        // Spotify playlist IDs often appear in favorite metadata
        let spotifyId = shareLink.objectId.components(separatedBy: ":").last ?? ""
        print("🔊 [STATION] Looking for favorite matching: \(spotifyId)")

        // We can't match by URL since favorites don't expose the underlying URL.
        // But we can list them for the user to see.
        if !favorites.isEmpty {
            print("🔊 [STATION] Available favorites: \(favorites.map { $0.name })")
        }

        return false
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

    // MARK: - Polling (fallback when WebSocket unavailable)

    func startPolling() {
        // Try WebSocket first
        connectWebSocket()

        // Also start polling as fallback — will be stopped if WS connects
        stopPolling()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Skip polling if WebSocket is connected
                if self.webSocket.isConnected { return }
                await self.fetchPlaybackState()
            }
        }
    }

    func stopAll() {
        stopPolling()
        webSocket.disconnect()
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

        // Reconnect WebSocket to new zone's coordinator
        connectWebSocket()

        // Also fetch current state immediately via REST
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
