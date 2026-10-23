import SwiftUI

struct PrayerDetailView: View {
    let prayers: [Prayer]
    let timings: [String: String]
    let week: [PrayerDay]
    @ObservedObject var store: ThemeStore

    private static let hm = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailHeader(title: "Jadwal Lengkap · \(store.theme.city)", symbol: "moon.stars.fill")

            VStack(spacing: 6) {
                extra("Imsak", timings["Imsak"])
                ForEach(prayers) { prayer in
                    if prayer.key == "Dhuhr" {
                        extra("Terbit", timings["Sunrise"])
                        // ponytail: Dhuha ≈ sunrise + 20 min (common Indonesian convention), not from the API.
                        extra("Dhuha", PrayerTimeService.time(timings["Sunrise"], on: .now).map { $0.addingTimeInterval(20 * 60).formatted(Self.hm) })
                    }
                    row(prayer)
                }
            }

            if !week.isEmpty {
                Divider().overlay(.white.opacity(0.15))
                Text("7 hari ke depan").font(.caption.weight(.semibold)).opacity(0.6)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("")
                        ForEach(["Subuh", "Dzuhur", "Ashar", "Maghrib", "Isya"], id: \.self) { Text($0) }
                    }
                    .font(.system(size: 9, weight: .semibold)).opacity(0.5)
                    ForEach(week, id: \.date) { day in
                        GridRow {
                            Text(PrayerTimeService.date(fromKey: day.date)?.formatted(.dateTime.weekday(.abbreviated).day()) ?? day.date)
                                .opacity(0.7)
                            ForEach(PrayerTimeService.schedule, id: \.key) { s in
                                Text(day.timings[s.key].map { String($0.prefix(5)) } ?? "–")
                            }
                        }
                        .font(.system(size: 11).monospacedDigit())
                    }
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    private func row(_ prayer: Prayer) -> some View {
        HStack {
            Text(prayer.name).fontWeight(.medium)
            Spacer()
            Text(prayer.time, format: Self.hm).monospacedDigit()
            Text(prayer.iqamah.map { "iq " + $0.formatted(Self.hm) } ?? "khutbah")
                .font(.caption.monospacedDigit()).opacity(0.55).frame(width: 64, alignment: .trailing)
            Button {
                store.theme.reminders[prayer.key] = !(store.theme.reminders[prayer.key] ?? true)
            } label: {
                Image(systemName: store.theme.reminders[prayer.key] ?? true ? "bell.fill" : "bell.slash")
                    .foregroundStyle(store.theme.reminderMode == "off" ? AnyShapeStyle(.white.opacity(0.3)) : AnyShapeStyle(.tint))
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help(store.theme.reminderMode == "off" ? "Turn on reminders in Settings → Prayer" : "Reminder for \(prayer.name)")
        }
    }

    private func extra(_ name: String, _ raw: String?) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(raw.map { String($0.prefix(5)) } ?? "–").monospacedDigit()
            Color.clear.frame(width: 64 + 22 + 8, height: 1)
        }
        .font(.callout)
        .opacity(0.55)
    }
}
