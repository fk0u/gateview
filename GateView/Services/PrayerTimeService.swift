import Foundation

@MainActor
final class PrayerTimeService {
    // API key → display name. Iqamah minutes come from the theme (Settings).
    static let schedule: [(key: String, label: String)] = [
        ("Fajr", "Subuh"), ("Dhuhr", "Dzuhur"), ("Asr", "Ashar"), ("Maghrib", "Maghrib"), ("Isha", "Isya"),
    ]
    private let cacheKey = "GateView.prayerDay"

    /// Cached once per day; network only when the cache is from another day (or forced).
    func todayTimings(city: String, country: String, method: Int, force: Bool = false) async throws -> PrayerDay {
        let today = Self.dayKey(for: .now) + "|\(city)|\(country)|\(method)"
        if !force,
           let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(PrayerDay.self, from: data),
           cached.date == today {
            return cached
        }

        // HTTPS: plain http is blocked by App Transport Security.
        var components = URLComponents(string: "https://api.aladhan.com/v1/timingsByCity")!
        components.queryItems = [
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "method", value: String(method)),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let day = PrayerDay(date: today, timings: try JSONDecoder().decode(AladhanResponse.self, from: data).data.timings)
        UserDefaults.standard.set(try JSONEncoder().encode(day), forKey: cacheKey)
        return day
    }

    nonisolated static func prayers(from day: PrayerDay, on date: Date = .now, iqamah: [String: Int] = Theme().iqamah) -> [Prayer] {
        let cal = Calendar.current
        let friday = cal.component(.weekday, from: date) == 6
        return schedule.compactMap { key, label in
            // Values look like "04:12" or "04:12 (WITA)".
            guard let raw = day.timings[key] else { return nil }
            let parts = raw.prefix(5).split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2,
                  let time = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
            else { return nil }
            if friday && key == "Dhuhr" {
                return Prayer(name: "Jumat", time: time, iqamah: nil, isJumat: true, key: key)
            }
            return Prayer(name: label, time: time, iqamah: time.addingTimeInterval(Double((iqamah[key] ?? 10) * 60)), key: key)
        }
    }

    nonisolated static func phase(at now: Date, in prayers: [Prayer]) -> PrayerPhase? {
        if let current = prayers.last(where: { $0.time <= now && now < $0.end }) {
            if let iqamah = current.iqamah, now < iqamah { return .iqamah(current) }
            return .ongoing(current)
        }
        return next(after: now, in: prayers).map(PrayerPhase.upcoming)
    }

    nonisolated static func next(after now: Date, in prayers: [Prayer]) -> Prayer? {
        if let upcoming = prayers.first(where: { $0.time > now }) { return upcoming }
        // ponytail: after Isya, tomorrow's Subuh ≈ today's + 1 day (off by ~1 min); real value loads at midnight.
        guard let fajr = prayers.first else { return nil }
        let day: TimeInterval = 86_400
        return Prayer(name: fajr.name, time: fajr.time + day, iqamah: fajr.iqamah.map { $0 + day }, key: fajr.key)
    }

    nonisolated static func countdown(to target: Date, from now: Date) -> String {
        let s = max(0, Int(target.timeIntervalSince(now).rounded(.up)))
        return s >= 3600
            ? String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    nonisolated static func hijri(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "d MMMM yyyy 'H'"
        return f.string(from: date)
    }

    nonisolated static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d-%02d-%04d", c.day!, c.month!, c.year!)
    }
}
