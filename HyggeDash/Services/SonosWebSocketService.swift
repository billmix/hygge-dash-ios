import Foundation

@MainActor
class SonosWebSocketService: NSObject, ObservableObject {
    @Published var trackInfo: SonosTrackInfo?
    @Published var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTask: Task<Void, Never>?

    var webSocketURL: String {
        let ip = UserDefaults.standard.string(forKey: "sonosServerIP") ?? "192.168.1.16"
        return "ws://\(ip):8765"
    }

    func connect() {
        guard webSocketTask == nil else { return }

        guard let url = URL(string: webSocketURL) else {
            print("Invalid WebSocket URL")
            return
        }

        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
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

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

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
                    // Continue listening for more messages
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
        guard let data = text.data(using: .utf8) else { return }

        do {
            let trackInfo = try JSONDecoder().decode(SonosTrackInfo.self, from: data)
            self.trackInfo = trackInfo
        } catch {
            print("Failed to decode WebSocket message: \(error)")
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self.webSocketTask = nil
            self.connect()
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
