import AppKit
import EventKit

struct Agenda: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let color: CGColor
}

@MainActor
final class CalendarService {
    let store = EKEventStore()

    func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        }
        return (try? await store.requestAccess(to: .event)) ?? false
    }

    /// Events from now until the end of today (+ `extraDays`), in-progress ones included.
    func upcomingEvents(limit: Int = 3, extraDays: Int = 0) -> [Agenda] {
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 1 + extraDays, to: Calendar.current.startOfDay(for: now)) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map {
                Agenda(id: $0.calendarItemIdentifier,
                       title: $0.title ?? "Untitled",
                       start: $0.startDate,
                       end: $0.endDate,
                       isAllDay: $0.isAllDay,
                       location: $0.location,
                       color: $0.calendar.cgColor)
            }
    }

    /// ponytail: just opens Calendar; jumping to the exact event needs AppleScript + Automation permission.
    static func openCalendar() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"), configuration: .init())
    }
}
