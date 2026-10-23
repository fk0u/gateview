import EventKit

struct Agenda: Identifiable {
    let id: String
    let title: String
    let start: Date
    let isAllDay: Bool
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

    /// Next `limit` events from now until end of today (includes in-progress ones).
    func upcomingEvents(limit: Int = 3) -> [Agenda] {
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map {
                Agenda(id: $0.eventIdentifier ?? UUID().uuidString,
                       title: $0.title ?? "Untitled",
                       start: $0.startDate,
                       isAllDay: $0.isAllDay,
                       color: $0.calendar.cgColor)
            }
    }
}
