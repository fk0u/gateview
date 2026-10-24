import SwiftUI

/// Days-until widget fed from theme.json (`"countdowns": [...]`). Compact: the next one, big.
/// Expanded: every upcoming countdown.
struct CountdownWidget: View {
    let expanded: Bool
    let theme: Theme

    var body: some View {
        let lang = theme.displayLanguage
        let items = CountdownService.upcoming(theme.countdowns)
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.tr(lang, "Hitung Mundur", "Countdown"), systemImage: "timer")
                .font(.caption.weight(.semibold))
                .opacity(0.7)
            if items.isEmpty {
                Text(L10n.tr(lang, "Tambah di theme.json → \"countdowns\"", "Add one in theme.json → \"countdowns\""))
                    .font(.caption).opacity(0.45)
            } else if expanded {
                ForEach(items) { row($0, lang: lang) }
            } else if let next = items.first, let target = next.target {
                let days = Countdown.days(until: target)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(days)")
                        .font(.system(size: 46, weight: .light).monospacedDigit())
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(.headline)
                        Text(L10n.daysLeft(days, lang: lang)).font(.caption).opacity(0.6)
                    }
                }
            }
        }
    }

    private func row(_ item: Countdown, lang: String) -> some View {
        let days = item.target.map { Countdown.days(until: $0) } ?? 0
        return HStack(spacing: 10) {
            Image(systemName: item.symbol).foregroundStyle(.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.callout)
                Text(Self.dateText(item, lang: lang)).font(.caption2.monospacedDigit()).opacity(0.5)
            }
            Spacer()
            Text(L10n.daysLeft(days, lang: lang))
                .font(.caption.weight(.medium))
                .foregroundStyle(days <= 3 ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.65)))
        }
    }

    static func dateText(_ item: Countdown, lang: String) -> String {
        guard let target = item.target else { return item.date }
        let f = DateFormatter()
        f.locale = Locale(identifier: lang == "id" ? "id_ID" : "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: target)
    }
}
