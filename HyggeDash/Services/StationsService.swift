import Foundation

@MainActor
class StationsService: ObservableObject {
    @Published var stations: [Station] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cachedStations: [Station]?
    private var lastFetchTime: Date?
    private let cacheExpirationSeconds: TimeInterval = 300 // 5 minutes

    var baseURL: String {
        let ip = UserDefaults.standard.string(forKey: "sonosServerIP") ?? "192.168.1.16"
        let port = UserDefaults.standard.string(forKey: "stationsServerPort") ?? "8766"
        return "http://\(ip):\(port)"
    }

    func fetchStations(forceRefresh: Bool = false) async {
        // Return cached data if still valid
        if !forceRefresh,
           let cached = cachedStations,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheExpirationSeconds {
            stations = cached
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            guard let url = URL(string: "\(baseURL)/stations") else {
                throw URLError(.badURL)
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                throw URLError(.badServerResponse)
            }

            let stationsResponse = try JSONDecoder().decode(StationsResponse.self, from: data)
            self.stations = stationsResponse.stations
            self.cachedStations = stationsResponse.stations
            self.lastFetchTime = Date()
        } catch {
            errorMessage = "Failed to load playlists: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func clearCache() {
        cachedStations = nil
        lastFetchTime = nil
    }
}
