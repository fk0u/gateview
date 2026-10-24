import AppKit
import EventKit

/// Apple Reminders for the panel widget: checklist that toggles right on the desktop.
@MainActor
final class RemindersService: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        var completed: Bool
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var authorized = false

    let store = EKEventStore()
    private var cache: [String: EKReminder] = [:]

    func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            authorized = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            authorized = (try? await store.requestAccess(to: .reminder)) ?? false
        }
        return authorized
    }

    func load() {
        guard authorized else { return }
        store.fetchReminders(matching: store.predicateForReminders(in: nil)) { [weak self] reminders in
            Task { @MainActor in
                guard let self else { return }
                let list = reminders ?? []
                self.cache = Dictionary(list.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { _, new in new })
                self.items = Self.select(list.map {
                    Item(id: $0.calendarItemIdentifier, title: $0.title ?? "", due: $0.dueDateComponents?.date, completed: $0.isCompleted)
                })
            }
        }
    }

    /// Open reminders first (by due date, undated last), capped for the widget.
    nonisolated static func select(_ items: [Item], limit: Int = 8) -> [Item] {
        let open = items.filter { !$0.completed }.sorted {
            switch ($0.due, $1.due) {
            case let (a?, b?): return a < b
            case (_, nil) where $0.due != nil: return true
            case (nil, _) where $1.due != nil: return false
            default: return $0.title < $1.title
            }
        }
        return Array(open.prefix(limit))
    }

    func toggle(_ item: Item) {
        guard let reminder = cache[item.id] else { return }
        reminder.isCompleted = !item.completed
        try? store.save(reminder, commit: true)
        load()
    }

    func add(title: String) {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        try? store.save(reminder, commit: true)
        load()
    }
}
