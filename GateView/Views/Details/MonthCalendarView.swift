import SwiftUI

/// A month grid with Hijri day numbers. Used by the clock detail and the Calendar widget.
struct MonthCalendarView: View {
    var month = Date()
    var compact = false
    var selected: Date?
    var onSelect: ((Date) -> Void)?
    var header = true

    private let cal = Calendar.current
    private let hijri = Calendar(identifier: .islamicUmmAlQura)

    private var weekdaySymbols: [String] {
        let s = cal.veryShortWeekdaySymbols
        return Array(s[(cal.firstWeekday - 1)...] + s[..<(cal.firstWeekday - 1)])
    }

    var body: some View {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let days = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7

        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if header {
                DetailHeader(title: month.formatted(.dateTime.month(.wide).year()) + " · " + PrayerTimeService.hijri(month), symbol: "calendar")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 2 : 4), count: 7), spacing: compact ? 2 : 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption2.weight(.semibold)).opacity(0.5)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(1...days, id: \.self) { day in
                    cell(cal.date(byAdding: .day, value: day - 1, to: start)!, day: day)
                }
            }
        }
    }

    private func cell(_ date: Date, day: Int) -> some View {
        let isToday = cal.isDateInToday(date)
        let isSelected = selected.map { cal.isDate($0, inSameDayAs: date) } ?? false
        let friday = cal.component(.weekday, from: date) == 6
        return VStack(spacing: 0) {
            Text("\(day)").font((compact ? Font.caption : .callout).monospacedDigit().weight(isToday ? .bold : .regular))
            if !compact {
                Text("\(hijri.component(.day, from: date))").font(.system(size: 8).monospacedDigit()).opacity(0.5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 20 : 30)
        .foregroundStyle(isToday ? AnyShapeStyle(.black) : friday ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
        .background(isToday ? AnyShapeStyle(.tint) : isSelected ? AnyShapeStyle(.white.opacity(0.15)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: compact ? 5 : 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onSelect?(date) }
    }
}
