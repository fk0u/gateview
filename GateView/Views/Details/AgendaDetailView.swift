import SwiftUI

struct AgendaDetailView: View {
    let events: [Agenda]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailHeader(title: "Agenda", symbol: "calendar")
            if events.isEmpty {
                Text("Tidak ada agenda hari ini dan besok").opacity(0.6)
            }
            let groups = Dictionary(grouping: events) { Calendar.current.isDateInToday($0.start) || $0.start < .now }
            ForEach([true, false], id: \.self) { today in
                if let list = groups[today] {
                    Text(today ? "Hari ini" : "Besok").font(.caption.weight(.semibold)).opacity(0.6)
                    ForEach(list) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Capsule().fill(Color(cgColor: event.color)).frame(width: 4, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).fontWeight(.medium).lineLimit(1)
                                Text(event.isAllDay ? "Sepanjang hari"
                                     : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption.monospacedDigit()).opacity(0.6)
                                if let location = event.location, !location.isEmpty {
                                    Label(location, systemImage: "mappin").font(.caption2).opacity(0.5).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            Button {
                CalendarService.openCalendar()
            } label: {
                Label("Buka Calendar", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .font(.callout.weight(.medium))
        }
    }
}
