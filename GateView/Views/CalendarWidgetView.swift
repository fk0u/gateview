import SwiftUI

struct CalendarWidgetView: View {
    let events: [Agenda]
    let authorized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agenda Hari Ini", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .opacity(0.7)

            if !authorized || events.isEmpty {
                Text(authorized ? "No upcoming events today" : "Calendar access not granted")
                    .opacity(0.6)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 12) {
                        Capsule().fill(Color(cgColor: event.color)).frame(width: 4, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.body.weight(.medium)).lineLimit(1)
                            Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .opacity(0.6)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
