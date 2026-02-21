import Foundation
import CoreLocation

// MARK: - OpenWeatherMap Response Models

struct OpenWeatherResponse: Codable {
    let name: String
    let main: OpenWeatherMain
    let weather: [OpenWeatherCondition]
}

struct OpenWeatherMain: Codable {
    let temp: Double
    let tempMin: Double
    let tempMax: Double

    enum CodingKeys: String, CodingKey {
        case temp
        case tempMin = "temp_min"
        case tempMax = "temp_max"
    }
}

struct OpenWeatherCondition: Codable {
    let id: Int
    let main: String
    let description: String
    let icon: String
}

@MainActor
class WeatherService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var currentTemperature: String = "--°"
    @Published var highTemperature: String = "--°"
    @Published var lowTemperature: String = "--°"
    @Published var condition: String = "Loading..."
    @Published var conditionSymbol: String = "cloud.fill"
    @Published var cityName: String = ""

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var updateTask: Task<Void, Never>?

    var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OpenWeatherMapAPIKey") as? String ?? ""
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    deinit {
        updateTask?.cancel()
    }

    func startWeatherUpdates() {
        print("🌤️ Starting weather updates...")
        print("🌤️ Location authorization status: \(locationManager.authorizationStatus.rawValue)")

        // Request location permission
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()

        // Refresh weather every 15 minutes
        updateTask = Task {
            while !Task.isCancelled {
                if let location = currentLocation {
                    print("🌤️ Fetching weather for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    await fetchWeather(for: location)
                } else {
                    print("🌤️ No location available yet, waiting...")
                }
                try? await Task.sleep(for: .seconds(900)) // 15 minutes
            }
        }
    }

    func fetchWeather(for location: CLLocation) async {
        guard !apiKey.isEmpty else {
            print("❌ OpenWeatherMap API key not set")
            condition = "No API Key"
            return
        }

        print("🌤️ Fetching weather data from OpenWeatherMap...")

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(lat)&lon=\(lon)&appid=\(apiKey)&units=imperial"

        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)

            // City name from API
            cityName = response.name
            print("🌤️ Weather data received for: \(cityName)")

            // Current temperature
            currentTemperature = "\(Int(response.main.temp.rounded()))°"
            highTemperature = "\(Int(response.main.tempMax.rounded()))°"
            lowTemperature = "\(Int(response.main.tempMin.rounded()))°"

            // Condition
            if let weatherCondition = response.weather.first {
                condition = weatherCondition.main
                conditionSymbol = mapConditionToSymbol(weatherCondition.id)
            }

            print("🌤️ \(cityName): \(currentTemperature), \(condition) (lat: \(lat), lon: \(lon))")

        } catch {
            print("❌ Weather fetch error: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
        }
    }

    private func mapConditionToSymbol(_ conditionId: Int) -> String {
        // OpenWeatherMap condition codes: https://openweathermap.org/weather-conditions
        switch conditionId {
        case 200...232: return "cloud.bolt.rain.fill"      // Thunderstorm
        case 300...321: return "cloud.drizzle.fill"        // Drizzle
        case 500...504: return "cloud.rain.fill"           // Rain
        case 511: return "cloud.sleet.fill"                // Freezing rain
        case 520...531: return "cloud.heavyrain.fill"      // Shower rain
        case 600...622: return "cloud.snow.fill"           // Snow
        case 701: return "cloud.fog.fill"                  // Mist
        case 711: return "smoke.fill"                      // Smoke
        case 721: return "sun.haze.fill"                   // Haze
        case 731, 761: return "sun.dust.fill"              // Dust
        case 741: return "cloud.fog.fill"                  // Fog
        case 751: return "sun.dust.fill"                   // Sand
        case 762: return "mountain.2.fill"                 // Volcanic ash
        case 771: return "wind"                            // Squalls
        case 781: return "tornado"                         // Tornado
        case 800: return "sun.max.fill"                    // Clear sky
        case 801: return "cloud.sun.fill"                  // Few clouds
        case 802: return "cloud.fill"                      // Scattered clouds
        case 803, 804: return "smoke.fill"                 // Broken/overcast clouds
        default: return "cloud.fill"
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        print("📍 Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        currentLocation = location

        Task {
            await fetchWeather(for: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        // Use a default location (San Francisco)
        let defaultLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        currentLocation = defaultLocation

        Task {
            await fetchWeather(for: defaultLocation)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("🔐 Location authorization changed: \(status.rawValue)")

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ Location authorized, requesting location...")
            locationManager.requestLocation()
        case .denied, .restricted:
            print("⚠️ Location denied/restricted, using default location")
            let defaultLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
            currentLocation = defaultLocation
            Task {
                await fetchWeather(for: defaultLocation)
            }
        case .notDetermined:
            print("❓ Location not determined, requesting authorization...")
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }
}
