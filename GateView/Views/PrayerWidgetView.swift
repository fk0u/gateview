import SwiftUI

struct PrayerWidgetView: View {
    let prayers: [Prayer]
    let error: String?
    let city: String
    @Environment(\.gateMotion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if prayers.isEmpty {
                header(Date())
                Text(error ?? "Loading prayer times…").opacity(0.7)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        header(context.date)
                        if let phase = PrayerTimeService.phase(at: context.date, in: prayers) {
                            hero(phase, now: context.date)
                                .id(caption(of: phase)) // new phase → cross-fade
                                .transition(.opacity)
                            row(highlight: phase, now: context.date)
                        }
                    }
                    .motion(.easeInOut(duration: 0.6), value: PrayerTimeService.phase(at: context.date, in: prayers).map(caption), enabled: motion)
                }
            }
        }
    }

    private func header(_ date: Date) -> some View {
        HStack {
            Label(city, systemImage: "moon.stars.fill")
            Spacer()
            Text(PrayerTimeService.hijri(date))
        }
        .font(.caption.weight(.semibold))
        .opacity(0.7)
    }

    @ViewBuilder
    private func hero(_ phase: PrayerPhase, now: Date) -> some View {
        let (prayer, caption, target): (Prayer, String, Date?) = switch phase {
        case .upcoming(let p): (p, p.isJumat ? "Menuju Sholat Jumat" : "Menuju adzan", p.time)
        case .iqamah(let p): (p, "Iqomah dalam", p.iqamah)
        case .ongoing(let p): (p, p.isJumat ? "Khutbah & Sholat Jumat" : "Sholat berjamaah", nil)
        }
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption).font(.caption).opacity(0.6)
                Text(prayer.name).font(.system(size: 28, weight: .semibold))
            }
            Spacer()
            if let target {
                let text = PrayerTimeService.countdown(to: target, from: now)
                let finalMinute = target.timeIntervalSince(now) < 60
                Text(text)
                    .font(.system(size: 40, weight: .light).monospacedDigit())
                    .foregroundStyle(phase == .iqamah(prayer) ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tint))
                    .rollingDigits(text, enabled: motion)
                    // soft breathing pulse in the last minute
                    .opacity(finalMinute && motion && Int(now.timeIntervalSince1970) % 2 == 0 ? 0.55 : 1)
                    .motion(.easeInOut(duration: 0.9), value: Int(now.timeIntervalSince1970), enabled: finalMinute)
            } else {
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
            }
        }
    }

    private func caption(of phase: PrayerPhase) -> String {
        switch phase {
        case .upcoming(let p): return "u" + p.name
        case .iqamah(let p): return "i" + p.name
        case .ongoing(let p): return "o" + p.name
        }
    }

    private func row(highlight phase: PrayerPhase, now: Date) -> some View {
        let active: String = switch phase {
        case .upcoming(let p), .iqamah(let p), .ongoing(let p): p.name
        }
        return HStack(spacing: 0) {
            ForEach(prayers) { prayer in
                let isActive = prayer.name == active
                VStack(spacing: 4) {
                    Text(prayer.name).font(.caption2.weight(.medium))
                    Text(prayer.time, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.callout.monospacedDigit())
                    Text(prayer.iqamah.map { "iq " + $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) } ?? "khutbah")
                        .font(.system(size: 9).monospacedDigit())
                        .opacity(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                .opacity(isActive || prayer.end > now ? 1 : 0.55)
                .background(isActive ? Color.white.opacity(0.08) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
