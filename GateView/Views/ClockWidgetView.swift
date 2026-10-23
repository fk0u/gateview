import SwiftUI

struct ClockWidgetView<Accessory: View>: View {
    let theme: Theme
    @ViewBuilder var accessory: Accessory // e.g. weather, shown next to the greeting

}

// Formatters live outside the generic type (no static stored properties in generics).
private enum ClockFormat {
    static let hm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    static let ss: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "ss"; return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "EEEE, d MMMM"
        return f
    }()
}

extension ClockWidgetView {
    var body: some View {
        // TimelineView redraws only this subtree once per second.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    Text(Self.greeting(for: context.date, name: theme.greetingName))
                        .font(.system(size: 26, weight: .medium))
                        .opacity(0.85)
                    accessory
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ClockFormat.hm.string(from: context.date))
                        .font(.system(size: theme.clockSize, weight: theme.clockFontWeight).monospacedDigit())
                        .tracking(-4)
                    if theme.showSeconds {
                        Text(ClockFormat.ss.string(from: context.date))
                            .font(.system(size: theme.clockSize * 0.2, weight: .regular).monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                }
                Text(ClockFormat.day.string(from: context.date))
                    .font(.system(size: 26, weight: .regular))
                    .opacity(0.85)
            }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
        }
    }

    static func greeting(for date: Date, name: String) -> String {
        let suffix = name.isEmpty ? "" : ", \(name)"
        switch Calendar.current.component(.hour, from: date) {
        case 4..<12: return "Good Morning" + suffix
        case 12..<18: return "Good Afternoon" + suffix
        default: return "Good Evening" + suffix
        }
    }
}
