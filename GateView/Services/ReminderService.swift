import AppKit
import UserNotifications

enum ReminderMode: String, CaseIterable {
    case off, banner, chime
    static let storageKey = "GateView.reminderMode"

    var title: String {
        switch self {
        case .off: return "Off"
        case .banner: return "Banner"
        case .chime: return "Banner + Chime"
        }
    }

    static var current: ReminderMode {
        ReminderMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .off
    }
}

/// Banner at each adzan (scheduled with the OS, no polling) + optional soft chime.
@MainActor
final class ReminderService {
    private var chimeTask: Task<Void, Never>?

    func schedule(_ prayers: [Prayer], mode: ReminderMode = .current, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        chimeTask?.cancel()
        guard mode != .off,
              (try? await center.requestAuthorization(options: [.alert])) == true || mode == .chime
        else { return }

        let upcoming = Self.upcoming(prayers, after: now)
        for prayer in upcoming {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: prayer.time)
            let request = UNNotificationRequest(
                identifier: "prayer.\(prayer.name)",
                content: Self.content(for: prayer),
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            try? await center.add(request)
        }

        guard mode == .chime else { return }
        chimeTask = Task {
            for prayer in upcoming {
                let wait = prayer.time.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard !Task.isCancelled else { return }
                if Date().timeIntervalSince(prayer.time) < 60 { Self.chime() } // skip if the Mac slept through it
            }
        }
    }

    func test() {
        let request = UNNotificationRequest(identifier: "prayer.test", content: Self.content(for: nil), trigger: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in
            UNUserNotificationCenter.current().add(request)
        }
        if ReminderMode.current == .chime { Self.chime() }
    }

    nonisolated static func upcoming(_ prayers: [Prayer], after now: Date) -> [Prayer] {
        prayers.filter { $0.time > now }
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

    private static func chime() {
        NSSound(named: "Glass")?.play()
    }
}
