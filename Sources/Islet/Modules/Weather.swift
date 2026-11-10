import Foundation

/// Weather from Open-Meteo (free, no API key). Only the city name you set is
/// sent; no location permission is used.
@MainActor
final class WeatherService: ObservableObject {
    struct Hour: Identifiable { let id = UUID(); let date: Date; let temp: Double; let code: Int }
    struct Day: Identifiable { let id = UUID(); let date: Date; let min: Double; let max: Double; let code: Int; let rain: Double }

    static let cityKey = "islet.weather.city"
    static let enabledKey = "islet.weather.enabled"

    @Published var city: String {
        didSet { UserDefaults.standard.set(city, forKey: Self.cityKey); refresh(force: true) }
    }
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); refresh(force: true) }
    }
    @Published private(set) var resolvedCity: String?
    @Published private(set) var temperature: Double?
    @Published private(set) var code: Int = 0
    @Published private(set) var wind: Double?
    @Published private(set) var humidity: Double?
    @Published private(set) var hours: [Hour] = []
    @Published private(set) var days: [Day] = []
    @Published private(set) var failed = false

    private var lastFetch: Date?
    private var timer: Timer?

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [Self.enabledKey: true])
        city = d.string(forKey: Self.cityKey) ?? Self.cityFromTimeZone()
        enabled = d.bool(forKey: Self.enabledKey)
        let t = Timer(timeInterval: 20 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh(force: true)
    }

    /// "Europe/Moscow" → "Moscow": a sensible default without asking for location.
    static func cityFromTimeZone() -> String {
        let id = TimeZone.current.identifier
        return id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "London"
    }

    func refresh(force: Bool = false) {
        guard enabled, !city.trimmingCharacters(in: .whitespaces).isEmpty else {
            temperature = nil
            return
        }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 10 * 60 { return }
        lastFetch = Date()
        let name = city
        Task {
            do {
                let result = try await Self.fetch(city: name)
                guard name == self.city else { return }
                self.resolvedCity = result.city
                self.temperature = result.temp
                self.code = result.code
                self.wind = result.wind
                self.humidity = result.humidity
                self.hours = result.hours
                self.days = result.days
                self.failed = false
            } catch {
                self.failed = true
            }
        }
    }

    struct Result { var city: String; var temp: Double; var code: Int; var wind: Double; var humidity: Double; var hours: [Hour]; var days: [Day] }

    nonisolated static func fetch(city: String) async throws -> Result {
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geo.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        let (gData, _) = try await URLSession.shared.data(from: geo.url!)
        guard let g = try JSONSerialization.jsonObject(with: gData) as? [String: Any],
              let first = (g["results"] as? [[String: Any]])?.first,
              let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double
        else { throw URLError(.badServerResponse) }
        let resolved = first["name"] as? String ?? city

        var f = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        f.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ]
        let (fData, _) = try await URLSession.shared.data(from: f.url!)
        guard let j = try JSONSerialization.jsonObject(with: fData) as? [String: Any],
              let cur = j["current"] as? [String: Any] else { throw URLError(.cannotParseResponse) }

        func doubles(_ v: Any?) -> [Double] { (v as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? [] }
        let hourly = j["hourly"] as? [String: Any] ?? [:]
        let hTimes = doubles(hourly["time"]), hTemps = doubles(hourly["temperature_2m"]), hCodes = doubles(hourly["weather_code"])
        let now = Date().timeIntervalSince1970
        var hours: [Hour] = []
        for (i, t) in hTimes.enumerated() where t >= now - 3600 && hours.count < 8 && i < hTemps.count && i < hCodes.count {
            hours.append(Hour(date: Date(timeIntervalSince1970: t), temp: hTemps[i], code: Int(hCodes[i])))
        }
        let daily = j["daily"] as? [String: Any] ?? [:]
        let dTimes = doubles(daily["time"]), dMax = doubles(daily["temperature_2m_max"]), dMin = doubles(daily["temperature_2m_min"])
        let dCodes = doubles(daily["weather_code"]), dRain = doubles(daily["precipitation_sum"])
        var days: [Day] = []
        for (i, t) in dTimes.enumerated() where i < dMax.count && i < dMin.count && i < dCodes.count {
            days.append(Day(date: Date(timeIntervalSince1970: t), min: dMin[i], max: dMax[i], code: Int(dCodes[i]),
                            rain: i < dRain.count ? dRain[i] : 0))
        }
        return Result(city: resolved,
                      temp: (cur["temperature_2m"] as? NSNumber)?.doubleValue ?? 0,
                      code: (cur["weather_code"] as? NSNumber)?.intValue ?? 0,
                      wind: (cur["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 0,
                      humidity: (cur["relative_humidity_2m"] as? NSNumber)?.doubleValue ?? 0,
                      hours: hours, days: days)
    }

    /// WMO weather code → SF Symbol.
    static func symbol(_ code: Int, night: Bool = false) -> String {
        switch code {
        case 0: return night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var symbol: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return Self.symbol(code, night: hour < 6 || hour >= 21)
    }

    var temperatureText: String? {
        temperature.map { "\(Int($0.rounded()))°" }
    }
}
