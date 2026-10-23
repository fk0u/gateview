// Run: swiftc GateView/Models/PrayerTimeModel.swift GateView/Services/PrayerTimeService.swift GateView/Services/WeatherService.swift GateView/Services/SystemStatsService.swift GateView/Services/ReminderService.swift GateView/Services/ThemeStore.swift Tests/main.swift -o /tmp/pcheck && /tmp/pcheck
import Foundation
import SwiftUI

let day = PrayerDay(date: "", timings: ["Fajr": "04:34", "Dhuhr": "11:56 (WITA)", "Asr": "15:13", "Maghrib": "18:00", "Isha": "19:10"])
let cal = Calendar.current
let friday = cal.date(from: DateComponents(year: 2026, month: 10, day: 23))!
let thursday = cal.date(byAdding: .day, value: -1, to: friday)!
func at(_ h: Int, _ m: Int, _ d: Date) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: d)! }

let fri = PrayerTimeService.prayers(from: day, on: friday)
assert(fri[1].name == "Jumat" && fri[1].iqamah == nil)
assert(PrayerTimeService.prayers(from: day, on: thursday)[1].name == "Dzuhur")

guard case .upcoming(let p1) = PrayerTimeService.phase(at: at(11, 0, friday), in: fri), p1.isJumat else { fatalError("before jumat") }
guard case .ongoing(let p2) = PrayerTimeService.phase(at: at(12, 30, friday), in: fri), p2.isJumat else { fatalError("jumat ongoing") }
guard case .iqamah(let p3) = PrayerTimeService.phase(at: at(15, 18, friday), in: fri), p3.name == "Ashar" else { fatalError("ashar iqamah") }
guard case .ongoing = PrayerTimeService.phase(at: at(15, 25, friday), in: fri) else { fatalError("ashar ongoing") }
guard case .upcoming(let p4) = PrayerTimeService.phase(at: at(15, 40, friday), in: fri), p4.name == "Maghrib" else { fatalError("next maghrib") }
guard case .upcoming(let p5) = PrayerTimeService.phase(at: at(22, 0, friday), in: fri), p5.name == "Subuh", p5.time > at(22, 0, friday) else { fatalError("tomorrow subuh") }
assert(PrayerTimeService.countdown(to: at(15, 23, friday), from: at(15, 18, friday)) == "05:00")
// Weather codes
assert(WeatherService.describe(code: 0, isDay: false).0 == "moon.stars.fill")
assert(WeatherService.describe(code: 63, isDay: true).1 == "Hujan")
assert(WeatherService.describe(code: 96, isDay: true).1 == "Badai Petir")

// CPU % from tick delta
assert(SystemStatsSampler.cpuPercent(from: (100, 1000), to: (150, 1100)) == 50)
assert(SystemStatsSampler.cpuPercent(from: (100, 1000), to: (100, 1000)) == 0)

// Reminders: only future prayers, Jumat included
let rem = ReminderService.upcoming(fri, after: at(11, 0, friday))
assert(rem.map(\.name) == ["Jumat", "Ashar", "Maghrib", "Isya"])
assert(SystemStatsSampler().sample().ram > 0)
// Theme: partial file keeps defaults, bad JSON throws, custom iqamah applies
let partial = try! Theme.decode(Data(##"{"accent": "#00FF88", "panelSide": "left"}"##.utf8))
assert(partial.accent == "#00FF88" && partial.panelSide == "left" && partial.city == "Samarinda" && partial.clockSize == 168)
assert((try? Theme.decode(Data("{oops".utf8))) == nil)
assert(Color(hex: "#00FF88") != nil && Color(hex: "nope") == nil)
let custom = PrayerTimeService.prayers(from: day, on: thursday, iqamah: ["Maghrib": 3])
assert(custom[3].iqamah == custom[3].time.addingTimeInterval(180))
print("ok", PrayerTimeService.hijri(friday))
