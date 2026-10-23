import Foundation

/// One day's raw timings ("HH:mm") as cached in UserDefaults.
struct PrayerDay: Codable, Equatable {
    let date: String // dd-MM-yyyy, local
    let timings: [String: String]
}

struct Prayer: Identifiable, Equatable {
    let name: String
    let time: Date      // adzan
    let iqamah: Date?   // nil for Jumat (khutbah comes first)
    var isJumat = false
    var key = ""        // Aladhan key: Fajr, Dhuhr, Asr, Maghrib, Isha
    var id: String { name }

    /// When the congregation is roughly over.
    var end: Date { (iqamah ?? time).addingTimeInterval(isJumat ? 45 * 60 : 10 * 60) }
}

enum PrayerPhase: Equatable {
    case upcoming(Prayer) // counting down to adzan
    case iqamah(Prayer)   // adzan done, counting down to iqamah
    case ongoing(Prayer)  // sholat / khutbah in progress
}

/// Subset of the Aladhan response we use.
struct AladhanResponse: Decodable {
    struct Payload: Decodable { let timings: [String: String] }
    let data: Payload
}
