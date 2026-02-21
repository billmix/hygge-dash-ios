import Foundation

struct Station: Identifiable, Codable, Hashable {
    var id: String { name }
    let name: String
    let url: String
}

struct StationsResponse: Codable {
    let stations: [Station]
}
