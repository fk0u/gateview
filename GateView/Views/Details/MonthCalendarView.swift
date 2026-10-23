import SwiftUI

/// Current month with Hijri day numbers.
struct MonthCalendarView: View {
    private let cal = Calendar.current
    private let hijri = Calendar(identifier: .islamicUmmAlQura)

    private var weekdaySymbols: [String] {
        let s = cal.veryShortWeekdaySymbols
        return Array(s[(cal.firstWeekday - 1)...] + s[..<(cal.firstWeekday - 1)])
    }

    var body: some View {
        let today = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let days = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let symbols = weekdaySymbols

        VStack(alignment: .leading, spacing: 12) {
            DetailHeader(title: today.formatted(.dateTime.month(.wide).year()) + " · " + PrayerTimeService.hijri(today), symbol: "calendar")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption2.weight(.semibold)).opacity(0.5)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(1...days, id: \.self) { day in
                    let date = cal.date(byAdding: .day, value: day - 1, to: start)!
                    let isToday = cal.isDateInToday(date)
                    let friday = cal.component(.weekday, from: date) == 6
                    VStack(spacing: 0) {
                        Text("\(day)").font(.callout.monospacedDigit().weight(isToday ? .bold : .regular))
                        Text("\(hijri.component(.day, from: date))").font(.system(size: 8).monospacedDigit()).opacity(0.5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .foregroundStyle(isToday ? AnyShapeStyle(.black) : friday ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                    .background(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}
