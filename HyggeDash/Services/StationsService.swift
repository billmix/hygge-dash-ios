import Foundation

/// Shared storage key and App Group identifier
/// The App Group allows the Share Extension to write stations that the main app can read.
private let appGroupID = "group.com.hyggedash.app"
private let storageKey = "savedStations"

@MainActor
class StationsService: ObservableObject {
    @Published var stations: [Station] = []

    private let defaults: UserDefaults

    init() {
        // Use App Group shared container if available, fall back to standard
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        loadStations()
    }

    // MARK: - CRUD

    func addStation(name: String, url: String) {
        let station = Station(name: name, url: url)
        stations.insert(station, at: 0) // newest first
        saveStations()
    }

    /// Add a station from a share extension (name may be empty, will use URL-derived name)
    func addFromShare(url: String, name: String? = nil) {
        let source = StationSource.detect(from: url)
        let resolvedName = name?.isEmpty == false ? name! : defaultName(for: url, source: source)

        // Avoid duplicates
        guard !stations.contains(where: { $0.url == url }) else {
            print("📋 [STATIONS] Duplicate URL, skipping: \(url)")
            return
        }

        let station = Station(name: resolvedName, url: url)
        stations.insert(station, at: 0)
        saveStations()
        print("📋 [STATIONS] Added from share: \(resolvedName) (\(source.displayName))")
    }

    func updateStation(_ station: Station, name: String, url: String) {
        guard let index = stations.firstIndex(where: { $0.id == station.id }) else { return }
        stations[index].name = name
        stations[index].url = url
        stations[index].source = StationSource.detect(from: url)
        if let parsed = ShareLinkParser.parse(url) {
            stations[index].contentType = StationContentType(rawValue: parsed.type) ?? .unknown
        }
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

    /// Reload from shared storage (call when app returns to foreground after share extension adds items)
    func reload() {
        loadStations()
    }

    // MARK: - Persistence

    private func saveStations() {
        guard let data = try? JSONEncoder().encode(stations) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func loadStations() {
        guard let data = defaults.data(forKey: storageKey) else {
            // Try migrating from old standard UserDefaults
            migrateFromStandardDefaults()
            return
        }
        // Try new format first, fall back to legacy
        if let saved = try? JSONDecoder().decode([Station].self, from: data) {
            stations = saved
        } else if let legacy = try? JSONDecoder().decode([LegacyStation].self, from: data) {
            stations = legacy.map { Station(id: $0.id.uuidString, name: $0.name, url: $0.url) }
            saveStations() // re-save in new format
        }
    }

    /// Migrate from standard UserDefaults to App Group (one-time)
    private func migrateFromStandardDefaults() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let legacy = try? JSONDecoder().decode([LegacyStation].self, from: data) {
            stations = legacy.map { Station(id: $0.id.uuidString, name: $0.name, url: $0.url) }
            saveStations()
            UserDefaults.standard.removeObject(forKey: storageKey)
            print("📋 [STATIONS] Migrated \(stations.count) stations to App Group")
        }
    }

    /// Generate a reasonable default name from a URL
    private func defaultName(for url: String, source: StationSource) -> String {
        if let parsed = ShareLinkParser.parse(url) {
            return "\(source.displayName) \(parsed.type.capitalized)"
        }
        return "\(source.displayName) Link"
    }
}

/// Legacy format for migration
private struct LegacyStation: Codable {
    let id: UUID
    var name: String
    var url: String
}
