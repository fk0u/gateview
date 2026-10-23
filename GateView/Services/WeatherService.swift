import Foundation

struct Weather: Equatable {
    let temperature: Int
    let symbol: String
    let label: String
}

@MainActor
final class WeatherService {
    func current(latitude: Double, longitude: Double) async throws -> Weather {
        // Open-Meteo: free, no API key.
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
            let current: Current
        }
        let c = try JSONDecoder().decode(Response.self, from: data).current
        let (symbol, label) = Self.describe(code: c.weather_code, isDay: c.is_day == 1)
        return Weather(temperature: Int(c.temperature_2m.rounded()), symbol: symbol, label: label)
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
}
