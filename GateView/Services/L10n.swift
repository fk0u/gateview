import Foundation

/// Minimal Indonesian/English string switch. `lang` is `Theme.displayLanguage` ("id" | "en"),
/// so every caller stays reactive to theme.json without its own observation.
enum L10n {
    static func tr(_ lang: String, _ id: String, _ en: String) -> String {
        lang == "id" ? id : en
    }

    static func greeting(for date: Date, name: String, lang: String) -> String {
        let suffix = name.isEmpty ? "" : ", \(name)"
        let hour = Calendar.current.component(.hour, from: date)
        if lang == "id" {
            switch hour {
            case 4..<11: return "Selamat Pagi" + suffix
            case 11..<15: return "Selamat Siang" + suffix
            case 15..<18: return "Selamat Sore" + suffix
            default: return "Selamat Malam" + suffix
            }
        }
        switch hour {
        case 4..<12: return "Good Morning" + suffix
        case 12..<18: return "Good Afternoon" + suffix
        default: return "Good Evening" + suffix
        }
    }

    static func daysLeft(_ n: Int, lang: String) -> String {
        switch (lang, n) {
        case ("id", 0): return "Hari ini!"
        case ("id", 1): return "Besok"
        case ("id", _): return "\(n) hari lagi"
        case (_, 0): return "Today!"
        case (_, 1): return "Tomorrow"
        default: return "\(n) days left"
        }
    }
}
