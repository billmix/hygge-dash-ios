import Foundation
import Combine

/// Connects to a Sonos speaker's local WebSocket for real-time playback,
/// metadata, and volume events — replaces REST polling.
@MainActor
class SonosWebSocketService: NSObject, ObservableObject {
    @Published var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var currentURL: String?
    private var householdId: String?
    private var groupId: String?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    /// Called when playback state changes (playing/paused/idle)
    var onPlaybackState: ((Bool) -> Void)?
    /// Called when track metadata changes (title, artist, album, art)
    var onMetadata: ((String?, String?, String?, String?) -> Void)?
    /// Called when volume changes
    var onVolume: ((Int) -> Void)?
    /// Called when groups change
    var onGroupsChanged: (() -> Void)?

    // MARK: - Connect / Disconnect

    private var accessToken: String?

    func connect(websocketUrl: String, householdId: String, groupId: String, accessToken: String?) {
        // Don't reconnect if already connected to the same URL
        if currentURL == websocketUrl && isConnected { return }

        disconnect()
        self.currentURL = websocketUrl
        self.householdId = householdId
        self.groupId = groupId
        self.accessToken = accessToken

        guard let url = URL(string: websocketUrl) else {
            print("🔌 [WS] Invalid URL: \(websocketUrl)")
            return
        }

        print("🔌 [WS] Connecting to \(websocketUrl)")

        // Sonos local WebSocket requires specific headers
        var request = URLRequest(url: url)
        request.setValue("v1.api.smartspeaker.audio", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        // API key is the Sonos Client ID
        let apiKey = Bundle.main.infoDictionary?["SonosClientID"] as? String ?? ""
        request.setValue(apiKey, forHTTPHeaderField: "X-Sonos-Api-Key")

        // OAuth access token for authorization
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessage()
    }

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        currentURL = nil
    }

    // MARK: - Subscribe to Namespaces

    private func subscribeAll() {
        guard let hId = householdId, let gId = groupId else { return }

        // Subscribe to playback state
        subscribe(namespace: "playback", householdId: hId, groupId: gId)
        // Subscribe to track metadata
        subscribe(namespace: "playbackMetadata", householdId: hId, groupId: gId)
        // Subscribe to volume
        subscribe(namespace: "groupVolume", householdId: hId, groupId: gId)
        // Subscribe to group changes
        subscribe(namespace: "groups", householdId: hId)

        print("🔌 [WS] Subscribed to playback, playbackMetadata, groupVolume, groups")
    }

    private func subscribe(namespace: String, householdId: String, groupId: String? = nil) {
        var message: [String: Any] = [
            "namespace": namespace,
            "command": "subscribe",
            "householdId": householdId,
        ]
        if let groupId {
            message["groupId"] = groupId
        }
        send(message)
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(text)) { error in
            if let error {
                print("🔌 [WS] Send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Receive

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    // Continue listening
                    self.receiveMessage()

                case .failure(let error):
                    print("🔌 [WS] Receive error: \(error.localizedDescription)")
                    self.isConnected = false
                    self.scheduleReconnect()
                }
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let namespace = json["namespace"] as? String
        let type = json["type"] as? String

        // Skip subscribe confirmations
        if type == "subscribed" {
            print("🔌 [WS] ✅ Subscribed to \(namespace ?? "unknown")")
            return
        }

        switch namespace {
        case "playback":
            handlePlaybackEvent(json)
        case "playbackMetadata":
            handleMetadataEvent(json)
        case "groupVolume":
            handleVolumeEvent(json)
        case "groups":
            print("🔌 [WS] Groups changed")
            onGroupsChanged?()
        default:
            print("🔌 [WS] Event: \(namespace ?? "?") — \(text.prefix(200))")
        }
    }

    private func handlePlaybackEvent(_ json: [String: Any]) {
        guard let playbackState = json["playbackState"] as? String else { return }
        let isPlaying = playbackState == "PLAYBACK_STATE_PLAYING"
        print("🔌 [WS] Playback: \(playbackState)")
        onPlaybackState?(isPlaying)
    }

    private func handleMetadataEvent(_ json: [String: Any]) {
        var title: String?
        var artist: String?
        var album: String?
        var imageUrl: String?

        if let container = json["container"] as? [String: Any] {
            title = container["name"] as? String
            imageUrl = container["imageUrl"] as? String
        }

        if let currentItem = json["currentItem"] as? [String: Any],
           let track = currentItem["track"] as? [String: Any] {
            title = track["name"] as? String ?? title
            artist = (track["artist"] as? [String: Any])?["name"] as? String
            album = (track["album"] as? [String: Any])?["name"] as? String
            imageUrl = track["imageUrl"] as? String ?? imageUrl
        }

        print("🔌 [WS] Metadata: \(title ?? "?") — \(artist ?? "?")")
        onMetadata?(title, artist, album, imageUrl)
    }

    private func handleVolumeEvent(_ json: [String: Any]) {
        guard let volume = json["volume"] as? Int else { return }
        print("🔌 [WS] Volume: \(volume)")
        onVolume?(volume)
    }

    // MARK: - Keepalive & Reconnect

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                webSocketTask?.sendPing { error in
                    if let error {
                        print("🔌 [WS] Ping failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func scheduleReconnect() {
        reconnectAttempts += 1
        if reconnectAttempts > maxReconnectAttempts {
            print("🔌 [WS] Max reconnect attempts reached (\(maxReconnectAttempts)), giving up. Polling will continue as fallback.")
            return
        }

        reconnectTask?.cancel()
        let delay = min(3.0 * Double(reconnectAttempts), 15.0) // backoff: 3s, 6s, 9s...
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  let url = currentURL,
                  let hId = householdId,
                  let gId = groupId else { return }
            print("🔌 [WS] Reconnecting (attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts))...")
            self.connect(websocketUrl: url, householdId: hId, groupId: gId, accessToken: self.accessToken)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension SonosWebSocketService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            print("🔌 [WS] ✅ Connected")
            self.isConnected = true
            self.reconnectAttempts = 0
            self.subscribeAll()
            self.startPing()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            print("🔌 [WS] Disconnected (code: \(closeCode.rawValue))")
            self.isConnected = false
            self.scheduleReconnect()
        }
    }

    // Trust local self-signed certs from Sonos speakers
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
