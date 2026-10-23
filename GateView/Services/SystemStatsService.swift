import Darwin
import Foundation
import IOKit.ps

struct SystemStats: Equatable {
    var cpu = 0
    var ram = 0
    var battery: Int?   // nil on Macs without a battery
    var charging = false
    var minutesLeft: Int?   // battery estimate, nil when charging/unknown
}

/// Samples every 5 s while running and keeps 5 minutes of history for the detail sparkline.
@MainActor
final class SystemStatsMonitor: ObservableObject {
    @Published private(set) var stats = SystemStats()
    @Published private(set) var history: [SystemStats] = []
    private let sampler = SystemStatsSampler()
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let s = self.sampler.sample()
                self.stats = s
                self.history = Array((self.history + [s]).suffix(60))
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// Cheap Mach/IOKit reads; call every few seconds, not every frame.
final class SystemStatsSampler {
    private var previousTicks: (used: UInt64, total: UInt64)?

    func sample() -> SystemStats {
        var stats = SystemStats()
        if let ticks = Self.cpuTicks() {
            if let prev = previousTicks { stats.cpu = Self.cpuPercent(from: prev, to: ticks) }
            previousTicks = ticks
        }
        stats.ram = Self.ramPercent()
        (stats.battery, stats.charging) = Self.battery()
        let estimate = IOPSGetTimeRemainingEstimate()
        stats.minutesLeft = estimate > 0 ? Int(estimate / 60) : nil
        return stats
    }

    static func cpuPercent(from a: (used: UInt64, total: UInt64), to b: (used: UInt64, total: UInt64)) -> Int {
        let total = b.total &- a.total
        guard total > 0 else { return 0 }
        return Int((Double(b.used &- a.used) / Double(total) * 100).rounded())
    }

    private static func cpuTicks() -> (used: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks // user, system, idle, nice
        let used = UInt64(t.0) + UInt64(t.1) + UInt64(t.3)
        return (used, used + UInt64(t.2))
    }

    private static func ramPercent() -> Int {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // Same notion as Activity Monitor's "Memory Used" (app + wired + compressed).
        let pages = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
        let used = pages * UInt64(vm_kernel_page_size)
        return Int(Double(used) / Double(ProcessInfo.processInfo.physicalMemory) * 100)
    }

    private static func battery() -> (Int?, Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false) }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            return (d[kIOPSCurrentCapacityKey] as? Int, d[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return (nil, false)
    }
}
