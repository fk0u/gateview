// Golden dataset generator (macOS source of truth).
// Run: swiftc GateView/Models/*.swift GateView/Services/{PrayerTimeService,ThemeStore}.swift Tests/golden.swift -o /tmp/gv-golden && /tmp/gv-golden Tests/fixtures/aladhan-timings.json
// Its printed values are asserted verbatim by crates/gateview-core/tests/golden.rs.
import Foundation

@main
enum GoldenScript {
    static func main() {
        let args = CommandLine.arguments
        let fixture = try! String(contentsOfFile: args.count > 1 ? args[1] : "Tests/fixtures/aladhan-timings.json", encoding: .utf8)

        let cal = Calendar.current
        let friday = cal.date(from: DateComponents(year: 2026, month: 10, day: 23))!
        let thursday = cal.date(byAdding: .day, value: -1, to: friday)!
        let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

        let timings = try! JSONDecoder().decode(AladhanResponse.self, from: Data(fixture.utf8)).data.timings
        let day = PrayerDay(date: "23-10-2026", timings: timings)

        print("== prayers friday default iqamah ==")
        for p in PrayerTimeService.prayers(from: day, on: friday) {
            print("\(p.key) \(fmt.string(from: p.time)) iqamah=\(p.iqamah.map { fmt.string(from: $0) } ?? "-") jumat=\(p.isJumat)")
        }
        print("== prayers thursday maghrib=3 ==")
        for p in PrayerTimeService.prayers(from: day, on: thursday, iqamah: ["Maghrib": 3]) {
            print("\(p.key) \(fmt.string(from: p.time)) iqamah=\(p.iqamah.map { fmt.string(from: $0) } ?? "-")")
        }
        print("== countdown ==")
        func at(_ h: Int, _ m: Int, _ d: Date) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: d)! }
        print(PrayerTimeService.countdown(to: at(15, 23, friday), from: at(15, 18, friday)))
        print(PrayerTimeService.countdown(to: at(16, 23, friday), from: at(15, 18, friday)))
        print("== hijri ==")
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .islamicUmmAlQura)
        df.locale = Locale(identifier: "id_ID")
        df.dateFormat = "d MMMM yyyy 'H'"
        for (y, m, d) in [(2026, 10, 23), (2026, 3, 20), (2025, 2, 28), (2027, 1, 1), (2026, 6, 17)] {
            print("\(y)-\(m)-\(d) \(df.string(from: cal.date(from: DateComponents(year: y, month: m, day: d))!))")
        }
        print("== hijri month names ==")
        let hc = Calendar(identifier: .islamicUmmAlQura)
        var seen = Set<Int>()
        var scan = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        for _ in 0..<800 {
            let m = hc.component(.month, from: scan)
            if !seen.contains(m) {
                seen.insert(m)
                let name = df.string(from: scan).split(separator: " ")[1]
                print("month \(m) = \(name)")
            }
            scan = cal.date(byAdding: .day, value: 1, to: scan)!
        }

        // Dump the Umm al-Qura month-start table (Apple's = the official KACST tables;
        // ICU4X's fallback approximation drifts by a day on some months, so the Rust
        // side consumes this fixture instead of computing).
        print("== hijri month table ==")
        let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f }()
        var rows: [String] = []
        var cursor = cal.date(from: DateComponents(year: 2020, month: 1, day: 1))!
        let tableEnd = cal.date(from: DateComponents(year: 2051, month: 1, day: 1))!
        var prev = (0, 0)
        while cursor < tableEnd {
            let hy = hc.component(.year, from: cursor), hm = hc.component(.month, from: cursor)
            if (hy, hm) != prev {
                rows.append("{\"g\": \"\(dayFmt.string(from: cursor))\", \"h\": \"\(hy)-\(hm)\"}")
                prev = (hy, hm)
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        let json = "[\n  " + rows.joined(separator: ",\n  ") + "\n]"
        let outURL = URL(fileURLWithPath: "Tests/fixtures/umm-alqura-months.json")
        try! json.write(to: outURL, atomically: true, encoding: .utf8)
        print("wrote \(rows.count) month starts to \(outURL.path)")
    }
}
