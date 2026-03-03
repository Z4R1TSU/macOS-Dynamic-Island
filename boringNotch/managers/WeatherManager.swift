//
//  WeatherManager.swift
//  boringNotch
//
//  Fetches current weather using Open-Meteo (no API key required) + CoreLocation.
//

import Combine
import CoreLocation
import Defaults
import Foundation
import SwiftUI

enum WeatherCondition: String {
    case clear, partlyCloudy, overcast, fog
    case drizzle, rain, heavyRain
    case snow, heavySnow
    case thunderstorm
    case unknown

    var sfSymbol: String {
        return sfSymbol(isDay: true)
    }
    
    func sfSymbol(isDay: Bool) -> String {
        switch self {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .snow: return "cloud.snow.fill"
        case .heavySnow: return "cloud.snow.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .unknown: return "cloud.fill"
        }
    }

    var description: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .overcast: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .heavyRain: return "Heavy Rain"
        case .snow: return "Snow"
        case .heavySnow: return "Heavy Snow"
        case .thunderstorm: return "Thunderstorm"
        case .unknown: return "Unknown"
        }
    }

    var hasParticles: Bool {
        switch self {
        case .clear, .partlyCloudy, .overcast, .fog,
             .drizzle, .rain, .heavyRain,
             .snow, .heavySnow, .thunderstorm:
            return true
        case .unknown:
            return false
        }
    }

    var isSnow: Bool { self == .snow || self == .heavySnow }
    var isSunny: Bool { self == .clear }
    var isCloudy: Bool { self == .overcast || self == .fog || self == .partlyCloudy }

    var particleIntensity: Double {
        switch self {
        case .clear: return 0.3
        case .partlyCloudy: return 0.2
        case .overcast, .fog: return 0.25
        case .drizzle: return 0.3
        case .rain: return 0.6
        case .heavyRain, .thunderstorm: return 1.0
        case .snow: return 0.4
        case .heavySnow: return 0.8
        default: return 0
        }
    }

    static func from(wmoCode: Int) -> WeatherCondition {
        switch wmoCode {
        case 0: return .clear
        case 1, 2: return .partlyCloudy
        case 3: return .overcast
        case 45, 48: return .fog
        case 51, 53: return .drizzle
        case 55, 61, 63: return .rain
        case 65, 80, 81, 82: return .heavyRain
        case 71, 73, 77, 85: return .snow
        case 75, 86: return .heavySnow
        case 95, 96, 99: return .thunderstorm
        default: return .unknown
        }
    }
}

struct WeatherData {
    var temperature: Double = 0
    var condition: WeatherCondition = .unknown
    var cityName: String = ""
    var isLoaded: Bool = false
    var isDay: Bool = true
}

@MainActor
class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherManager()

    @Published var weather = WeatherData()
    @Published var locationAuthorized = false

    private let locationManager = CLLocationManager()
    private var lastFetchLocation: CLLocation?
    private var lastFetchTime: Date?
    private var fetchTimer: Timer?
    private let geocoder = CLGeocoder()
    private var immediateRefreshTask: Task<Void, Never>?

    private struct CachedWeather: Codable {
        var temperature: Double
        var conditionRawValue: String
        var cityName: String
        var isDay: Bool
        var fetchedAt: Date
        var latitude: Double
        var longitude: Double
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        loadCachedWeather()
    }

    func startMonitoring() {
        fetchTimer?.invalidate()
        fetchTimer = nil

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedAlways || status == .authorized {
            locationAuthorized = true
            locationManager.startUpdatingLocation()
        }

        if status == .authorizedAlways || status == .authorized {
            if let location = (lastFetchLocation ?? locationManager.location) {
                lastFetchLocation = location
                immediateRefreshTask?.cancel()
                immediateRefreshTask = Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    if self.weather.cityName.isEmpty {
                        self.reverseGeocode(location)
                    }
                }
            }
        }

        // Fetch weather every 4 hours, but update location only every 6 hours
        fetchTimer = Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // Only request location update if it's been more than 6 hours (21600 seconds)
                // or if we've never successfully fetched a location
                let shouldUpdateLocation = self.lastFetchTime == nil || Date().timeIntervalSince(self.lastFetchTime!) > 21600
                
                if shouldUpdateLocation {
                    self.locationManager.startUpdatingLocation()
                } else if let location = self.lastFetchLocation {
                    // Otherwise just refresh weather using cached location
                    await self.fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                }
            }
        }
    }

    func stopMonitoring() {
        fetchTimer?.invalidate()
        fetchTimer = nil
        immediateRefreshTask?.cancel()
        immediateRefreshTask = nil
        locationManager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            locationAuthorized = (status == .authorizedAlways || status == .authorized)
            if locationAuthorized {
                locationManager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            let shouldForceUpdate = lastFetchTime == nil || Date().timeIntervalSince(lastFetchTime!) > 14000 // Force update if older than ~4 hours
            
            if !shouldForceUpdate, let last = lastFetchLocation, location.distance(from: last) < 1000 && weather.isLoaded {
                locationManager.stopUpdatingLocation()
                return
            }
            
            lastFetchLocation = location
            lastFetchTime = Date()
            locationManager.stopUpdatingLocation()
            await fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            reverseGeocode(location)
        }
    }

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor [weak self] in
                if let city = placemarks?.first?.locality {
                    self?.weather.cityName = city
                    self?.persistCachedWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                }
            }
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double) async {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code,is_day&timezone=auto"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current"] as? [String: Any],
               let temp = current["temperature_2m"] as? Double,
               let code = current["weather_code"] as? Int,
               let isDayValue = current["is_day"] as? Int
            {
                weather.temperature = temp
                weather.condition = WeatherCondition.from(wmoCode: code)
                weather.isDay = isDayValue == 1
                weather.isLoaded = true
                persistCachedWeather(latitude: latitude, longitude: longitude)
            }
        } catch {
            // Silently fail - weather is supplementary info
        }
    }

    private func loadCachedWeather() {
        guard let data = Defaults[.cachedWeatherData] else { return }
        guard let cached = try? JSONDecoder().decode(CachedWeather.self, from: data) else { return }

        let condition = WeatherCondition(rawValue: cached.conditionRawValue) ?? .unknown
        weather = WeatherData(
            temperature: cached.temperature,
            condition: condition,
            cityName: cached.cityName,
            isLoaded: true,
            isDay: cached.isDay
        )

        lastFetchLocation = CLLocation(latitude: cached.latitude, longitude: cached.longitude)
        lastFetchTime = cached.fetchedAt
    }

    private func persistCachedWeather(latitude: Double, longitude: Double) {
        guard weather.isLoaded else { return }

        let cached = CachedWeather(
            temperature: weather.temperature,
            conditionRawValue: weather.condition.rawValue,
            cityName: weather.cityName,
            isDay: weather.isDay,
            fetchedAt: Date(),
            latitude: latitude,
            longitude: longitude
        )

        guard let data = try? JSONEncoder().encode(cached) else { return }
        Defaults[.cachedWeatherData] = data
    }
}
