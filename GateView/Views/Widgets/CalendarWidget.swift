import SwiftUI

/// Compact: this month. Expanded: browse months, pick a day, see its events.
struct CalendarWidget: View {
    let expanded: Bool
    let eventsOn: (Date) -> [Agenda]
    @State private var offset = 0
    @State private var selected = Date()

    var body: some View {
        let month = Calendar.current.date(byAdding: .month, value: offset, to: .now) ?? .now
        if expanded {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
                MonthCalendarView(month: month, selected: selected, onSelect: { selected = $0 }, header: false)
                Divider().overlay(.white.opacity(0.15))
                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · " + PrayerTimeService.hijri(selected))
                    .font(.caption.weight(.semibold)).opacity(0.7)
                let events = eventsOn(selected)
                if events.isEmpty {
                    Text("Tidak ada agenda").font(.callout).opacity(0.5)
                }
                ForEach(events) { event in
                    HStack(spacing: 10) {
                        Capsule().fill(Color(cgColor: event.color)).frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).lineLimit(1)
                            Text(event.isAllDay ? "Sepanjang hari" : event.start.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit()).opacity(0.6)
                        }
                    }
                }
            }
        } else {
            MonthCalendarView(compact: true)
        }
    }
}
