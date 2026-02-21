import Foundation
import Combine

struct SpeakersResponse: Codable {
    let speakers: [String]
}

@MainActor
class SonosService: ObservableObject {
    @Published var zones: [SonosZone] = []
    @Published var selectedZone: SonosZone?
    @Published var playbackState: SonosPlaybackState?
    @Published var trackInfo: SonosTrackInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var refreshTimer: Timer?
    private let webSocketService = SonosWebSocketService()
    private var webSocketCancellable: AnyCancellable?

    var baseURL: String {
        let ip = UserDefaults.standard.string(forKey: "sonosServerIP") ?? "192.168.1.16"
        let port = UserDefaults.standard.string(forKey: "sonosServerPort") ?? "8000"
        return "http://\(ip):\(port)"
    }

    func fetchSpeakers() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let url = URL(string: "\(baseURL)/speakers") else {
                throw URLError(.badURL)
            }

            let (data, _) = try await URLSession.shared.data(from: url)

            // The /speakers endpoint returns {"speakers": ["name1", "name2", ...]}
            let response = try JSONDecoder().decode(SpeakersResponse.self, from: data)
            
            // Convert speaker names to SonosZone objects
            self.zones = response.speakers.map { speakerName in
                SonosZone(coordinator: speakerName, members: [speakerName], isPlaying: nil)
            }

            // Default to "Living Room" if available, otherwise first zone
            if selectedZone == nil {
                if let livingRoom = zones.first(where: { $0.coordinator == "Living Room" }) {
                    selectedZone = livingRoom
                } else if let firstZone = zones.first {
                    selectedZone = firstZone
                }
            }
        } catch {
            errorMessage = "Failed to fetch speakers: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func fetchPlaybackState() async {
        guard let zone = selectedZone else { return }

        do {
            guard let url = URL(string: "\(baseURL)/\(zone.coordinator.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zone.coordinator)/state") else {
                throw URLError(.badURL)
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SonosTrackResponse.self, from: data)

            // The result field contains "PLAYING", "PAUSED", or "STOPPED"
            let isPlaying = response.result == "PLAYING"

            // Preserve existing track info and volume, just update isPlaying
            let currentVolume = self.playbackState?.volume ?? 0
            let currentTitle = self.playbackState?.title
            let currentArtist = self.playbackState?.artist
            let currentAlbum = self.playbackState?.album

            self.playbackState = SonosPlaybackState(
                title: currentTitle,
                artist: currentArtist,
                album: currentAlbum,
                isPlaying: isPlaying,
                volume: currentVolume
            )

            // Also fetch the current volume
            await fetchVolume()
        } catch {
            // Silently fail for state updates to avoid spamming errors
        }
    }

    func fetchVolume() async {
        guard let zone = selectedZone else { return }

        do {
            guard let url = URL(string: "\(baseURL)/\(zone.coordinator.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zone.coordinator)/group_volume") else {
                throw URLError(.badURL)
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Decode the generic API response
            let response = try JSONDecoder().decode(SonosTrackResponse.self, from: data)
            
            // The result field contains the volume as a string
            if let volume = Int(response.result.trimmingCharacters(in: .whitespacesAndNewlines)) {
                // Only update if volume actually changed to avoid UI flicker
                guard volume != self.playbackState?.volume else { return }

                // Update the volume in playback state
                if let currentState = self.playbackState {
                    self.playbackState = SonosPlaybackState(
                        title: currentState.title,
                        artist: currentState.artist,
                        album: currentState.album,
                        isPlaying: currentState.isPlaying,
                        volume: volume
                    )
                } else {
                    // Create a minimal playback state if one doesn't exist
                    self.playbackState = SonosPlaybackState(volume: volume)
                }
            }
        } catch {
            // Silently fail for volume updates to avoid spamming errors
        }
    }

    func fetchTrackInfo() async {
        guard let zone = selectedZone else { return }

        do {
            guard let url = URL(string: "\(baseURL)/\(zone.coordinator.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zone.coordinator)/track") else {
                throw URLError(.badURL)
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SonosTrackResponse.self, from: data)
            
            // Parse the response into track info
            self.trackInfo = SonosTrackInfo(from: response)
        } catch {
            // Silently fail for track updates to avoid spamming errors
        }
    }

    func sendCommand(_ command: SonosCommand) async {
        guard let zone = selectedZone else {
            errorMessage = "No zone selected"
            return
        }

        let roomName = zone.coordinator.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zone.coordinator

        var urlString: String

        switch command {
        case .volumeUp:
            // Fetch current volume, increment by 1, set via group_volume
            await fetchVolume()
            let currentVolume = playbackState?.volume ?? 20
            let newVolume = min(100, currentVolume + 1)
            urlString = "\(baseURL)/\(roomName)/group_volume/\(newVolume)"
        case .volumeDown:
            // Fetch current volume, decrement by 1, set via group_volume
            await fetchVolume()
            let currentVolume = playbackState?.volume ?? 20
            let newVolume = max(0, currentVolume - 1)
            urlString = "\(baseURL)/\(roomName)/group_volume/\(newVolume)"
        default:
            urlString = "\(baseURL)/\(roomName)/\(command.endpoint)"
        }

        do {
            guard let url = URL(string: urlString) else {
                throw URLError(.badURL)
            }

            let (_, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                errorMessage = "Command failed with status \(httpResponse.statusCode)"
            }

            // Refresh playback state after command (track info comes via WebSocket)
            await fetchPlaybackState()
        } catch {
            errorMessage = "Failed to send command: \(error.localizedDescription)"
        }
    }

    func setVolume(_ volume: Int) async {
        guard let zone = selectedZone else { return }

        let roomName = zone.coordinator.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zone.coordinator
        let clampedVolume = max(0, min(100, volume))

        do {
            guard let url = URL(string: "\(baseURL)/\(roomName)/group_volume/\(clampedVolume)") else {
                throw URLError(.badURL)
            }

            let (_, _) = try await URLSession.shared.data(from: url)

            // Fetch the actual group volume to confirm the change
            await fetchVolume()
        } catch {
            errorMessage = "Failed to set volume: \(error.localizedDescription)"
        }
    }

    func setGroupVolume(to targetVolume: Int) async {
        guard let zone = selectedZone else { return }

        let roomName = zone.coordinator.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zone.coordinator
        let clampedTarget = max(0, min(100, targetVolume))

        do {
            guard let url = URL(string: "\(baseURL)/\(roomName)/group_volume/\(clampedTarget)") else {
                throw URLError(.badURL)
            }

            let (_, _) = try await URLSession.shared.data(from: url)

            // Don't immediately fetch - let polling handle it to avoid race conditions
        } catch {
            errorMessage = "Failed to set volume: \(error.localizedDescription)"
        }
    }

    func playStation(_ station: Station) async {
        guard let zone = selectedZone else {
            errorMessage = "No zone selected"
            return
        }

        let roomName = zone.coordinator.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zone.coordinator

        // URL-encode the station URL - keep slashes and colons intact as the API expects them
        guard let encodedStationURL = station.url.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            errorMessage = "Invalid station URL"
            return
        }

        print("Playing station: \(station.name) with URL: \(station.url)")
        print("Encoded URL: \(encodedStationURL)")
        print("Full sharelink URL: \(baseURL)/\(roomName)/sharelink/\(encodedStationURL)")

        do {
            // Clear the queue first
            guard let clearURL = URL(string: "\(baseURL)/\(roomName)/clear_queue") else {
                throw URLError(.badURL)
            }
            let (_, _) = try await URLSession.shared.data(from: clearURL)

            // Add the station via sharelink
            guard let sharelinkURL = URL(string: "\(baseURL)/\(roomName)/sharelink/\(encodedStationURL)") else {
                throw URLError(.badURL)
            }
            print("Sharelink URL: \(sharelinkURL)")
            let (_, response) = try await URLSession.shared.data(from: sharelinkURL)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                errorMessage = "Failed to play station (status \(httpResponse.statusCode))"
                return
            }

            // Start playback from the queue (play_from_queue/1 plays the first track)
            guard let playURL = URL(string: "\(baseURL)/\(roomName)/play_from_queue/1") else {
                throw URLError(.badURL)
            }
            print("Play from queue URL: \(playURL)")
            let (_, _) = try await URLSession.shared.data(from: playURL)

            // Refresh playback state
            await fetchPlaybackState()
        } catch {
            errorMessage = "Failed to play station: \(error.localizedDescription)"
        }
    }

    func startPolling() {
        // Stop any existing polling
        stopPolling()

        // Poll playback state every 5 seconds (for volume updates)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchPlaybackState()
            }
        }

        // Subscribe to WebSocket for track info updates
        webSocketCancellable = webSocketService.$trackInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTrackInfo in
                self?.trackInfo = newTrackInfo
            }
        webSocketService.connect()
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        webSocketCancellable?.cancel()
        webSocketCancellable = nil
        webSocketService.disconnect()
    }
}
