import Foundation

/// One "days until" entry, declared in theme.json:
/// `"countdowns": [{ "title": "Lebaran", "date": "2027-03-10", "symbol": "moon.stars" }]`
struct Countdown: Codable, Equatable, Identifiable {
    var title = ""
    var date = ""          // yyyy-MM-dd
    var symbol = "sparkles"
    var uid = UUID().uuidString // stable ForEach id; not encoded, and excluded from == so churn never rewrites theme.json
    var id: String { uid }

    // uid stays out of JSON: old theme.json files decode with a fresh uid from the default value.
    enum CodingKeys: String, CodingKey { case title, date, symbol }

    var target: Date? { Self.parse(date) }

    static func == (lhs: Countdown, rhs: Countdown) -> Bool {
        lhs.title == rhs.title && lhs.date == rhs.date && lhs.symbol == rhs.symbol
    }

    nonisolated static func parse(_ raw: String) -> Date? {
        guard raw.count == 10 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }

    /// Whole days from `now` (0 = today, negative once passed).
    nonisolated static func days(until target: Date, from now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
    }
}

enum CountdownService {
    /// Declared countdowns still ahead (today counts), soonest first.
    nonisolated static func upcoming(_ items: [Countdown], from now: Date = .now, calendar: Calendar = .current) -> [Countdown] {
        items.compactMap { item -> (Countdown, Int)? in
            guard let target = item.target else { return nil }
            let days = Countdown.days(until: target, from: now, calendar: calendar)
            return days >= 0 ? (item, days) : nil
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }
}
