import Foundation
import WeatherKit
import CoreLocation

@MainActor
class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentTemperature: String = "--°"
    @Published var highTemperature: String = "--°"
    @Published var lowTemperature: String = "--°"
    @Published var condition: String = "Loading..."
    @Published var conditionSymbol: String = "cloud.fill"
    
    private let weatherService = WeatherKit.WeatherService.shared
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    func startWeatherUpdates() {
        // Request location permission
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
        
        // Refresh weather every 15 minutes
        Task {
            while !Task.isCancelled {
                if let location = currentLocation {
                    await fetchWeather(for: location)
                }
                try? await Task.sleep(for: .seconds(900)) // 15 minutes
            }
        }
    }
    
    func fetchWeather(for location: CLLocation) async {
        do {
            let weather = try await weatherService.weather(for: location)
            
            // Current temperature
            let temp = weather.currentWeather.temperature
            currentTemperature = formatTemperature(temp)
            
            // Daily forecast (high/low)
            if let today = weather.dailyForecast.first {
                highTemperature = formatTemperature(today.highTemperature)
                lowTemperature = formatTemperature(today.lowTemperature)
            }
            
            // Condition
            condition = weather.currentWeather.condition.description
            conditionSymbol = weather.currentWeather.symbolName
            
        } catch {
            print("Weather fetch error: \(error.localizedDescription)")
            // Keep showing last known data or defaults
        }
    }
    
    private func formatTemperature(_ measurement: Measurement<UnitTemperature>) -> String {
        let formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 0
        formatter.unitOptions = .providedUnit
        
        // Convert to Fahrenheit for US, keep Celsius otherwise
        let fahrenheit = measurement.converted(to: .fahrenheit)
        return formatter.string(from: fahrenheit).replacingOccurrences(of: " ", with: "")
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        currentLocation = location
        
        Task {
            await fetchWeather(for: location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        // Use a default location (San Francisco)
        let defaultLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        currentLocation = defaultLocation
        
        Task {
            await fetchWeather(for: defaultLocation)
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            // Use default location
            let defaultLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
            currentLocation = defaultLocation
            Task {
                await fetchWeather(for: defaultLocation)
            }
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }
}
