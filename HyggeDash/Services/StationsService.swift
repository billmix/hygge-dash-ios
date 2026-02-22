import Foundation

@MainActor
class StationsService: ObservableObject {
    @Published var stations: [Station] = []

    private static let storageKey = "savedStations"

    init() {
        loadStations()
    }

    // MARK: - CRUD

    func addStation(name: String, url: String) {
        let station = Station(name: name, url: url)
        stations.append(station)
        saveStations()
    }

    func updateStation(_ station: Station, name: String, url: String) {
        guard let index = stations.firstIndex(where: { $0.id == station.id }) else { return }
        stations[index].name = name
        stations[index].url = url
        saveStations()
    }

    func deleteStation(_ station: Station) {
        stations.removeAll { $0.id == station.id }
        saveStations()
    }

    func deleteStations(at offsets: IndexSet) {
        stations.remove(atOffsets: offsets)
        saveStations()
    }

    func moveStations(from source: IndexSet, to destination: Int) {
        stations.move(fromOffsets: source, toOffset: destination)
        saveStations()
    }

    // MARK: - Persistence

    private func saveStations() {
        guard let data = try? JSONEncoder().encode(stations) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func loadStations() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([Station].self, from: data) else { return }
        stations = saved
    }
}
