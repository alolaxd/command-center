import Foundation

struct WeatherReport: Sendable, Equatable {
    struct Day: Sendable, Equatable, Identifiable { var id: String { date }; let date: String; let code: Int; let hi: Double; let lo: Double; let precip: Int; let gusts: Double }
    var temp: Double = 0
    var feels: Double = 0
    var humidity: Int = 0
    var wind: Double = 0
    var code: Int = 0
    var isDay = true
    var days: [Day] = []
    var fetched = Date()
}

/// Open-Meteo (free, no key) for forecasts + geocoding; RainViewer for radar tiles.
enum WeatherStore {
    struct Place: Codable, Hashable, Sendable { var name: String; var lat: Double; var lon: Double }

    static func geocode(_ name: String) async -> Place? {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(q)&count=1"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = (obj["results"] as? [[String: Any]])?.first,
              let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { return nil }
        let label = [r["name"] as? String, r["country_code"] as? String].compactMap { $0 }.joined(separator: ", ")
        return Place(name: label, lat: lat, lon: lon)
    }

    static func forecast(_ p: Place, fahrenheit: Bool) async throws -> WeatherReport {
        let unit = fahrenheit ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : ""
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(p.lat)&longitude=\(p.lon)"
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_gusts_10m_max"
            + "&timezone=auto&forecast_days=7" + unit)!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = obj["current"] as? [String: Any], let daily = obj["daily"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        var r = WeatherReport()
        r.temp = cur["temperature_2m"] as? Double ?? 0
        r.feels = cur["apparent_temperature"] as? Double ?? r.temp
        r.humidity = cur["relative_humidity_2m"] as? Int ?? 0
        r.wind = cur["wind_speed_10m"] as? Double ?? 0
        r.code = cur["weather_code"] as? Int ?? 0
        r.isDay = (cur["is_day"] as? Int ?? 1) == 1
        let dates = daily["time"] as? [String] ?? []
        let codes = daily["weather_code"] as? [Int] ?? []
        let his = daily["temperature_2m_max"] as? [Double] ?? []
        let los = daily["temperature_2m_min"] as? [Double] ?? []
        let pr = daily["precipitation_probability_max"] as? [Int?] ?? []
        let gusts = daily["wind_gusts_10m_max"] as? [Double] ?? []
        r.days = dates.indices.compactMap { i in
            guard i < codes.count, i < his.count, i < los.count else { return nil }
            return .init(date: dates[i], code: codes[i], hi: his[i], lo: los[i], precip: (i < pr.count ? pr[i] : nil) ?? 0, gusts: i < gusts.count ? gusts[i] : 0)
        }
        return r
    }

    static func radarTileTemplate() async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://api.rainviewer.com/public/weather-maps.json")!),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = obj["host"] as? String,
              let past = (obj["radar"] as? [String: Any])?["past"] as? [[String: Any]],
              let path = past.last?["path"] as? String else { return nil }
        return "\(host)\(path)/256/{z}/{x}/{y}/2/1_1.png"
    }

    /// WMO weather code → (description, SF Symbol).
    static func describe(_ code: Int, day: Bool = true) -> (String, String) {
        switch code {
        case 0: ("Clear", day ? "sun.max" : "moon.stars")
        case 1, 2: ("Partly cloudy", day ? "cloud.sun" : "cloud.moon")
        case 3: ("Overcast", "cloud")
        case 45, 48: ("Fog", "cloud.fog")
        case 51...57: ("Drizzle", "cloud.drizzle")
        case 61...67: ("Rain", code >= 65 ? "cloud.heavyrain" : "cloud.rain")
        case 71...77: ("Snow", "cloud.snow")
        case 80...82: ("Showers", "cloud.sun.rain")
        case 85, 86: ("Snow showers", "cloud.snow")
        case 95...99: ("Thunderstorm", "cloud.bolt.rain")
        default: ("—", "questionmark")
        }
    }

    static func isSevere(_ code: Int) -> Bool { [65, 67, 75, 82, 86, 95, 96, 99].contains(code) }
}
