import SwiftUI

struct StatsBarView: View {
    @ObservedObject var monitor: SystemStatsMonitor

    var body: some View {
        let stats = monitor.stats
        HStack(spacing: 18) {
            Label("CPU \(stats.cpu)%", systemImage: "cpu")
            Label("RAM \(stats.ram)%", systemImage: "memorychip")
            if let battery = stats.battery {
                Label("\(battery)%", systemImage: stats.charging ? "battery.100.bolt" : "battery.75")
            }
        }
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .opacity(0.7)
    }
}
