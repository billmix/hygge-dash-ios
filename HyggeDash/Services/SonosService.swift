import Foundation
import Network
import Combine

@MainActor
class SonosService: ObservableObject {
    @Published var zones: [SonosZone] = []
    @Published var selectedZone: SonosZone?
    @Published var playbackState: SonosPlaybackState?
    @Published var trackInfo: SonosTrackInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let webSocketService = SonosWebSocketService()
    private var browser: NWBrowser?
    private var discoveredIP: String?
    private var householdId: String?
    private var groupId: String?
    private var refreshTimer: Timer?
    private var authService: SonosAuthService?

    func configure(authService: SonosAuthService) {
        self.authService = authService
    }

    // MARK: - Discovery

    func fetchSpeakers() async {
        isLoading = true
        errorMessage = nil

        // Use Bonjour to discover Sonos speakers on the local network
        let browser = NWBrowser(for: .bonjour(type: "_sonos._tcp", domain: nil), using: .tcp)
        self.browser = browser

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor [weak self] in
                    guard let self, !resumed else { return }

                    for result in results {
                        if case .service(let name, _, _, _) = result.endpoint {
                            // Resolve the service to get the IP
                            let zone = SonosZone(coordinator: name, members: [name])
                            if !self.zones.contains(where: { $0.coordinator == name }) {
                                self.zones.append(zone)
                            }
                        }
                    }

                    // Resolve first result to get an IP for WebSocket
                    if let first = results.first {
                        self.resolveEndpoint(first.endpoint)
                    }

                    if self.selectedZone == nil {
                        self.selectedZone = self.zones.first(where: { $0.coordinator == "Living Room" }) ?? self.zones.first
                    }

                    resumed = true
                    self.isLoading = false
                    continuation.resume()
                }
            }

            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    if case .failed(let error) = state {
                        self?.errorMessage = "Discovery failed: \(error.localizedDescription)"
                        self?.isLoading = false
                        if !resumed {
                            resumed = true
                            continuation.resume()
                        }
                    }
                }
            }

            browser.start(queue: .main)

            // Timeout after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                if !resumed {
                    resumed = true
                    await MainActor.run {
                        self.isLoading = false
                        if self.zones.isEmpty {
                            self.errorMessage = "No Sonos speakers found on the network."
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, _) = innerEndpoint {
                    let ip: String
                    switch host {
                    case .ipv4(let addr):
                        ip = "\(addr)"
                    case .ipv6(let addr):
                        ip = "\(addr)"
                    default:
                        connection.cancel()
                        return
                    }
                    Task { @MainActor [weak self] in
                        self?.discoveredIP = ip
                        self?.connectWebSocket()
                    }
                }
                connection.cancel()
            }
        }
        connection.start(queue: .main)
    }

    // MARK: - WebSocket

    private func connectWebSocket() {
        guard let ip = discoveredIP else { return }

        Task {
            guard let token = try? await authService?.refreshTokenIfNeeded() else {
                errorMessage = "Not authenticated. Please connect your Sonos account in Settings."
                return
            }

            webSocketService.onEvent = { [weak self] namespace, json in
                Task { @MainActor [weak self] in
                    self?.handleWebSocketEvent(namespace: namespace, json: json)
                }
            }

            webSocketService.connect(to: ip, token: token)
        }
    }

    private func handleWebSocketEvent(namespace: String, json: [String: Any]) {
        switch namespace {
        case "groups":
            if let groups = json["groups"] as? [[String: Any]], let first = groups.first {
                householdId = json["householdId"] as? String
                groupId = first["id"] as? String

                // Parse group members into zones
                if let players = json["players"] as? [[String: Any]] {
                    zones = players.map { player in
                        let name = player["name"] as? String ?? "Unknown"
                        return SonosZone(coordinator: name, members: [name])
                    }
                    if selectedZone == nil {
                        selectedZone = zones.first(where: { $0.coordinator == "Living Room" }) ?? zones.first
                    }
                }

                // Now subscribe to playback and volume
                if let hId = householdId, let gId = groupId {
                    webSocketService.subscribe(namespace: "playback", householdId: hId, groupId: gId)
                    webSocketService.subscribe(namespace: "playerVolume", householdId: hId, groupId: gId)
                }
            }

            // Handle subscription confirmation
            if json["type"] as? String == "subscribed" {
                // Already subscribed to groups, now get initial state
            }

        case "playback":
            let isPlaying = (json["playbackState"] as? String) == "PLAYBACK_STATE_PLAYING"

            var title: String?
            var artist: String?
            var album: String?

            if let container = json["container"] as? [String: Any] {
                title = container["name"] as? String
            }
            if let currentItem = json["currentItem"] as? [String: Any],
               let track = currentItem["track"] as? [String: Any] {
                title = track["name"] as? String ?? title
                artist = track["artist"] as? [String: Any]?["name"] as? String
                album = track["album"] as? [String: Any]?["name"] as? String

                trackInfo = SonosTrackInfo(
                    artist: artist,
                    album: album,
                    title: title,
                    albumArt: track["imageUrl"] as? String,
                    isPlaying: isPlaying
                )
            }

            let currentVolume = playbackState?.volume ?? 0
            playbackState = SonosPlaybackState(
                title: title,
                artist: artist,
                album: album,
                isPlaying: isPlaying,
                volume: currentVolume
            )

        case "playerVolume":
            if let volume = json["volume"] as? Int {
                let current = playbackState ?? SonosPlaybackState()
                playbackState = SonosPlaybackState(
                    title: current.title,
                    artist: current.artist,
                    album: current.album,
                    isPlaying: current.isPlaying,
                    volume: volume
                )
            }

        default:
            break
        }
    }

    // MARK: - Commands

    func sendCommand(_ command: SonosCommand) async {
        guard let hId = householdId, let gId = groupId else {
            errorMessage = "No group connected"
            return
        }

        let (namespace, wsCommand) = command.webSocketCommand

        var message: [String: Any] = [
            "namespace": namespace,
            "command": wsCommand,
            "householdId": hId,
            "groupId": gId,
        ]

        switch command {
        case .volumeUp:
            message["volumeDelta"] = 2
        case .volumeDown:
            message["volumeDelta"] = -2
        default:
            break
        }

        webSocketService.send(message)
    }

    func setVolume(_ volume: Int) async {
        guard let hId = householdId, let gId = groupId else { return }

        let clamped = max(0, min(100, volume))
        webSocketService.send([
            "namespace": "playerVolume",
            "command": "setVolume",
            "householdId": hId,
            "groupId": gId,
            "volume": clamped,
        ])
    }

    func setGroupVolume(to targetVolume: Int) async {
        await setVolume(targetVolume)
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()

        // Subscribe to groups namespace to bootstrap
        if let hId = householdId {
            webSocketService.subscribe(namespace: "groups", householdId: hId)
        } else if discoveredIP != nil {
            // If we have IP but no household yet, try connecting WS
            connectWebSocket()
        }

        // Light polling as fallback — WebSocket events are primary
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.webSocketService.isConnected, self.discoveredIP != nil {
                    self.connectWebSocket()
                }
            }
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        webSocketService.disconnect()
    }
}
