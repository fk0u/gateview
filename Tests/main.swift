// Run: swiftc GateView/Models/*.swift GateView/Services/{PrayerTimeService,WeatherService,SystemStatsService,ReminderService,ThemeStore,MoodEngine,WallpaperColorService,NowPlayingService,GalleryService}.swift Tests/main.swift -o /tmp/gv-check && /tmp/gv-check
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
// Reminders respect per-prayer toggles
assert(ReminderService.upcoming(fri, after: at(11, 0, friday), enabled: ["Asr": false]).map(\.name) == ["Jumat", "Maghrib", "Isya"])

// Mood follows the day
assert(MoodEngine.mood(at: at(3, 0, friday), prayers: fri).name == "night")
assert(MoodEngine.mood(at: at(5, 0, friday), prayers: fri).name == "dawn")
assert(MoodEngine.mood(at: at(10, 0, friday), prayers: fri).name == "day")
let early = MoodEngine.mood(at: at(15, 30, friday), prayers: fri), late = MoodEngine.mood(at: at(17, 45, friday), prayers: fri)
assert(early.name == "golden" && late.tintOpacity > early.tintOpacity) // warmer toward Maghrib
assert(MoodEngine.mood(at: at(18, 30, friday), prayers: fri).name == "dusk")
assert(MoodEngine.mood(at: at(23, 0, friday), prayers: fri).name == "night")

// Wallpaper colour: saturated orange beats a larger grey area
let px = Array(repeating: (0.5, 0.5, 0.5), count: 600) + Array(repeating: (0.95, 0.5, 0.1), count: 200)
let dom = WallpaperColorService.dominant(px)!
assert(dom.h > 0.04 && dom.h < 0.12)
assert(WallpaperColorService.dominant(Array(repeating: (0.5, 0.5, 0.5), count: 10)) == nil)

// Hit regions: nested (smaller) widget wins
let regions = ["clock": CGRect(x: 0, y: 0, width: 500, height: 300), "weather": CGRect(x: 300, y: 0, width: 150, height: 40)]
assert(HitRegionsKey.hit(CGPoint(x: 310, y: 10), in: regions) == "weather")
assert(HitRegionsKey.hit(CGPoint(x: 10, y: 200), in: regions) == "clock")
assert(HitRegionsKey.hit(CGPoint(x: 900, y: 10), in: regions) == nil)

// A 1.2-era theme.json still loads, new keys get defaults
let old = try! Theme.decode(Data(##"{"accent": "#FFC56B", "showWeather": false}"##.utf8))
assert(!old.showWeather && old.interactive && old.weatherEffects == "subtle" && old.widgetOrder.count == 3)

// Weather detail parsing
let sample = Data(##"{"utc_offset_seconds":28800,"current":{"temperature_2m":29.6,"apparent_temperature":33.1,"wind_speed_10m":7.2,"relative_humidity_2m":80,"weather_code":63,"is_day":1},"hourly":{"time":["2026-10-23T15:00","2026-10-23T16:00"],"temperature_2m":[30,29],"weather_code":[3,61],"precipitation_probability":[20,null],"is_day":[1,1]},"daily":{"time":["2026-10-23","2026-10-24"],"weather_code":[63,1],"temperature_2m_max":[31.4,32],"temperature_2m_min":[24.2,24.8],"precipitation_probability_max":[80,null]}}"##.utf8)
let w = try! WeatherService.parse(sample, now: at(14, 0, friday))
assert(w.temperature == 30 && w.feelsLike == 33 && w.label == "Hujan" && w.code == 63)
assert(w.hourly.count == 2 && w.hourly[1].rainChance == 0 && w.daily.count == 1 && w.daily[0].max == 32)
// Now Playing position: advances while playing, frozen when paused, clamped to duration
let t0 = Date(timeIntervalSince1970: 1_000)
let song = NowPlaying(title: "x", artist: "", album: "", artwork: nil, isPlaying: true, duration: 200, elapsed: 50, timestamp: t0, rate: 1)
assert(song.position(at: t0.addingTimeInterval(10)) == 60)
assert(song.position(at: t0.addingTimeInterval(1_000)) == 200)
let pausedSong = NowPlaying(title: "x", artist: "", album: "", artwork: nil, isPlaying: false, duration: 200, elapsed: 50, timestamp: t0, rate: 0)
assert(pausedSong.position(at: t0.addingTimeInterval(10)) == 50)

// Widget catalog: unknown keys and duplicates dropped, prayer removable
var panelTheme = Theme()
panelTheme.widgetOrder = ["notes", "bogus", "prayer", "notes", "gallery"]
assert(panelTheme.panelWidgets == ["notes", "prayer", "gallery"])
panelTheme.widgetOrder.removeAll { $0 == "prayer" }
assert(!panelTheme.panelWidgets.contains("prayer"))
// 2.1 theme with showAgenda=false migrates to "agenda not in panel"
let migrated = try! Theme.decode(Data(##"{"showAgenda": false, "showNowPlaying": true}"##.utf8))
assert(migrated.panelWidgets == ["prayer", "nowPlaying"])

// Gallery picks up images only
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gv-gallery-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for name in ["a.jpg", "b.PNG", "c.txt", ".hidden.jpg"] { FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data()) }
assert(Set(GalleryService.images(in: dir).map(\.lastPathComponent)) == ["a.jpg", "b.PNG"])
try? FileManager.default.removeItem(at: dir)
print("ok", PrayerTimeService.hijri(friday))
