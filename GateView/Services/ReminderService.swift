import AppKit
import AVFoundation
import UserNotifications

/// Banner at each adzan (scheduled with the OS, no polling) + optional chime or a real adhan audio file.
/// Settings live in the theme.
@MainActor
final class ReminderService {
    static let modes = [("off", "Off"), ("banner", "Banner"), ("chime", "Banner + Chime")]
    static let sounds = ["Glass", "Tink", "Purr", "Pop", "Submarine", "Hero"]

    private var chimeTask: Task<Void, Never>?
    private static var adhanPlayer: AVAudioPlayer?

    func schedule(_ prayers: [Prayer], theme: Theme, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        chimeTask?.cancel()
        guard theme.reminderMode != "off",
              (try? await center.requestAuthorization(options: [.alert])) == true || theme.reminderMode == "chime"
        else { return }

        let upcoming = Self.upcoming(prayers, after: now, enabled: theme.reminders)
        for prayer in upcoming {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: prayer.time)
            let request = UNNotificationRequest(
                identifier: "prayer.\(prayer.key)",
                content: Self.content(for: prayer),
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            try? await center.add(request)
        }

        guard theme.reminderMode == "chime" else { return }
        let sound = theme.reminderSound
        let volume = theme.adhanVolume
        chimeTask = Task {
            for prayer in upcoming {
                let wait = prayer.time.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard !Task.isCancelled else { return }
                if Date().timeIntervalSince(prayer.time) < 60 { // skip if the Mac slept through it
                    if let path = Self.adhanPath(for: prayer.key, in: theme) {
                        Self.playAdhan(path, volume: volume)
                    } else {
                        Self.play(sound)
                    }
                }
            }
        }
    }

    func test(theme: Theme) {
        let request = UNNotificationRequest(identifier: "prayer.test", content: Self.content(for: nil), trigger: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in
            UNUserNotificationCenter.current().add(request)
        }
        if theme.reminderMode == "chime" {
            if let path = Self.adhanPaths(in: theme).values.first.flatMap({ Self.adhanPath(for: $0) }) {
                Self.playAdhan(path, volume: theme.adhanVolume)
            } else {
                Self.play(theme.reminderSound)
            }
        }
    }

    nonisolated static func upcoming(_ prayers: [Prayer], after now: Date, enabled: [String: Bool] = [:]) -> [Prayer] {
        prayers.filter { $0.time > now && enabled[$0.key] != false }
    }

    static func play(_ sound: String) {
        NSSound(named: sound)?.play()
    }

    // MARK: Adhan audio

    /// Per-prayer file if set, else the global one; `~` expanded. nil → fall back to the chime.
    nonisolated static func adhanPath(for key: String, in theme: Theme) -> String? {
        adhanPath(for: theme.adhanPaths[key] ?? theme.adhanPath)
    }

    nonisolated static func adhanPath(for raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded) ? expanded : nil
    }

    nonisolated static func adhanPaths(in theme: Theme) -> [String: String] {
        var all = theme.adhanPaths
        if !theme.adhanPath.isEmpty { for key in ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"] where all[key] == nil { all[key] = theme.adhanPath } }
        return all
    }

    static func playAdhan(_ path: String, volume: Double) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        adhanPlayer = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) // kept alive until it finishes
        adhanPlayer?.volume = Float(min(max(volume, 0), 1))
        adhanPlayer?.play()
    }

    private static func content(for prayer: Prayer?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch prayer {
        case let p? where p.isJumat:
            content.title = "Waktu Sholat Jumat"
            content.body = "Saatnya bersiap ke masjid"
        case let p?:
            content.title = "Waktu \(p.name)"
            content.body = "Adzan \(p.name) · iqomah \(p.iqamah?.formatted(date: .omitted, time: .shortened) ?? "")"
        case nil:
            content.title = "GateView"
            content.body = "Tes pengingat sholat"
        }
        content.sound = nil // silent banner; the chime is our own softer sound
        return content
    }
}
