import Foundation
import Combine

@MainActor
class SonosWebSocketService: NSObject, ObservableObject {
    @Published var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var speakerIP: String?
    private var accessToken: String?

    var onEvent: ((String, [String: Any]) -> Void)?

    func connect(to ip: String, token: String) {
        disconnect()
        speakerIP = ip
        accessToken = token

        guard let url = URL(string: "ws://\(ip):1400/websocket/api") else {
            print("Invalid WebSocket URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("Sec-WebSocket-Protocol", forHTTPHeaderField: "v1.api.smartspeaker.audio")

        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessage()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
    }

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(text)) { error in
            if let error {
                print("WebSocket send error: \(error.localizedDescription)")
            }
        }
    }

    func subscribe(namespace: String, householdId: String, groupId: String? = nil) {
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

    // MARK: - Private

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
                    self.receiveMessage()

                case .failure(let error):
                    print("WebSocket receive error: \(error)")
                    self.isConnected = false
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let namespace = json["namespace"] as? String else { return }

        onEvent?(namespace, json)
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let ip = speakerIP, let token = accessToken else { return }
            self.connect(to: ip, token: token)
        }
    }
}

extension SonosWebSocketService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.isConnected = true
            print("WebSocket connected")
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.isConnected = false
            print("WebSocket disconnected")
            self.scheduleReconnect()
        }
    }
}
