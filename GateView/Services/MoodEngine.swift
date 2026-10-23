import Foundation

/// Ambient tint that follows the day and the prayer times.
struct Mood: Equatable {
    var name = "day"
    var tint = "#000000"     // hex colour washed over the scrim and glass
    var tintOpacity = 0.0
    var scrimDelta = 0.0     // added to the theme's scrim
}

enum MoodEngine {
    static func mood(at now: Date, prayers: [Prayer]) -> Mood {
        func time(_ key: String) -> Date? { prayers.first { $0.key == key }?.time }
        guard let fajr = time("Fajr"), let asr = time("Asr"), let maghrib = time("Maghrib"), let isha = time("Isha") else { return Mood() }
        let sunrise = fajr.addingTimeInterval(75 * 60)
        let night = isha.addingTimeInterval(60 * 60)

        switch now {
        case ..<fajr, night...:
            return Mood(name: "night", tint: "#0B1530", tintOpacity: 0.3, scrimDelta: 0.2)
        case fajr..<sunrise:
            return Mood(name: "dawn", tint: "#4A6FA5", tintOpacity: 0.2, scrimDelta: 0.05)
        case asr..<maghrib:
            // Warmer the closer Maghrib gets.
            let progress = now.timeIntervalSince(asr) / maghrib.timeIntervalSince(asr)
            return Mood(name: "golden", tint: "#F2A65A", tintOpacity: 0.06 + 0.2 * progress, scrimDelta: 0)
        case maghrib..<isha:
            return Mood(name: "dusk", tint: "#6B4E9B", tintOpacity: 0.24, scrimDelta: 0.1)
        case isha..<night:
            let progress = now.timeIntervalSince(isha) / night.timeIntervalSince(isha)
            return Mood(name: "evening", tint: "#2A2350", tintOpacity: 0.24 + 0.06 * progress, scrimDelta: 0.1 + 0.1 * progress)
        default:
            return Mood()
        }
    }
}
