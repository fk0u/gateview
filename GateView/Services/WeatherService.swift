import Foundation

struct Weather: Equatable {
    struct Hour: Equatable, Identifiable { let time: Date; let temperature: Int; let symbol: String; let rainChance: Int; var id: Date { time } }
    struct Day: Equatable, Identifiable { let date: Date; let min: Int; let max: Int; let symbol: String; let rainChance: Int; var id: Date { date } }

    let temperature: Int
    let code: Int
    let symbol: String
    let label: String
    let feelsLike: Int
    let humidity: Int
    let wind: Int        // km/h
    let hourly: [Hour]   // next 12 h
    let daily: [Day]     // next 5 days
}

@MainActor
final class WeatherService {
    /// One request every 30 min covers the inline widget and the detail card.
    func fetch(latitude: Double, longitude: Double, unit: String) async throws -> Weather {
        // Open-Meteo: free, no API key.
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "temperature_unit", value: unit),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.parse(data, now: .now)
    }

    nonisolated static func parse(_ data: Data, now: Date) throws -> Weather {
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m, apparent_temperature, wind_speed_10m: Double
                let relative_humidity_2m, weather_code, is_day: Int
            }
            struct Hourly: Decodable {
                let time: [String]; let temperature_2m: [Double]; let weather_code: [Int]
                let precipitation_probability: [Int?]; let is_day: [Int]
            }
            struct Daily: Decodable {
                let time: [String]; let weather_code: [Int]
                let temperature_2m_max, temperature_2m_min: [Double]; let precipitation_probability_max: [Int?]
            }
            let utc_offset_seconds: Int
            let current: Current; let hourly: Hourly; let daily: Daily
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let f = DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: r.utc_offset_seconds)
        f.locale = Locale(identifier: "en_US_POSIX")

        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let hours: [Weather.Hour] = r.hourly.time.indices.compactMap { i in
            guard let t = f.date(from: r.hourly.time[i]), t > now.addingTimeInterval(-3600) else { return nil }
            return Weather.Hour(time: t, temperature: Int(r.hourly.temperature_2m[i].rounded()),
                                symbol: describe(code: r.hourly.weather_code[i], isDay: r.hourly.is_day[i] == 1).0,
                                rainChance: r.hourly.precipitation_probability[i] ?? 0)
        }
        f.dateFormat = "yyyy-MM-dd"
        let days: [Weather.Day] = r.daily.time.indices.dropFirst().compactMap { i in
            guard let d = f.date(from: r.daily.time[i]) else { return nil }
            return Weather.Day(date: d, min: Int(r.daily.temperature_2m_min[i].rounded()), max: Int(r.daily.temperature_2m_max[i].rounded()),
                               symbol: describe(code: r.daily.weather_code[i], isDay: true).0,
                               rainChance: r.daily.precipitation_probability_max[i] ?? 0)
        }

        let c = r.current
        let (symbol, label) = describe(code: c.weather_code, isDay: c.is_day == 1)
        return Weather(temperature: Int(c.temperature_2m.rounded()), code: c.weather_code, symbol: symbol, label: label,
                       feelsLike: Int(c.apparent_temperature.rounded()), humidity: c.relative_humidity_2m,
                       wind: Int(c.wind_speed_10m.rounded()), hourly: Array(hours.prefix(12)), daily: Array(days.prefix(5)))
    }

    /// WMO weather code → SF Symbol + short Indonesian label.
    nonisolated static func describe(code: Int, isDay: Bool) -> (String, String) {
        switch code {
        case 0: return (isDay ? "sun.max.fill" : "moon.stars.fill", "Cerah")
        case 1, 2: return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Cerah Berawan")
        case 3: return ("cloud.fill", "Berawan")
        case 45, 48: return ("cloud.fog.fill", "Berkabut")
        case 51...57: return ("cloud.drizzle.fill", "Gerimis")
        case 61...67, 80...82: return ("cloud.rain.fill", "Hujan")
        case 71...77, 85, 86: return ("cloud.snow.fill", "Salju")
        case 95...99: return ("cloud.bolt.rain.fill", "Badai Petir")
        default: return ("cloud.fill", "Berawan")
        }
    }

    struct Place: Decodable, Identifiable, Hashable {
        let name: String; let latitude: Double; let longitude: Double
        let country: String?; let admin1: String?
        var id: String { "\(name)\(latitude)\(longitude)" }
    }

    /// City search for Settings (Open-Meteo geocoding, no key).
    nonisolated static func search(_ query: String) async throws -> [Place] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "6"),
                                 URLQueryItem(name: "language", value: "id")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        struct Response: Decodable { let results: [Place]? }
        return try JSONDecoder().decode(Response.self, from: data).results ?? []
    }
}
