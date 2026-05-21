//
//  AstroModels.swift
//  HalfCup Watch App
//

import CoreLocation
import Foundation
import MapKit
import Observation

struct ObservationSite: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let cloudCoverPercent: Int?
    let bortleClass: Int?
    let hasResolvedLocation: Bool

    var coordinateText: String {
        guard hasResolvedLocation else { return "N/A" }

        let latitudeSuffix = latitude >= 0 ? "N" : "S"
        let longitudeSuffix = longitude >= 0 ? "E" : "W"
        return String(
            format: "%.3f° %@, %.3f° %@",
            abs(latitude),
            latitudeSuffix,
            abs(longitude),
            longitudeSuffix
        )
    }

    var solarCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        let offsetHours = Int((longitude / 15).rounded())
        calendar.timeZone = TimeZone(secondsFromGMT: offsetHours * 60 * 60) ?? .current
        return calendar
    }

    static let fallback = ObservationSite(
        name: "本地时区估算",
        latitude: 31.23,
        longitude: 121.47,
        cloudCoverPercent: nil,
        bortleClass: nil,
        hasResolvedLocation: false
    )

    static func current(latitude: Double, longitude: Double) -> ObservationSite {
        ObservationSite(
            name: "当前位置",
            latitude: latitude,
            longitude: longitude,
            cloudCoverPercent: nil,
            bortleClass: nil,
            hasResolvedLocation: true
        )
    }

    func withCloudCover(_ cloudCoverPercent: Int) -> ObservationSite {
        ObservationSite(
            name: name,
            latitude: latitude,
            longitude: longitude,
            cloudCoverPercent: min(max(cloudCoverPercent, 0), 100),
            bortleClass: bortleClass,
            hasResolvedLocation: hasResolvedLocation
        )
    }
}

struct StargazingWindow: Equatable {
    let start: Date?
    let end: Date?
    let score: Int
    let summary: String

    var displayText: String {
        displayText(calendar: .current)
    }

    func displayText(calendar: Calendar) -> String {
        guard let start, let end else { return summary }
        return "今晚 \(start.clockText(calendar: calendar))-\(end.clockText(calendar: calendar)) 可观测"
    }
}

struct AstroRadarFactor: Identifiable, Equatable {
    let id: String
    let title: String
    let valueText: String
    let score: Int
}

struct WeatherSnapshot: Equatable {
    let lowCloudPercent: Int?
    let midCloudPercent: Int?
    let highCloudPercent: Int?
    let windSpeedKPH: Double?
    let windDirectionDegrees: Double?
    let aqi: Int?
    let uvIndex: Double?
    let seaSurfaceTemperatureCelsius: Double?
    let updatedAt: Date?

    static let unavailable = WeatherSnapshot(
        lowCloudPercent: nil,
        midCloudPercent: nil,
        highCloudPercent: nil,
        windSpeedKPH: nil,
        windDirectionDegrees: nil,
        aqi: nil,
        uvIndex: nil,
        seaSurfaceTemperatureCelsius: nil,
        updatedAt: nil
    )

    var lowCloudText: String {
        Self.percentText(lowCloudPercent)
    }

    var midCloudText: String {
        Self.percentText(midCloudPercent)
    }

    var highCloudText: String {
        Self.percentText(highCloudPercent)
    }

    var windText: String {
        guard let windSpeedKPH else { return "N/A" }
        let speedText = "\(Int(windSpeedKPH.rounded())) km/h"
        guard let windDirectionDegrees else { return speedText }
        return "\(speedText) \(Self.windDirectionText(windDirectionDegrees))"
    }

    var aqiText: String {
        aqi.map { "\($0)" } ?? "N/A"
    }

    var uvText: String {
        guard let uvIndex else { return "N/A" }
        return String(format: "%.1f", uvIndex)
    }

    var seaTemperatureText: String {
        guard let seaSurfaceTemperatureCelsius else { return "N/A" }
        return String(format: "%.1f°C", seaSurfaceTemperatureCelsius)
    }

    private static func percentText(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "N/A"
    }

    private static func windDirectionText(_ degrees: Double) -> String {
        let normalized = ((degrees.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalized / 45).rounded()) % directions.count
        return directions[index]
    }
}

struct PlanetVisibility: Identifiable, Equatable {
    let id: String
    let name: String
    let altitudeDegrees: Int?
    let azimuthText: String?
    let riseTime: Date?
    let bestObservationTime: Date?

    func summaryText(calendar: Calendar) -> String {
        if let altitudeDegrees, altitudeDegrees > 0 {
            let direction = azimuthText ?? "N/A"
            return "\(direction) · \(altitudeDegrees)° H"
        }

        if let riseTime {
            return "\(riseTime.clockText(calendar: calendar)) 升起"
        }

        return "N/A"
    }
}

struct AstroForecast: Equatable {
    let date: Date
    let site: ObservationSite
    let moonPhaseName: String
    let moonIlluminationPercent: Int
    let moonAltitudeDegrees: Int
    let moonAzimuthText: String
    let moonRise: Date?
    let moonSet: Date?
    let sunrise: Date?
    let sunset: Date?
    let stargazingWindow: StargazingWindow
    let radarFactors: [AstroRadarFactor]
    let visiblePlanets: [PlanetVisibility]

    var stargazingComplicationLine: String {
        stargazingWindow.displayText(calendar: site.solarCalendar)
    }

    var lunarDayText: String {
        let lunarCalendar = Calendar(identifier: .chinese)
        let day = lunarCalendar.component(.day, from: date)
        return "农历\(chineseDayText(day))"
    }

    var moonDetailLine: String {
        "\(lunarDayText) · 亮面\(moonIlluminationPercent)%"
    }

    var moonComplicationLine: String {
        if moonAltitudeDegrees > 0 {
            return "月 \(moonAltitudeDegrees)° High"
        }

        if let moonRise {
            return "月 \(moonRise.clockText(calendar: site.solarCalendar)) 升起"
        }

        return "月亮今晚较低"
    }

    var planetComplicationLine: String {
        guard let planet = visiblePlanets.first else { return moonComplicationLine }

        if let altitudeDegrees = planet.altitudeDegrees, altitudeDegrees > 0 {
            let direction = planet.azimuthText ?? "N/A"
            return "\(planet.name) \(direction) · \(altitudeDegrees)° H"
        }

        if let riseTime = planet.riseTime {
            return "\(planet.name) \(riseTime.clockText(calendar: site.solarCalendar)) 升起"
        }

        return "\(planet.name) N/A"
    }

    static var preview: AstroForecast {
        AstroCalculator.forecast(for: Date(), site: .fallback)
    }

    private func chineseDayText(_ day: Int) -> String {
        let names = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]
        guard names.indices.contains(day - 1) else { return "N/A" }
        return names[day - 1]
    }
}

@Observable
final class AstroStore {
    private(set) var forecast: AstroForecast
    private(set) var locationStatusMessage = "等待定位"
    private(set) var weatherStatusMessage = "等待云量"
    private(set) var weatherSnapshot = WeatherSnapshot.unavailable
    private(set) var placeName = "N/A"
    private(set) var tideStatusMessage = "潮汐估算"

    @ObservationIgnored private let locationProvider = LocationProvider()
    @ObservationIgnored private let placeProvider = PlaceProvider()
    @ObservationIgnored private let weatherProvider = WeatherProvider()

    init(date: Date = Date(), site: ObservationSite = .fallback) {
        self.forecast = AstroCalculator.forecast(for: date, site: site)
        self.tideStatusMessage = AstroCalculator.tideSummary(for: date, site: site)
        configureLocationProvider()
    }

    static var preview: AstroStore {
        AstroStore(date: Date(), site: .fallback)
    }

    func refresh(at date: Date = Date()) {
        forecast = AstroCalculator.forecast(for: date, site: forecast.site)
        tideStatusMessage = AstroCalculator.tideSummary(for: date, site: forecast.site)
    }

    func requestLocation() {
        locationProvider.requestLocation()
    }

    func refreshWeather() {
        let site = forecast.site
        guard site.hasResolvedLocation else {
            weatherStatusMessage = "云量 N/A"
            weatherSnapshot = .unavailable
            return
        }

        Task {
            await updateWeather(for: site)
        }
    }

    func refreshTide(at date: Date = Date()) {
        tideStatusMessage = AstroCalculator.tideSummary(for: date, site: forecast.site)
    }

    private func configureLocationProvider() {
        locationProvider.onLocation = { [weak self] location in
            Task { @MainActor in
                guard let self else { return }
                let site = ObservationSite.current(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                self.forecast = AstroCalculator.forecast(for: Date(), site: site)
                self.tideStatusMessage = AstroCalculator.tideSummary(for: Date(), site: site)
                self.locationStatusMessage = ""
                Task {
                    await self.updatePlaceName(for: location)
                    await self.updateWeather(for: site)
                }
            }
        }

        locationProvider.onStatus = { [weak self] message in
            Task { @MainActor in
                self?.locationStatusMessage = message
            }
        }
    }

    private func updatePlaceName(for location: CLLocation) async {
        do {
            let placeName = try await placeProvider.placeName(for: location)
            await MainActor.run {
                self.placeName = placeName
            }
        } catch {
            await MainActor.run {
                self.placeName = "N/A"
            }
        }
    }

    private func updateWeather(for site: ObservationSite) async {
        await MainActor.run {
            weatherStatusMessage = "云量更新中"
        }

        do {
            let reading = try await weatherProvider.currentWeather(
                latitude: site.latitude,
                longitude: site.longitude
            )
            await MainActor.run {
                let updatedSite = site.withCloudCover(reading.cloudCoverPercent)
                forecast = AstroCalculator.forecast(for: Date(), site: updatedSite)
                weatherSnapshot = reading.snapshot
                weatherStatusMessage = "云量 \(reading.cloudCoverPercent)%"
            }
        } catch {
            await MainActor.run {
                weatherStatusMessage = cloudErrorMessage(error)
                weatherSnapshot = .unavailable
            }
        }
    }

    private func cloudErrorMessage(_ error: Error) -> String {
        "N/A"
    }
}

private final class PlaceProvider {
    private var lastLocation: CLLocation?
    private var lastPlaceName: String?
    private var lastLookupDate: Date?

    func placeName(for location: CLLocation) async throws -> String {
        if let cached = cachedPlaceName(for: location) {
            return cached
        }

        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw MKError(.placemarkNotFound)
        }
        request.preferredLocale = .autoupdatingCurrent

        let mapItems = try await mapItems(for: request)
        guard let mapItem = mapItems.first,
              let addressRepresentations = mapItem.addressRepresentations
        else {
            throw MKError(.placemarkNotFound)
        }

        let components = [
            addressRepresentations.regionName,
            addressRepresentations.cityName,
            mapItem.name
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { output, component in
                if output.last != component {
                    output.append(component)
                }
            }

        guard !components.isEmpty else {
            throw MKError(.placemarkNotFound)
        }

        let placeName = components.joined(separator: "·")
        lastLocation = location
        lastPlaceName = placeName
        lastLookupDate = Date()
        return placeName
    }

    private func mapItems(for request: MKReverseGeocodingRequest) async throws -> [MKMapItem] {
        try await withCheckedThrowingContinuation { continuation in
            request.getMapItems { mapItems, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: mapItems ?? [])
            }
        }
    }

    private func cachedPlaceName(for location: CLLocation) -> String? {
        guard let lastLocation,
              let lastPlaceName,
              let lastLookupDate,
              location.distance(from: lastLocation) < 1_000,
              Date().timeIntervalSince(lastLookupDate) < 30 * 60
        else {
            return nil
        }

        return lastPlaceName
    }
}

private final class WeatherProvider {
    struct WeatherReading {
        let cloudCoverPercent: Int
        let snapshot: WeatherSnapshot
    }

    private struct ForecastResponse: Decodable {
        let current: CurrentWeather?
    }

    private struct CurrentWeather: Decodable {
        let cloudCover: Int?
        let cloudCoverLow: Int?
        let cloudCoverMid: Int?
        let cloudCoverHigh: Int?
        let windSpeed: Double?
        let windDirection: Double?
        let uvIndex: Double?

        private enum CodingKeys: String, CodingKey {
            case cloudCover = "cloud_cover"
            case cloudCoverLow = "cloud_cover_low"
            case cloudCoverMid = "cloud_cover_mid"
            case cloudCoverHigh = "cloud_cover_high"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case uvIndex = "uv_index"
        }
    }

    private struct AirQualityResponse: Decodable {
        let current: CurrentAirQuality?
    }

    private struct CurrentAirQuality: Decodable {
        let aqi: Int?

        private enum CodingKeys: String, CodingKey {
            case aqi = "us_aqi"
        }
    }

    private struct MarineResponse: Decodable {
        let current: CurrentMarine?
    }

    private struct CurrentMarine: Decodable {
        let seaSurfaceTemperature: Double?

        private enum CodingKeys: String, CodingKey {
            case seaSurfaceTemperature = "sea_surface_temperature"
        }
    }

    func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherReading {
        async let forecast = openMeteoForecast(latitude: latitude, longitude: longitude)
        async let aqi = openMeteoAQI(latitude: latitude, longitude: longitude)
        async let seaTemperature = openMeteoSeaTemperature(latitude: latitude, longitude: longitude)

        let forecastCurrent = try await forecast
        let currentAQI: Int?
        do {
            currentAQI = try await aqi
        } catch {
            currentAQI = nil
        }

        let currentSeaTemperature: Double?
        do {
            currentSeaTemperature = try await seaTemperature
        } catch {
            currentSeaTemperature = nil
        }
        let snapshot = WeatherSnapshot(
            lowCloudPercent: forecastCurrent.cloudCoverLow,
            midCloudPercent: forecastCurrent.cloudCoverMid,
            highCloudPercent: forecastCurrent.cloudCoverHigh,
            windSpeedKPH: forecastCurrent.windSpeed,
            windDirectionDegrees: forecastCurrent.windDirection,
            aqi: currentAQI,
            uvIndex: forecastCurrent.uvIndex,
            seaSurfaceTemperatureCelsius: currentSeaTemperature,
            updatedAt: Date()
        )

        return WeatherReading(
            cloudCoverPercent: forecastCurrent.cloudCover ?? maxCloudCover(from: snapshot),
            snapshot: snapshot
        )
    }

    private func openMeteoForecast(latitude: Double, longitude: Double) async throws -> CurrentWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", longitude)),
            URLQueryItem(
                name: "current",
                value: [
                    "cloud_cover",
                    "cloud_cover_low",
                    "cloud_cover_mid",
                    "cloud_cover_high",
                    "wind_speed_10m",
                    "wind_direction_10m",
                    "uv_index"
                ].joined(separator: ",")
            ),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let decoded: ForecastResponse = try await requestDecoded(components: components)
        guard let current = decoded.current, current.cloudCover != nil else {
            throw URLError(.cannotParseResponse)
        }

        return current
    }

    private func openMeteoAQI(latitude: Double, longitude: Double) async throws -> Int {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", longitude)),
            URLQueryItem(name: "current", value: "us_aqi"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let decoded: AirQualityResponse = try await requestDecoded(components: components)
        guard let aqi = decoded.current?.aqi else {
            throw URLError(.cannotParseResponse)
        }

        return aqi
    }

    private func openMeteoSeaTemperature(latitude: Double, longitude: Double) async throws -> Double {
        var components = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", longitude)),
            URLQueryItem(name: "current", value: "sea_surface_temperature"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let decoded: MarineResponse = try await requestDecoded(components: components)
        guard let seaTemperature = decoded.current?.seaSurfaceTemperature else {
            throw URLError(.cannotParseResponse)
        }

        return seaTemperature
    }

    private func requestDecoded<Response: Decodable>(components: URLComponents?) async throws -> Response {
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func maxCloudCover(from snapshot: WeatherSnapshot) -> Int {
        [
            snapshot.lowCloudPercent,
            snapshot.midCloudPercent,
            snapshot.highCloudPercent
        ]
            .compactMap { $0 }
            .max() ?? 0
    }

}

private final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    var onStatus: ((String) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1_000
    }

    func requestLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            onStatus?("定位已关闭")
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            onStatus?("定位待授权")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            onStatus?("定位中")
            manager.requestLocation()
        case .denied, .restricted:
            onStatus?("定位未授权")
        @unknown default:
            onStatus?("定位不可用")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .denied, .restricted:
            onStatus?("定位未授权")
        case .notDetermined:
            onStatus?("定位待授权")
        @unknown default:
            onStatus?("定位不可用")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            onStatus?("暂无定位")
            return
        }

        onLocation?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError {
            switch error.code {
            case .denied:
                onStatus?("定位未授权")
            case .locationUnknown:
                onStatus?("定位中")
            default:
                onStatus?("定位失败")
            }
            return
        }

        onStatus?("定位失败")
    }
}

private enum PlanetBody: CaseIterable {
    case mercury
    case venus
    case mars
    case jupiter
    case saturn

    static let visiblePlanets: [PlanetBody] = [.mercury, .venus, .mars, .jupiter, .saturn]

    var name: String {
        switch self {
        case .mercury: return "水星"
        case .venus: return "金星"
        case .mars: return "火星"
        case .jupiter: return "木星"
        case .saturn: return "土星"
        }
    }
}

private struct EclipticSphericalPosition {
    let longitude: Double
    let latitude: Double
    let radius: Double

    var rectangular: (x: Double, y: Double, z: Double) {
        let cosLatitude = cos(latitude)
        return (
            radius * cosLatitude * cos(longitude),
            radius * cosLatitude * sin(longitude),
            radius * sin(latitude)
        )
    }
}

private struct VSOPTerm {
    let amplitude: Double
    let phase: Double
    let frequency: Double
}

private enum VSOP87DTable {
    private typealias Series = [[VSOPTerm]]

    // VSOP87D micro terms, public-domain generated data from VSOP87-Multilang.
    // t is Julian millennia from J2000. Coordinates are heliocentric ecliptic L/B/R.
    static func position(for body: PlanetBody, julianDay: Double) -> EclipticSphericalPosition {
        let t = (julianDay - 2_451_545.0) / 365_250.0
        let series = coefficients(for: body)
        return EclipticSphericalPosition(
            longitude: evaluate(series.longitude, t: t),
            latitude: evaluate(series.latitude, t: t),
            radius: evaluate(series.radius, t: t)
        )
    }

    static func earthPosition(julianDay: Double) -> EclipticSphericalPosition {
        let t = (julianDay - 2_451_545.0) / 365_250.0
        return EclipticSphericalPosition(
            longitude: evaluate(earthL, t: t),
            latitude: evaluate(earthB, t: t),
            radius: evaluate(earthR, t: t)
        )
    }

    private static func evaluate(_ series: Series, t: Double) -> Double {
        var value = 0.0
        var power = 1.0

        for terms in series {
            let subtotal = terms.reduce(0.0) { partial, term in
                partial + term.amplitude * cos(term.phase + term.frequency * t)
            }
            value += subtotal * power
            power *= t
        }

        return value
    }

    private static func coefficients(for body: PlanetBody) -> (longitude: Series, latitude: Series, radius: Series) {
        switch body {
        case .mercury:
            return (mercuryL, mercuryB, mercuryR)
        case .venus:
            return (venusL, venusB, venusR)
        case .mars:
            return (marsL, marsB, marsR)
        case .jupiter:
            return (jupiterL, jupiterB, jupiterR)
        case .saturn:
            return (saturnL, saturnB, saturnR)
        }
    }

    private static let mercuryL: Series = [
        [
            VSOPTerm(amplitude: 0.00034561897, phase: 0.77930765817, frequency: 130439.51570787099),
            VSOPTerm(amplitude: 0.00165590362, phase: 4.11969163181, frequency: 104351.61256629678),
            VSOPTerm(amplitude: 0.00855346843, phase: 1.16520322351, frequency: 78263.70942472259),
            VSOPTerm(amplitude: 0.05046294199, phase: 4.47785489540, frequency: 52175.80628314840),
            VSOPTerm(amplitude: 0.40989414976, phase: 1.48302034194, frequency: 26087.90314157420),
            VSOPTerm(amplitude: 4.40250710144, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00021245035, phase: 2.83531934452, frequency: 104351.61256629678),
            VSOPTerm(amplitude: 0.00080538452, phase: 6.10454743366, frequency: 78263.70942472259),
            VSOPTerm(amplitude: 0.00303471395, phase: 3.05565472363, frequency: 52175.80628314840),
            VSOPTerm(amplitude: 0.01126007832, phase: 6.21703970996, frequency: 26087.90314157420),
            VSOPTerm(amplitude: 26088.14706222746, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00016903658, phase: 4.69072300649, frequency: 26087.90314157420),
            VSOPTerm(amplitude: 0.00053049845, phase: 0.00000000000, frequency: 0.00000000000)
        ]
    ]

    private static let mercuryB: Series = [
        [
            VSOPTerm(amplitude: 0.00031866927, phase: 1.58088495667, frequency: 130439.51570787099),
            VSOPTerm(amplitude: 0.00129778770, phase: 4.83232503961, frequency: 104351.61256629678),
            VSOPTerm(amplitude: 0.00543251810, phase: 1.79644363963, frequency: 78263.70942472259),
            VSOPTerm(amplitude: 0.01222839532, phase: 3.14159265359, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.02388076996, phase: 5.03738959685, frequency: 52175.80628314840),
            VSOPTerm(amplitude: 0.11737528962, phase: 1.98357498767, frequency: 26087.90314157420)
        ],
        [
            VSOPTerm(amplitude: 0.00010894981, phase: 0.48540174006, frequency: 78263.70942472259),
            VSOPTerm(amplitude: 0.00022675295, phase: 0.01515366880, frequency: 52175.80628314840),
            VSOPTerm(amplitude: 0.00146233668, phase: 3.14159265359, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00429151362, phase: 3.50169780393, frequency: 26087.90314157420)
        ],
        [
            VSOPTerm(amplitude: 0.00011830934, phase: 4.79065585784, frequency: 26087.90314157420)
        ]
    ]

    private static let mercuryR: Series = [
        [
            VSOPTerm(amplitude: 0.00021921969, phase: 2.77820093975, frequency: 104351.61256629678),
            VSOPTerm(amplitude: 0.00121281763, phase: 6.01064153805, frequency: 78263.70942472259),
            VSOPTerm(amplitude: 0.00795525557, phase: 2.95989690096, frequency: 52175.80628314840),
            VSOPTerm(amplitude: 0.07834131817, phase: 6.19233722599, frequency: 26087.90314157420),
            VSOPTerm(amplitude: 0.39528271652, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00010094479, phase: 4.47466326316, frequency: 78263.70942472259),
            VSOPTerm(amplitude: 0.00044141826, phase: 1.42385543975, frequency: 52175.80628314840),
            VSOPTerm(amplitude: 0.00217347739, phase: 4.65617158663, frequency: 26087.90314157420)
        ]
    ]

    private static let venusL: Series = [
        [
            VSOPTerm(amplitude: 0.00089891645, phase: 5.30650048468, frequency: 20426.57109242200),
            VSOPTerm(amplitude: 0.01353968419, phase: 5.59313319619, frequency: 10213.28554621100),
            VSOPTerm(amplitude: 3.17614666774, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00014444977, phase: 0.51624564679, frequency: 20426.57109242200),
            VSOPTerm(amplitude: 0.00095707712, phase: 2.46424448979, frequency: 10213.28554621100),
            VSOPTerm(amplitude: 10213.52943052898, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00054127076, phase: 0.00000000000, frequency: 0.00000000000)
        ]
    ]

    private static let venusB: Series = [
        [
            VSOPTerm(amplitude: 0.00032814918, phase: 3.14159265359, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00040107978, phase: 1.14737178106, frequency: 20426.57109242200),
            VSOPTerm(amplitude: 0.05923638472, phase: 0.26702775813, frequency: 10213.28554621100)
        ],
        [
            VSOPTerm(amplitude: 0.00513347602, phase: 1.80364310797, frequency: 10213.28554621100)
        ],
        [
            VSOPTerm(amplitude: 0.00022377665, phase: 3.38509143877, frequency: 10213.28554621100)
        ]
    ]

    private static let venusR: Series = [
        [
            VSOPTerm(amplitude: 0.00489824185, phase: 4.02151832268, frequency: 10213.28554621100),
            VSOPTerm(amplitude: 0.72334820905, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00034551039, phase: 0.89198710598, frequency: 10213.28554621100)
        ]
    ]

    private static let earthL: Series = [
        [
            VSOPTerm(amplitude: 0.00034894275, phase: 4.62610241759, frequency: 12566.15169998280),
            VSOPTerm(amplitude: 0.03341656456, phase: 4.66925680417, frequency: 6283.07584999140),
            VSOPTerm(amplitude: 1.75347045673, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00206058863, phase: 2.67823455584, frequency: 6283.07584999140),
            VSOPTerm(amplitude: 6283.31966747491, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00052918870, phase: 0.00000000000, frequency: 0.00000000000)
        ]
    ]

    private static let earthB: Series = []

    private static let earthR: Series = [
        [
            VSOPTerm(amplitude: 0.00013956023, phase: 3.05524609620, frequency: 12566.15169998280),
            VSOPTerm(amplitude: 0.01670699626, phase: 3.09846350771, frequency: 6283.07584999140),
            VSOPTerm(amplitude: 1.00013988799, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00103018608, phase: 1.10748969588, frequency: 6283.07584999140)
        ]
    ]

    private static let marsL: Series = [
        [
            VSOPTerm(amplitude: 0.00012315897, phase: 0.84956081238, frequency: 2810.92146160520),
            VSOPTerm(amplitude: 0.00010610230, phase: 2.93958524973, frequency: 2281.23049651060),
            VSOPTerm(amplitude: 0.00027744987, phase: 5.97049512942, frequency: 3.52311834900),
            VSOPTerm(amplitude: 0.00091798394, phase: 5.75478745111, frequency: 10021.83728009940),
            VSOPTerm(amplitude: 0.01108216792, phase: 5.40099836958, frequency: 6681.22485339960),
            VSOPTerm(amplitude: 0.18656368100, phase: 5.05037100303, frequency: 3340.61242669980),
            VSOPTerm(amplitude: 6.20347711583, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00019963338, phase: 4.26594061030, frequency: 10021.83728009940),
            VSOPTerm(amplitude: 0.00164901343, phase: 3.92631250962, frequency: 6681.22485339960),
            VSOPTerm(amplitude: 0.01458227051, phase: 3.60426053609, frequency: 3340.61242669980),
            VSOPTerm(amplitude: 3340.85627474342, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00013908426, phase: 2.45742359888, frequency: 6681.22485339960),
            VSOPTerm(amplitude: 0.00054187645, phase: 0.00000000000, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00058015791, phase: 2.04979463279, frequency: 3340.61242669980)
        ]
    ]

    private static let marsB: Series = [
        [
            VSOPTerm(amplitude: 0.00031365538, phase: 4.44651052853, frequency: 10021.83728009940),
            VSOPTerm(amplitude: 0.00289104742, phase: 0.00000000000, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00298033234, phase: 4.10616996243, frequency: 6681.22485339960),
            VSOPTerm(amplitude: 0.03197134986, phase: 3.76832042432, frequency: 3340.61242669980)
        ],
        [
            VSOPTerm(amplitude: 0.00014116030, phase: 3.14159265359, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00350068845, phase: 5.36847836211, frequency: 3340.61242669980)
        ],
        [
            VSOPTerm(amplitude: 0.00016726690, phase: 0.60221392419, frequency: 3340.61242669980)
        ]
    ]

    private static let marsR: Series = [
        [
            VSOPTerm(amplitude: 0.00046179117, phase: 4.15595316284, frequency: 10021.83728009940),
            VSOPTerm(amplitude: 0.00660776357, phase: 3.81783442097, frequency: 6681.22485339960),
            VSOPTerm(amplitude: 0.14184953153, phase: 3.47971283519, frequency: 3340.61242669980),
            VSOPTerm(amplitude: 1.53033488276, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00010815880, phase: 2.70888093803, frequency: 10021.83728009940),
            VSOPTerm(amplitude: 0.00012877200, phase: 0.00000000000, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00103175886, phase: 2.37071845682, frequency: 6681.22485339960),
            VSOPTerm(amplitude: 0.01107433340, phase: 2.03250524950, frequency: 3340.61242669980)
        ],
        [
            VSOPTerm(amplitude: 0.00044242247, phase: 0.47930603943, frequency: 3340.61242669980)
        ]
    ]

    private static let jupiterL: Series = [
        [
            VSOPTerm(amplitude: 0.00013589738, phase: 5.77481031590, frequency: 1589.07289528380),
            VSOPTerm(amplitude: 0.00027964622, phase: 1.78454589485, frequency: 536.80451209540),
            VSOPTerm(amplitude: 0.00038857780, phase: 1.27231724860, frequency: 316.39186965660),
            VSOPTerm(amplitude: 0.00039806051, phase: 2.29376744855, frequency: 419.48464387520),
            VSOPTerm(amplitude: 0.00064263986, phase: 3.41145185203, frequency: 103.09277421860),
            VSOPTerm(amplitude: 0.00072903096, phase: 3.64042909255, frequency: 522.57741809380),
            VSOPTerm(amplitude: 0.00097178280, phase: 4.14264708819, frequency: 632.78373931320),
            VSOPTerm(amplitude: 0.00306389180, phase: 5.41734729976, frequency: 1059.38193018920),
            VSOPTerm(amplitude: 0.00573610145, phase: 1.44406205976, frequency: 7.11354700080),
            VSOPTerm(amplitude: 0.09695898711, phase: 5.06191793105, frequency: 529.69096509460),
            VSOPTerm(amplitude: 0.59954691495, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00012105732, phase: 0.16985765041, frequency: 536.80451209540),
            VSOPTerm(amplitude: 0.00020720943, phase: 5.45938936295, frequency: 522.57741809380),
            VSOPTerm(amplitude: 0.00027655380, phase: 4.57265956824, frequency: 1059.38193018920),
            VSOPTerm(amplitude: 0.00228918538, phase: 6.02647464016, frequency: 7.11354700080),
            VSOPTerm(amplitude: 0.00489741194, phase: 4.22066689928, frequency: 529.69096509460),
            VSOPTerm(amplitude: 529.93480757497, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00038965550, phase: 0.00000000000, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00030629053, phase: 2.93021440216, frequency: 529.69096509460),
            VSOPTerm(amplitude: 0.00047233598, phase: 4.32148323554, frequency: 7.11354700080)
        ]
    ]

    private static let jupiterB: Series = [
        [
            VSOPTerm(amplitude: 0.00110090358, phase: 0.00000000000, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00109971634, phase: 3.90809347389, frequency: 1059.38193018920),
            VSOPTerm(amplitude: 0.02268615703, phase: 3.55852606718, frequency: 529.69096509460)
        ],
        [
            VSOPTerm(amplitude: 0.00177351787, phase: 5.70166488486, frequency: 529.69096509460)
        ]
    ]

    private static let jupiterR: Series = [
        [
            VSOPTerm(amplitude: 0.00012749004, phase: 2.71550102862, frequency: 1052.26838318840),
            VSOPTerm(amplitude: 0.00013032600, phase: 2.96043055741, frequency: 1162.47470440780),
            VSOPTerm(amplitude: 0.00023947340, phase: 0.27457854894, frequency: 7.11354700080),
            VSOPTerm(amplitude: 0.00022283710, phase: 4.19362773546, frequency: 1589.07289528380),
            VSOPTerm(amplitude: 0.00023453209, phase: 3.54023147303, frequency: 735.87651353180),
            VSOPTerm(amplitude: 0.00030135275, phase: 2.16132058449, frequency: 949.17560896980),
            VSOPTerm(amplitude: 0.00029134620, phase: 1.67759243710, frequency: 103.09277421860),
            VSOPTerm(amplitude: 0.00065517227, phase: 5.97995850843, frequency: 316.39186965660),
            VSOPTerm(amplitude: 0.00072062869, phase: 0.21465694745, frequency: 536.80451209540),
            VSOPTerm(amplitude: 0.00086792941, phase: 0.71001090609, frequency: 419.48464387520),
            VSOPTerm(amplitude: 0.00187647391, phase: 2.07590380082, frequency: 522.57741809380),
            VSOPTerm(amplitude: 0.00282029465, phase: 2.57419879933, frequency: 632.78373931320),
            VSOPTerm(amplitude: 0.00610599902, phase: 3.84115365602, frequency: 1059.38193018920),
            VSOPTerm(amplitude: 0.25209327020, phase: 3.49108640015, frequency: 529.69096509460),
            VSOPTerm(amplitude: 5.20887429471, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00011847190, phase: 2.41329588176, frequency: 419.48464387520),
            VSOPTerm(amplitude: 0.00041390257, phase: 0.00000000000, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00031185167, phase: 4.88276663526, frequency: 536.80451209540),
            VSOPTerm(amplitude: 0.00053443592, phase: 3.89717644226, frequency: 522.57741809380),
            VSOPTerm(amplitude: 0.00061661771, phase: 3.00076251018, frequency: 1059.38193018920),
            VSOPTerm(amplitude: 0.01271801596, phase: 2.64937511122, frequency: 529.69096509460)
        ],
        [
            VSOPTerm(amplitude: 0.00079644833, phase: 1.35865896596, frequency: 529.69096509460)
        ]
    ]

    private static let saturnL: Series = [
        [
            VSOPTerm(amplitude: 0.00010725066, phase: 3.12939596466, frequency: 202.25339517410),
            VSOPTerm(amplitude: 0.00013005305, phase: 5.98119067061, frequency: 11.04570026390),
            VSOPTerm(amplitude: 0.00015053509, phase: 2.71670027883, frequency: 639.89728631400),
            VSOPTerm(amplitude: 0.00013160308, phase: 4.44891180176, frequency: 14.22709400160),
            VSOPTerm(amplitude: 0.00014609562, phase: 1.56518573691, frequency: 3.93215326310),
            VSOPTerm(amplitude: 0.00015820300, phase: 0.93808953760, frequency: 632.78373931320),
            VSOPTerm(amplitude: 0.00014906995, phase: 5.76903283845, frequency: 316.39186965660),
            VSOPTerm(amplitude: 0.00016573583, phase: 0.43719123541, frequency: 419.48464387520),
            VSOPTerm(amplitude: 0.00023990338, phase: 4.66976934860, frequency: 110.20632121940),
            VSOPTerm(amplitude: 0.00079271288, phase: 3.84007078530, frequency: 220.41264243880),
            VSOPTerm(amplitude: 0.00206816296, phase: 0.24658366938, frequency: 103.09277421860),
            VSOPTerm(amplitude: 0.00350769223, phase: 3.30329903015, frequency: 426.59819087600),
            VSOPTerm(amplitude: 0.00398379386, phase: 0.52112025957, frequency: 206.18554843720),
            VSOPTerm(amplitude: 0.01414150958, phase: 4.58581515873, frequency: 7.11354700080),
            VSOPTerm(amplitude: 0.11107659780, phase: 3.96205090194, frequency: 213.29909543800),
            VSOPTerm(amplitude: 0.87401354029, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00010511706, phase: 2.74880392800, frequency: 14.22709400160),
            VSOPTerm(amplitude: 0.00019941734, phase: 1.27954662736, frequency: 103.09277421860),
            VSOPTerm(amplitude: 0.00040254586, phase: 2.04128257090, frequency: 220.41264243880),
            VSOPTerm(amplitude: 0.00107678770, phase: 2.27769911872, frequency: 206.18554843720),
            VSOPTerm(amplitude: 0.00098323030, phase: 1.08070061328, frequency: 426.59819087600),
            VSOPTerm(amplitude: 0.00564347566, phase: 2.88500136429, frequency: 7.11354700080),
            VSOPTerm(amplitude: 0.01296855005, phase: 1.82820544701, frequency: 213.29909543800),
            VSOPTerm(amplitude: 213.54295595986, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00010604979, phase: 5.40963595885, frequency: 426.59819087600),
            VSOPTerm(amplitude: 0.00010631396, phase: 0.25778277414, frequency: 220.41264243880),
            VSOPTerm(amplitude: 0.00015276909, phase: 4.06492007503, frequency: 206.18554843720),
            VSOPTerm(amplitude: 0.00090592251, phase: 0.00000000000, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00091920844, phase: 0.07425261094, frequency: 213.29909543800),
            VSOPTerm(amplitude: 0.00116441181, phase: 1.17987850633, frequency: 7.11354700080)
        ],
        [
            VSOPTerm(amplitude: 0.00016038734, phase: 5.73945377424, frequency: 7.11354700080)
        ]
    ]

    private static let saturnB: Series = [
        [
            VSOPTerm(amplitude: 0.00014734070, phase: 2.11846597870, frequency: 639.89728631400),
            VSOPTerm(amplitude: 0.00034116063, phase: 0.57297307844, frequency: 206.18554843720),
            VSOPTerm(amplitude: 0.00030863357, phase: 3.48441504465, frequency: 220.41264243880),
            VSOPTerm(amplitude: 0.00084745939, phase: 0.00000000000, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00240348303, phase: 2.85238489390, frequency: 426.59819087600),
            VSOPTerm(amplitude: 0.04330678040, phase: 3.60284428399, frequency: 213.29909543800)
        ],
        [
            VSOPTerm(amplitude: 0.00014800587, phase: 2.30586060520, frequency: 206.18554843720),
            VSOPTerm(amplitude: 0.00018571607, phase: 6.09919206378, frequency: 426.59819087600),
            VSOPTerm(amplitude: 0.00049478641, phase: 3.14159265359, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00397554998, phase: 5.33289992556, frequency: 213.29909543800)
        ],
        [
            VSOPTerm(amplitude: 0.00020629977, phase: 0.50482422817, frequency: 213.29909543800)
        ]
    ]

    private static let saturnR: Series = [
        [
            VSOPTerm(amplitude: 0.00012884128, phase: 1.64892310393, frequency: 138.51749687070),
            VSOPTerm(amplitude: 0.00011380261, phase: 1.73105746566, frequency: 522.57741809380),
            VSOPTerm(amplitude: 0.00011993314, phase: 5.98051421881, frequency: 846.08283475120),
            VSOPTerm(amplitude: 0.00014296479, phase: 2.60433537909, frequency: 323.50541665740),
            VSOPTerm(amplitude: 0.00015298457, phase: 3.05943652881, frequency: 529.69096509460),
            VSOPTerm(amplitude: 0.00020746678, phase: 5.33255667599, frequency: 199.07200143640),
            VSOPTerm(amplitude: 0.00020839118, phase: 1.52102590640, frequency: 433.71173787680),
            VSOPTerm(amplitude: 0.00020936573, phase: 0.46349163993, frequency: 735.87651353180),
            VSOPTerm(amplitude: 0.00032401718, phase: 5.47084606947, frequency: 949.17560896980),
            VSOPTerm(amplitude: 0.00034143794, phase: 0.19518550682, frequency: 277.03499374140),
            VSOPTerm(amplitude: 0.00048913044, phase: 1.55733388472, frequency: 202.25339517410),
            VSOPTerm(amplitude: 0.00061053350, phase: 0.94037761156, frequency: 639.89728631400),
            VSOPTerm(amplitude: 0.00069007015, phase: 5.94099622447, frequency: 419.48464387520),
            VSOPTerm(amplitude: 0.00108974737, phase: 3.29313595577, frequency: 110.20632121940),
            VSOPTerm(amplitude: 0.00140617548, phase: 5.70406652991, frequency: 632.78373931320),
            VSOPTerm(amplitude: 0.00361778433, phase: 3.13904303264, frequency: 7.11354700080),
            VSOPTerm(amplitude: 0.00371684449, phase: 2.27114833428, frequency: 220.41264243880),
            VSOPTerm(amplitude: 0.00547506899, phase: 5.01532628454, frequency: 103.09277421860),
            VSOPTerm(amplitude: 0.00821891059, phase: 5.93520025371, frequency: 316.39186965660),
            VSOPTerm(amplitude: 0.01464663959, phase: 1.64763045468, frequency: 426.59819087600),
            VSOPTerm(amplitude: 0.01873679934, phase: 5.23549605091, frequency: 206.18554843720),
            VSOPTerm(amplitude: 0.52921382465, phase: 2.39226219733, frequency: 213.29909543800),
            VSOPTerm(amplitude: 9.55758135801, phase: 0.00000000000, frequency: 0.00000000000)
        ],
        [
            VSOPTerm(amplitude: 0.00013876565, phase: 0.75886204364, frequency: 199.07200143640),
            VSOPTerm(amplitude: 0.00012892827, phase: 5.94330258435, frequency: 433.71173787680),
            VSOPTerm(amplitude: 0.00018839639, phase: 1.60819563173, frequency: 110.20632121940),
            VSOPTerm(amplitude: 0.00019952612, phase: 1.17560125007, frequency: 419.48464387520),
            VSOPTerm(amplitude: 0.00020928189, phase: 5.09245654470, frequency: 639.89728631400),
            VSOPTerm(amplitude: 0.00049621111, phase: 6.01744469580, frequency: 103.09277421860),
            VSOPTerm(amplitude: 0.00143891176, phase: 1.40744864239, frequency: 7.11354700080),
            VSOPTerm(amplitude: 0.00186261540, phase: 3.14159265359, frequency: 0.00000000000),
            VSOPTerm(amplitude: 0.00188491375, phase: 0.47215719444, frequency: 220.41264243880),
            VSOPTerm(amplitude: 0.00341394136, phase: 5.79635773960, frequency: 426.59819087600),
            VSOPTerm(amplitude: 0.00506577574, phase: 0.71114650941, frequency: 206.18554843720),
            VSOPTerm(amplitude: 0.06182981282, phase: 0.25843515034, frequency: 213.29909543800)
        ],
        [
            VSOPTerm(amplitude: 0.00029645554, phase: 5.96310264282, frequency: 7.11354700080),
            VSOPTerm(amplitude: 0.00043220894, phase: 3.86940443794, frequency: 426.59819087600),
            VSOPTerm(amplitude: 0.00049766792, phase: 4.97168150870, frequency: 220.41264243880),
            VSOPTerm(amplitude: 0.00071922760, phase: 2.50069994874, frequency: 206.18554843720),
            VSOPTerm(amplitude: 0.00436902464, phase: 4.78671673044, frequency: 213.29909543800)
        ],
        [
            VSOPTerm(amplitude: 0.00020315005, phase: 3.02186626038, frequency: 213.29909543800)
        ]
    ]
}

enum AstroCalculator {
    struct TideEstimate: Equatable {
        let typeText: String
        let highTides: [Date]

        func summaryText(calendar: Calendar) -> String {
            guard !highTides.isEmpty else {
                return typeText
            }

            let timeText = highTides
                .prefix(2)
                .map { $0.clockText(calendar: calendar) }
                .joined(separator: "/")
            return "\(typeText) · 时间\(timeText)"
        }
    }

    static func forecast(for date: Date, site: ObservationSite) -> AstroForecast {
        let moon = moonPosition(at: date, site: site)
        let phase = moonPhase(at: date)
        let moonEvents = nextMoonRiseSet(after: date, site: site)
        let sunrise = sunEvent(on: date, site: site, isSunrise: true)
        let sunset = sunEvent(on: date, site: site, isSunrise: false)
        let calendar = site.solarCalendar
        let sunriseTomorrow = calendar.date(byAdding: .day, value: 1, to: date).flatMap {
            sunEvent(on: $0, site: site, isSunrise: true)
        }
        let planets = planetVisibility(for: date, site: site, sunset: sunset, sunrise: sunriseTomorrow)
        let window = observingWindow(
            on: date,
            site: site,
            sunset: sunset,
            sunriseTomorrow: sunriseTomorrow,
            moonSet: moonEvents.set,
            moonAltitude: moon.altitude,
            moonIllumination: phase.illumination
        )
        let factors = radarFactors(
            site: site,
            date: date,
            moonAltitude: moon.altitude,
            moonIllumination: phase.illumination
        )

        return AstroForecast(
            date: date,
            site: site,
            moonPhaseName: phase.name,
            moonIlluminationPercent: Int((phase.illumination * 100).rounded()),
            moonAltitudeDegrees: Int(moon.altitude.rounded()),
            moonAzimuthText: azimuthText(moon.azimuth),
            moonRise: moonEvents.rise,
            moonSet: moonEvents.set,
            sunrise: sunrise,
            sunset: sunset,
            stargazingWindow: window,
            radarFactors: factors,
            visiblePlanets: planets
        )
    }

    static func tideSummary(for date: Date, site: ObservationSite) -> String {
        tideEstimate(for: date, site: site).summaryText(calendar: site.solarCalendar)
    }

    private static func observingWindow(
        on date: Date,
        site: ObservationSite,
        sunset: Date?,
        sunriseTomorrow: Date?,
        moonSet: Date?,
        moonAltitude: Double,
        moonIllumination: Double
    ) -> StargazingWindow {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let defaultSunset = calendar.date(bySettingHour: 18, minute: 40, second: 0, of: dayStart) ?? date
        let darkStart = (sunset ?? defaultSunset).addingTimeInterval(85 * 60)
        let defaultEnd = calendar.date(byAdding: .hour, value: 6, to: dayStart.addingTimeInterval(24 * 60 * 60)) ?? darkStart
        let darkEnd = (sunriseTomorrow ?? defaultEnd).addingTimeInterval(-70 * 60)

        var start = darkStart
        if moonIllumination > 0.55, moonAltitude > 8, let moonSet, moonSet > darkStart, moonSet < darkEnd {
            start = moonSet.addingTimeInterval(10 * 60)
        }

        let end = min(start.addingTimeInterval(90 * 60), darkEnd)
        let moonPenalty = moonAltitude > 8 ? Int((moonIllumination * 34).rounded()) : 0
        let cloudPenalty = site.cloudCoverPercent.map { $0 / 2 } ?? 28
        let lightPenalty = site.bortleClass.map { $0 * 5 } ?? 0
        let score = min(max(92 - moonPenalty - cloudPenalty - lightPenalty, 0), 100)

        guard end.timeIntervalSince(start) >= 40 * 60 else {
            return StargazingWindow(start: nil, end: nil, score: score, summary: "今晚窗口较短")
        }

        return StargazingWindow(start: start, end: end, score: score, summary: "今晚条件一般")
    }

    private static func radarFactors(
        site: ObservationSite,
        date: Date,
        moonAltitude: Double,
        moonIllumination: Double
    ) -> [AstroRadarFactor] {
        let moonScore = moonAltitude > 8 ? Int(((1 - moonIllumination) * 100).rounded()) : 92
        let cloudScore = site.cloudCoverPercent.map { max(100 - $0, 0) } ?? 0

        return [
            twilightFactor(id: "civil", title: "民", depression: 6, date: date, site: site),
            twilightFactor(id: "nautical", title: "航", depression: 12, date: date, site: site),
            twilightFactor(id: "astronomical", title: "天", depression: 18, date: date, site: site),
            AstroRadarFactor(id: "moon", title: "月光", valueText: "\(Int((moonIllumination * 100).rounded()))%", score: moonScore),
            AstroRadarFactor(id: "cloud", title: "云量", valueText: site.cloudCoverPercent.map { "\($0)%" } ?? "N/A", score: cloudScore),
            AstroRadarFactor(id: "light", title: "光害", valueText: "N/A", score: 0)
        ]
    }

    private static func twilightFactor(
        id: String,
        title: String,
        depression: Double,
        date: Date,
        site: ObservationSite
    ) -> AstroRadarFactor {
        let calendar = site.solarCalendar
        let nextMorning = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(24 * 60 * 60)
        let eveningEnd = sunEvent(on: date, site: site, isSunrise: false, zenith: 90 + depression)
        let morningStart = sunEvent(on: nextMorning, site: site, isSunrise: true, zenith: 90 + depression)
        let valueText = twilightText(end: eveningEnd, start: morningStart, calendar: calendar)
        return AstroRadarFactor(
            id: id,
            title: title,
            valueText: valueText,
            score: eveningEnd == nil || morningStart == nil ? 0 : 86
        )
    }

    private static func twilightText(end: Date?, start: Date?, calendar: Calendar) -> String {
        guard let end, let start else { return "N/A" }
        return "终\(end.clockText(calendar: calendar))/始\(start.clockText(calendar: calendar))"
    }

    private static func planetVisibility(
        for date: Date,
        site: ObservationSite,
        sunset: Date?,
        sunrise: Date?
    ) -> [PlanetVisibility] {
        let eveningStart = sunset?.addingTimeInterval(45 * 60) ?? date
        let morningEnd = sunrise ?? date.addingTimeInterval(9 * 60 * 60)

        return PlanetBody.visiblePlanets.compactMap { planet in
            let horizontal = planetHorizontalPosition(planet: planet, at: date, site: site)
            let riseTime = nextRiseTime(for: planet, after: date, site: site)
            let bestTime = bestObservationTime(
                for: planet,
                date: date,
                site: site,
                eveningStart: eveningStart,
                morningEnd: morningEnd
            )

            return PlanetVisibility(
                id: planet.name,
                name: planet.name,
                altitudeDegrees: Int(horizontal.altitude.rounded()),
                azimuthText: compactBearingText(horizontal.azimuth),
                riseTime: riseTime,
                bestObservationTime: bestTime
            )
        }
        .sorted { lhs, rhs in
            let lhsAltitude = lhs.altitudeDegrees ?? -90
            let rhsAltitude = rhs.altitudeDegrees ?? -90
            if lhsAltitude == rhsAltitude {
                return (lhs.bestObservationTime ?? .distantFuture) < (rhs.bestObservationTime ?? .distantFuture)
            }

            return lhsAltitude > rhsAltitude
        }
    }

    private static func planetHorizontalPosition(
        planet: PlanetBody,
        at date: Date,
        site: ObservationSite
    ) -> (altitude: Double, azimuth: Double) {
        let equatorial = planetEquatorialPosition(planet: planet, at: date)
        return horizontalCoordinates(
            rightAscension: equatorial.rightAscension,
            declination: equatorial.declination,
            at: date,
            site: site
        )
    }

    private static func nextRiseTime(for planet: PlanetBody, after date: Date, site: ObservationSite) -> Date? {
        let start = date
        let end = date.addingTimeInterval(30 * 60 * 60)
        var previousDate = start
        var previousAltitude = planetHorizontalPosition(planet: planet, at: start, site: site).altitude
        var currentDate = start.addingTimeInterval(20 * 60)

        while currentDate <= end {
            let currentAltitude = planetHorizontalPosition(planet: planet, at: currentDate, site: site).altitude
            if previousAltitude < 0, currentAltitude >= 0 {
                return interpolatedCrossing(
                    previousDate: previousDate,
                    previousAltitude: previousAltitude,
                    currentDate: currentDate,
                    currentAltitude: currentAltitude
                )
            }

            previousDate = currentDate
            previousAltitude = currentAltitude
            currentDate = currentDate.addingTimeInterval(20 * 60)
        }

        return nil
    }

    private static func bestObservationTime(
        for planet: PlanetBody,
        date: Date,
        site: ObservationSite,
        eveningStart: Date,
        morningEnd: Date
    ) -> Date? {
        var bestDate: Date?
        var bestAltitude = -90.0
        var currentDate = eveningStart

        while currentDate <= morningEnd {
            let altitude = planetHorizontalPosition(planet: planet, at: currentDate, site: site).altitude
            if altitude > bestAltitude {
                bestAltitude = altitude
                bestDate = currentDate
            }

            currentDate = currentDate.addingTimeInterval(30 * 60)
        }

        guard bestAltitude > 5 else { return nil }
        return bestDate
    }

    private static func nextMoonRiseSet(after date: Date, site: ObservationSite) -> (rise: Date?, set: Date?) {
        let start = date.addingTimeInterval(-10 * 60)
        var previousDate = start
        var previousAltitude = moonHorizonValue(at: start, site: site)
        var rise: Date?
        var set: Date?

        for minute in stride(from: 5, through: 36 * 60, by: 5) {
            let currentDate = start.addingTimeInterval(Double(minute) * 60)
            let currentAltitude = moonHorizonValue(at: currentDate, site: site)

            if rise == nil, previousAltitude < 0, currentAltitude >= 0 {
                let crossing = refinedMoonHorizonCrossing(
                    previousDate: previousDate,
                    currentDate: currentDate,
                    site: site
                )
                if crossing >= date {
                    rise = crossing
                }
            }

            if set == nil, previousAltitude >= 0, currentAltitude < 0 {
                let crossing = refinedMoonHorizonCrossing(
                    previousDate: previousDate,
                    currentDate: currentDate,
                    site: site
                )
                if crossing >= date {
                    set = crossing
                }
            }

            previousDate = currentDate
            previousAltitude = currentAltitude
        }

        return (rise, set)
    }

    private static func moonRiseSet(on date: Date, site: ObservationSite) -> (rise: Date?, set: Date?) {
        let calendar = site.solarCalendar
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        let searchStart = dayStart.addingTimeInterval(-60 * 60)
        let searchEnd = dayEnd.addingTimeInterval(60 * 60)
        var previousDate = searchStart
        var previousAltitude = moonHorizonValue(at: searchStart, site: site)
        var rise: Date?
        var set: Date?
        var currentDate = searchStart.addingTimeInterval(5 * 60)

        while currentDate <= searchEnd {
            let currentAltitude = moonHorizonValue(at: currentDate, site: site)

            if rise == nil, previousAltitude < 0, currentAltitude >= 0 {
                let crossing = refinedMoonHorizonCrossing(
                    previousDate: previousDate,
                    currentDate: currentDate,
                    site: site
                )
                if crossing >= dayStart, crossing < dayEnd {
                    rise = crossing
                }
            }

            if set == nil, previousAltitude >= 0, currentAltitude < 0 {
                let crossing = refinedMoonHorizonCrossing(
                    previousDate: previousDate,
                    currentDate: currentDate,
                    site: site
                )
                if crossing >= dayStart, crossing < dayEnd {
                    set = crossing
                }
            }

            previousDate = currentDate
            previousAltitude = currentAltitude
            currentDate = currentDate.addingTimeInterval(5 * 60)
        }

        return (rise, set)
    }

    private static func tideEstimate(for date: Date, site: ObservationSite) -> TideEstimate {
        let phaseAge = moonPhaseAge(at: date)
        let typeText = tideTypeText(phaseAge: phaseAge)
        let calendar = site.solarCalendar
        let dayStart = calendar.startOfDay(for: date)
        let highTides = estimatedHighTides(on: dayStart, site: site)
        return TideEstimate(typeText: typeText, highTides: highTides)
    }

    private static func tideTypeText(phaseAge: Double) -> String {
        let synodicMonth = 29.530588853
        let quarter = synodicMonth / 4
        let nearestSpringDistance = min(phaseAge, abs(phaseAge - synodicMonth), abs(phaseAge - synodicMonth / 2))
        let nearestNeapDistance = min(abs(phaseAge - quarter), abs(phaseAge - quarter * 3))

        if nearestSpringDistance <= 2.2 {
            return "大潮"
        }

        if nearestNeapDistance <= 2.2 {
            return "小潮"
        }

        return "中潮"
    }

    private static func estimatedHighTides(on dayStart: Date, site: ObservationSite) -> [Date] {
        let searchStart = dayStart.addingTimeInterval(-13 * 60 * 60)
        let searchEnd = dayStart.addingTimeInterval(37 * 60 * 60)
        var previousDate = searchStart
        var previousHourAngle = moonHourAngle(at: searchStart, site: site)
        var transits: [Date] = []
        var currentDate = searchStart.addingTimeInterval(20 * 60)

        while currentDate <= searchEnd {
            let currentHourAngle = moonHourAngle(at: currentDate, site: site)
            if previousHourAngle <= 0, currentHourAngle > 0 {
                transits.append(interpolatedAngleCrossing(
                    previousDate: previousDate,
                    previousAngle: previousHourAngle,
                    currentDate: currentDate,
                    currentAngle: currentHourAngle
                ))
            }

            previousDate = currentDate
            previousHourAngle = currentHourAngle
            currentDate = currentDate.addingTimeInterval(20 * 60)
        }

        let dayEnd = dayStart.addingTimeInterval(24 * 60 * 60)
        let highTides = transits
            .flatMap { transit in
                [
                    transit.addingTimeInterval(50 * 60),
                    transit.addingTimeInterval(12 * 60 * 60 + 25 * 60)
                ]
            }
            .filter { $0 >= dayStart && $0 < dayEnd }
            .sorted()

        return Array(highTides.prefix(2))
    }

    private static func moonPhaseAge(at date: Date) -> Double {
        let synodicMonth = 29.530588853
        let knownNewMoon = 2_451_550.1
        return positiveModulo(julianDay(for: date) - knownNewMoon, synodicMonth)
    }

    private static func moonPhase(at date: Date) -> (name: String, illumination: Double) {
        let synodicMonth = 29.530588853
        let age = moonPhaseAge(at: date)
        let illumination = (1 - cos(2 * .pi * age / synodicMonth)) / 2

        switch age {
        case 0..<1.85, 27.68...synodicMonth:
            return ("新月", illumination)
        case 1.85..<5.54:
            return ("娥眉月", illumination)
        case 5.54..<9.23:
            return ("上弦月", illumination)
        case 9.23..<12.92:
            return ("盈凸月", illumination)
        case 12.92..<16.61:
            return ("满月", illumination)
        case 16.61..<20.30:
            return ("亏凸月", illumination)
        case 20.30..<23.99:
            return ("下弦月", illumination)
        default:
            return ("残月", illumination)
        }
    }

    private static func moonPosition(at date: Date, site: ObservationSite) -> (altitude: Double, azimuth: Double, distanceEarthRadii: Double) {
        let equatorial = moonEquatorialPosition(at: date)
        let distance = max(equatorial.distanceEarthRadii, 1)
        let localSiderealTime = degreesToRadians(normalizedDegrees(greenwichSiderealTime(at: date) * 15 + site.longitude))
        let latitudeRadians = degreesToRadians(site.latitude)

        let geocentricX = distance * cos(equatorial.declination) * cos(equatorial.rightAscension)
        let geocentricY = distance * cos(equatorial.declination) * sin(equatorial.rightAscension)
        let geocentricZ = distance * sin(equatorial.declination)

        let geocentricLatitude = atan(0.99664719 * tan(latitudeRadians))
        let observerX = cos(geocentricLatitude) * cos(localSiderealTime)
        let observerY = cos(geocentricLatitude) * sin(localSiderealTime)
        let observerZ = 0.99664719 * sin(geocentricLatitude)

        let topocentricX = geocentricX - observerX
        let topocentricY = geocentricY - observerY
        let topocentricZ = geocentricZ - observerZ
        let topocentricRightAscension = atan2(topocentricY, topocentricX)
        let topocentricDeclination = atan2(
            topocentricZ,
            sqrt(topocentricX * topocentricX + topocentricY * topocentricY)
        )

        let horizontal = horizontalCoordinates(
            rightAscension: topocentricRightAscension,
            declination: topocentricDeclination,
            at: date,
            site: site
        )

        return (horizontal.altitude, horizontal.azimuth, distance)
    }

    private static func moonHourAngle(at date: Date, site: ObservationSite) -> Double {
        let equatorial = moonEquatorialPosition(at: date)
        let localSiderealTime = degreesToRadians(normalizedDegrees(greenwichSiderealTime(at: date) * 15 + site.longitude))
        return normalizedRadians(localSiderealTime - equatorial.rightAscension)
    }

    private static func moonHorizonValue(at date: Date, site: ObservationSite) -> Double {
        let position = moonPosition(at: date, site: site)
        let horizontalParallax = radiansToDegrees(asin(1 / max(position.distanceEarthRadii, 1)))
        let apparentRadius = 0.2725 * horizontalParallax
        let refraction = 0.5667
        return position.altitude + refraction + apparentRadius
    }

    private static func refinedMoonHorizonCrossing(
        previousDate: Date,
        currentDate: Date,
        site: ObservationSite
    ) -> Date {
        var lowerDate = previousDate
        var upperDate = currentDate
        var lowerValue = moonHorizonValue(at: lowerDate, site: site)

        for _ in 0..<12 {
            let midpoint = lowerDate.addingTimeInterval(upperDate.timeIntervalSince(lowerDate) / 2)
            let midpointValue = moonHorizonValue(at: midpoint, site: site)

            if (lowerValue < 0 && midpointValue >= 0) || (lowerValue >= 0 && midpointValue < 0) {
                upperDate = midpoint
            } else {
                lowerDate = midpoint
                lowerValue = midpointValue
            }
        }

        return lowerDate.addingTimeInterval(upperDate.timeIntervalSince(lowerDate) / 2)
    }

    private static func moonEquatorialPosition(at date: Date) -> (rightAscension: Double, declination: Double, distanceEarthRadii: Double) {
        let d = julianDay(for: date) - 2_451_543.5
        let nodeDegrees = normalizedDegrees(125.1228 - 0.0529538083 * d)
        let perigeeDegrees = normalizedDegrees(318.0634 + 0.1643573223 * d)
        let meanAnomalyDegrees = normalizedDegrees(115.3654 + 13.0649929509 * d)
        let node = degreesToRadians(nodeDegrees)
        let inclination = degreesToRadians(5.1454)
        let perigee = degreesToRadians(perigeeDegrees)
        let eccentricity = 0.0549
        let meanAnomaly = degreesToRadians(meanAnomalyDegrees)
        let eccentricAnomaly = meanAnomaly + eccentricity * sin(meanAnomaly) * (1 + eccentricity * cos(meanAnomaly))
        let xv = cos(eccentricAnomaly) - eccentricity
        let yv = sqrt(1 - eccentricity * eccentricity) * sin(eccentricAnomaly)
        let trueAnomaly = atan2(yv, xv)
        let radius = 60.2666 * sqrt(xv * xv + yv * yv)

        let xh = radius * (cos(node) * cos(trueAnomaly + perigee) - sin(node) * sin(trueAnomaly + perigee) * cos(inclination))
        let yh = radius * (sin(node) * cos(trueAnomaly + perigee) + cos(node) * sin(trueAnomaly + perigee) * cos(inclination))
        let zh = radius * sin(trueAnomaly + perigee) * sin(inclination)
        var longitudeDegrees = normalizedDegrees(radiansToDegrees(atan2(yh, xh)))
        var latitudeDegrees = radiansToDegrees(atan2(zh, sqrt(xh * xh + yh * yh)))
        var distance = radius

        let sunMeanAnomaly = normalizedDegrees(356.0470 + 0.9856002585 * d)
        let sunMeanLongitude = normalizedDegrees(sunMeanAnomaly + 282.9404 + 4.70935e-5 * d)
        let moonMeanLongitude = normalizedDegrees(nodeDegrees + perigeeDegrees + meanAnomalyDegrees)
        let elongation = normalizedDegrees(moonMeanLongitude - sunMeanLongitude)
        let argumentOfLatitude = normalizedDegrees(moonMeanLongitude - nodeDegrees)

        longitudeDegrees += -1.274 * sinDegrees(meanAnomalyDegrees - 2 * elongation)
            + 0.658 * sinDegrees(2 * elongation)
            - 0.186 * sinDegrees(sunMeanAnomaly)
            - 0.059 * sinDegrees(2 * meanAnomalyDegrees - 2 * elongation)
            - 0.057 * sinDegrees(meanAnomalyDegrees - 2 * elongation + sunMeanAnomaly)
            + 0.053 * sinDegrees(meanAnomalyDegrees + 2 * elongation)
            + 0.046 * sinDegrees(2 * elongation - sunMeanAnomaly)
            + 0.041 * sinDegrees(meanAnomalyDegrees - sunMeanAnomaly)
            - 0.035 * sinDegrees(elongation)
            - 0.031 * sinDegrees(meanAnomalyDegrees + sunMeanAnomaly)
            - 0.015 * sinDegrees(2 * argumentOfLatitude - 2 * elongation)
            + 0.011 * sinDegrees(meanAnomalyDegrees - 4 * elongation)

        latitudeDegrees += -0.173 * sinDegrees(argumentOfLatitude - 2 * elongation)
            - 0.055 * sinDegrees(meanAnomalyDegrees - argumentOfLatitude - 2 * elongation)
            - 0.046 * sinDegrees(meanAnomalyDegrees + argumentOfLatitude - 2 * elongation)
            + 0.033 * sinDegrees(argumentOfLatitude + 2 * elongation)
            + 0.017 * sinDegrees(2 * meanAnomalyDegrees + argumentOfLatitude)

        distance += -0.58 * cosDegrees(meanAnomalyDegrees - 2 * elongation)
            - 0.46 * cosDegrees(2 * elongation)

        let longitude = degreesToRadians(normalizedDegrees(longitudeDegrees))
        let latitude = degreesToRadians(latitudeDegrees)
        let obliquity = degreesToRadians(23.4393 - 3.563e-7 * d)
        let xe = cos(longitude) * cos(latitude)
        let ye = sin(longitude) * cos(latitude) * cos(obliquity) - sin(latitude) * sin(obliquity)
        let ze = sin(longitude) * cos(latitude) * sin(obliquity) + sin(latitude) * cos(obliquity)
        let rightAscension = atan2(ye, xe)
        let declination = atan2(ze, sqrt(xe * xe + ye * ye))

        return (rightAscension, declination, distance)
    }

    private static func planetEquatorialPosition(
        planet: PlanetBody,
        at date: Date
    ) -> (rightAscension: Double, declination: Double) {
        let julianDay = julianDay(for: date)
        let planetPosition = VSOP87DTable.position(for: planet, julianDay: julianDay).rectangular
        let earthPosition = VSOP87DTable.earthPosition(julianDay: julianDay).rectangular
        let xg = planetPosition.x - earthPosition.x
        let yg = planetPosition.y - earthPosition.y
        let zg = planetPosition.z - earthPosition.z
        let d = julianDay - 2_451_545.0
        let obliquity = degreesToRadians(23.439291 - 0.0130042 * (d / 36_525.0))
        let xe = xg
        let ye = yg * cos(obliquity) - zg * sin(obliquity)
        let ze = yg * sin(obliquity) + zg * cos(obliquity)
        let rightAscension = atan2(ye, xe)
        let declination = atan2(ze, sqrt(xe * xe + ye * ye))

        return (rightAscension, declination)
    }

    private static func horizontalCoordinates(
        rightAscension: Double,
        declination: Double,
        at date: Date,
        site: ObservationSite
    ) -> (altitude: Double, azimuth: Double) {
        let localSiderealTime = degreesToRadians(normalizedDegrees(greenwichSiderealTime(at: date) * 15 + site.longitude))
        let hourAngle = localSiderealTime - rightAscension
        let latitudeRadians = degreesToRadians(site.latitude)
        let altitude = asin(sin(declination) * sin(latitudeRadians) + cos(declination) * cos(latitudeRadians) * cos(hourAngle))
        let azimuth = atan2(
            -sin(hourAngle),
            tan(declination) * cos(latitudeRadians) - sin(latitudeRadians) * cos(hourAngle)
        )

        return (radiansToDegrees(altitude), normalizedDegrees(radiansToDegrees(azimuth)))
    }

    private static func sunEvent(
        on date: Date,
        site: ObservationSite,
        isSunrise: Bool,
        zenith: Double = 90.833
    ) -> Date? {
        let calendar = site.solarCalendar
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }

        let lngHour = site.longitude / 15
        let t = Double(dayOfYear) + ((isSunrise ? 6 : 18) - lngHour) / 24
        let meanAnomaly = 0.9856 * t - 3.289
        var trueLongitude = meanAnomaly
            + 1.916 * sin(degreesToRadians(meanAnomaly))
            + 0.020 * sin(degreesToRadians(2 * meanAnomaly))
            + 282.634
        trueLongitude = normalizedDegrees(trueLongitude)

        var rightAscension = radiansToDegrees(atan(0.91764 * tan(degreesToRadians(trueLongitude))))
        rightAscension = normalizedDegrees(rightAscension)
        rightAscension += floor(trueLongitude / 90) * 90 - floor(rightAscension / 90) * 90
        rightAscension /= 15

        let sinDeclination = 0.39782 * sin(degreesToRadians(trueLongitude))
        let cosDeclination = cos(asin(sinDeclination))
        let cosHourAngle = (
            cos(degreesToRadians(zenith)) - sinDeclination * sin(degreesToRadians(site.latitude))
        ) / (cosDeclination * cos(degreesToRadians(site.latitude)))

        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }

        var hourAngle = radiansToDegrees(acos(cosHourAngle))
        if isSunrise {
            hourAngle = 360 - hourAngle
        }
        hourAngle /= 15

        let localMeanTime = hourAngle + rightAscension - 0.06571 * t - 6.622
        let universalTime = normalizedHour(localMeanTime - lngHour)
        let localTime = normalizedHour(universalTime + Double(calendar.timeZone.secondsFromGMT(for: date)) / 3_600)
        return dateAtLocalHour(localTime, near: date, calendar: calendar)
    }

    private static func interpolatedCrossing(
        previousDate: Date,
        previousAltitude: Double,
        currentDate: Date,
        currentAltitude: Double
    ) -> Date {
        let fraction = abs(previousAltitude) / max(abs(previousAltitude) + abs(currentAltitude), 0.001)
        return previousDate.addingTimeInterval(currentDate.timeIntervalSince(previousDate) * fraction)
    }

    private static func interpolatedAngleCrossing(
        previousDate: Date,
        previousAngle: Double,
        currentDate: Date,
        currentAngle: Double
    ) -> Date {
        let fraction = abs(previousAngle) / max(abs(previousAngle) + abs(currentAngle), 0.001)
        return previousDate.addingTimeInterval(currentDate.timeIntervalSince(previousDate) * fraction)
    }

    private static func dateAtLocalHour(_ hour: Double, near date: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let wholeHours = Int(floor(hour))
        let minutes = Int(((hour - Double(wholeHours)) * 60).rounded())
        return dayStart.addingTimeInterval(Double(wholeHours * 60 + minutes) * 60)
    }

    private static func utcDate(matchingCivilDateOf date: Date, hour: Double) -> Date? {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        let components = localCalendar.dateComponents([.year, .month, .day], from: date)
        var utcComponents = DateComponents()
        utcComponents.timeZone = TimeZone(secondsFromGMT: 0)
        utcComponents.year = components.year
        utcComponents.month = components.month
        utcComponents.day = components.day
        utcComponents.hour = Int(floor(hour))
        utcComponents.minute = Int(((hour - floor(hour)) * 60).rounded())
        return Calendar(identifier: .gregorian).date(from: utcComponents)
    }

    private static func greenwichSiderealTime(at date: Date) -> Double {
        let d = julianDay(for: date) - 2_451_545.0
        return normalizedHour(18.697374558 + 24.06570982441908 * d)
    }

    private static func julianDay(for date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    private static func azimuthText(_ degrees: Double) -> String {
        switch normalizedDegrees(degrees) {
        case 22.5..<67.5:
            return "东北"
        case 67.5..<112.5:
            return "东"
        case 112.5..<157.5:
            return "东南"
        case 157.5..<202.5:
            return "南"
        case 202.5..<247.5:
            return "西南"
        case 247.5..<292.5:
            return "西"
        case 292.5..<337.5:
            return "西北"
        default:
            return "北"
        }
    }

    private static func bearingText(_ degrees: Double) -> String {
        let degrees = normalizedDegrees(degrees)

        switch degrees {
        case 0..<90:
            return bearingText(
                primary: "N",
                secondary: "E",
                firstOffset: degrees,
                secondOffset: 90 - degrees
            )
        case 90..<180:
            return bearingText(
                primary: "E",
                secondary: "S",
                firstOffset: degrees - 90,
                secondOffset: 180 - degrees
            )
        case 180..<270:
            return bearingText(
                primary: "S",
                secondary: "W",
                firstOffset: degrees - 180,
                secondOffset: 270 - degrees
            )
        default:
            return bearingText(
                primary: "W",
                secondary: "N",
                firstOffset: degrees - 270,
                secondOffset: 360 - degrees
            )
        }
    }

    private static func compactBearingText(_ degrees: Double) -> String {
        let degrees = normalizedDegrees(degrees)
        let directions: [(label: String, angle: Double)] = [
            ("N", 0),
            ("E", 90),
            ("S", 180),
            ("W", 270)
        ]

        if let nearest = directions.min(by: {
            angularDistance(degrees, $0.angle) < angularDistance(degrees, $1.angle)
        }), angularDistance(degrees, nearest.angle) < 20 {
            return nearest.label
        }

        switch degrees {
        case 0..<90:
            return "NE"
        case 90..<180:
            return "ES"
        case 180..<270:
            return "SW"
        default:
            return "WN"
        }
    }

    private static func angularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(normalizedDegrees(lhs - rhs))
        return min(delta, 360 - delta)
    }

    private static func bearingText(
        primary: String,
        secondary: String,
        firstOffset: Double,
        secondOffset: Double
    ) -> String {
        if firstOffset <= 45 {
            let offset = Int(firstOffset.rounded())
            return offset == 0 ? primary : "\(offset)° \(primary)\(secondary)"
        }

        let offset = Int(secondOffset.rounded())
        return offset == 0 ? secondary : "\(offset)° \(secondary)\(primary)"
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        positiveModulo(value, 360)
    }

    private static func normalizedHour(_ value: Double) -> Double {
        positiveModulo(value, 24)
    }

    private static func normalizedRadians(_ value: Double) -> Double {
        let normalized = positiveModulo(value + .pi, 2 * .pi) - .pi
        return normalized == -.pi ? .pi : normalized
    }

    private static func positiveModulo(_ value: Double, _ modulus: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: modulus)
        return result >= 0 ? result : result + modulus
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    private static func sinDegrees(_ degrees: Double) -> Double {
        sin(degreesToRadians(degrees))
    }

    private static func cosDegrees(_ degrees: Double) -> Double {
        cos(degreesToRadians(degrees))
    }
}
