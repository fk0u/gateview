import SwiftUI

struct StatsBarView: View {
    @State private var stats = SystemStats()
    @State private var sampler = SystemStatsSampler()

    var body: some View {
        HStack(spacing: 18) {
            item("cpu", "CPU \(stats.cpu)%")
            item("memorychip", "RAM \(stats.ram)%")
            if let battery = stats.battery {
                item(stats.charging ? "battery.100.bolt" : "battery.75", "\(battery)%")
            }
        }
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .opacity(0.7)
        .task {
            // Only this tiny view updates, every 5 s; cancelled automatically when hidden.
            while !Task.isCancelled {
                stats = sampler.sample()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func item(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).labelStyle(.titleAndIcon)
    }
}
