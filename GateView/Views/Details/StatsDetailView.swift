import SwiftUI

struct StatsDetailView: View {
    @ObservedObject var monitor: SystemStatsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailHeader(title: "Sistem · 5 menit terakhir", symbol: "cpu")
            chart("CPU", value: monitor.stats.cpu, series: monitor.history.map(\.cpu), color: .tint)
            chart("RAM", value: monitor.stats.ram, series: monitor.history.map(\.ram), color: .cyan)
            if let battery = monitor.stats.battery {
                HStack {
                    Label("Baterai \(battery)%", systemImage: monitor.stats.charging ? "battery.100.bolt" : "battery.75")
                    Spacer()
                    Text(monitor.stats.charging ? "Mengisi daya"
                         : monitor.stats.minutesLeft.map { "± \($0 / 60) j \($0 % 60) m tersisa" } ?? "Menghitung…")
                        .opacity(0.6)
                }
                .font(.callout)
            }
        }
    }

    private func chart(_ name: String, value: Int, series: [Int], color: some ShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.caption.weight(.semibold)).opacity(0.6)
                Spacer()
                Text("\(value)%").font(.callout.monospacedDigit())
            }
            Sparkline(values: series)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .background(Sparkline(values: series, closed: true).fill(.white.opacity(0.06)))
                .frame(height: 44)
        }
    }
}

private struct Sparkline: Shape {
    let values: [Int]
    var closed = false

    func path(in rect: CGRect) -> Path {
        Path { p in
            guard values.count > 1 else { return }
            let step = rect.width / CGFloat(59) // fixed 5-minute window, fills from the right
            let start = rect.maxX - step * CGFloat(values.count - 1)
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: start + step * CGFloat(i), y: rect.maxY - rect.height * CGFloat(min(v, 100)) / 100)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            if closed {
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                p.addLine(to: CGPoint(x: start, y: rect.maxY))
                p.closeSubpath()
            }
        }
    }
}
