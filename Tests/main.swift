// Run: swiftc GateView/Models/*.swift GateView/Services/{PrayerTimeService,WeatherService,SystemStatsService,ReminderService,ThemeStore,MoodEngine,WallpaperColorService,NowPlayingService,AppleScriptNowPlaying,RemindersService,GalleryService,L10n}.swift Tests/main.swift -o /tmp/gv-check && /tmp/gv-check
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

// Countdown: date parsing, whole-day difference, upcoming sort, theme decode
assert(Countdown.days(until: at(0, 0, friday), from: at(23, 0, thursday)) == 1)
assert(Countdown.days(until: at(23, 0, friday), from: at(8, 0, friday)) == 0)
let c1 = Countdown(title: "Lebaran", date: "2027-03-10"), c2 = Countdown(title: "Trip", date: "2026-10-25"), bad = Countdown(title: "x", date: "oops")
assert(c1.target != nil && bad.target == nil)
assert(CountdownService.upcoming([c1, c2, bad], from: friday).map(\.title) == ["Trip", "Lebaran"])
assert(CountdownService.upcoming([Countdown(title: "old", date: "2020-01-01")], from: friday).isEmpty)
let cdTheme = try! Theme.decode(Data(##"{"countdowns":[{"title":"Lebaran","date":"2027-03-10","symbol":"moon.stars"}]}"##.utf8))
assert(cdTheme.countdowns.count == 1 && cdTheme.countdowns[0].symbol == "moon.stars")
// New 2.3 defaults
assert(cdTheme.autoHideFullscreen && cdTheme.language == "auto" && cdTheme.displayLanguage != "" && cdTheme.adhanVolume == 0.9)
// uid churn doesn't affect equality (ThemeStore would otherwise rewrite theme.json forever)
assert(Countdown(title: "a", date: "2027-03-10") == Countdown(title: "a", date: "2027-03-10"))

// Air quality parsing + banding
let aqData = Data(##"{"current":{"us_aqi":78,"pm2_5":25.4}}"##.utf8)
let aq = try! WeatherService.parseAirQuality(aqData)
assert(aq.aqi == 78 && aq.pm25 == 25.4)
assert(WeatherService.airQualityBand(42).1 == "Baik" && WeatherService.airQualityBand(190).1 == "Tidak Sehat")

// Localization: greetings and weather labels in both languages
assert(L10n.greeting(for: at(9, 0, friday), name: "", lang: "id") == "Selamat Pagi")
assert(L10n.greeting(for: at(13, 0, friday), name: "Ghani", lang: "id") == "Selamat Siang, Ghani")
assert(L10n.greeting(for: at(20, 0, friday), name: "", lang: "en") == "Good Evening")
assert(L10n.daysLeft(0, lang: "id") == "Hari ini!" && L10n.daysLeft(3, lang: "en") == "3 days left")
assert(WeatherService.describe(code: 63, isDay: true, lang: "en").1 == "Rain")
assert(WeatherService.describe(code: 0, isDay: false).1 == "Cerah") // default stays Indonesian
var langTheme = Theme()
assert(langTheme.displayLanguage == langTheme.displayLanguage) // auto resolves deterministically
langTheme.language = "id"; assert(langTheme.displayLanguage == "id")

// Adhan: per-prayer file wins over the global one; missing files are ignored
var adhanTheme = Theme()
let adzanDir = FileManager.default.temporaryDirectory.appendingPathComponent("gv-adzan-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: adzanDir, withIntermediateDirectories: true)
FileManager.default.createFile(atPath: adzanDir.appendingPathComponent("azan.mp3").path, contents: Data())
FileManager.default.createFile(atPath: adzanDir.appendingPathComponent("subuh.mp3").path, contents: Data())
adhanTheme.adhanPath = adzanDir.appendingPathComponent("azan.mp3").path
adhanTheme.adhanPaths = ["Fajr": adzanDir.appendingPathComponent("subuh.mp3").path, "Asr": adzanDir.appendingPathComponent("missing.mp3").path]
assert(ReminderService.adhanPath(for: "Maghrib", in: adhanTheme)?.hasSuffix("/azan.mp3") == true)
assert(ReminderService.adhanPath(for: "Fajr", in: adhanTheme)?.hasSuffix("/subuh.mp3") == true)
assert(ReminderService.adhanPath(for: "Asr", in: adhanTheme) == nil) // file missing → chime fallback
assert(ReminderService.adhanPath(for: "") == nil) // empty path → chime fallback
assert(Set(ReminderService.adhanPaths(in: adhanTheme).keys) == ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"])
try? FileManager.default.removeItem(at: adzanDir)

// AppleScript Now Playing: field parsing (Spotify ms → s), playing wins over paused
let line = ["Spotify", "true", "Song A", "Artist", "Album", "210000", "35.5", "https://x/y.jpg"].joined(separator: "\u{1F}")
assert(AppleScriptNowPlaying.parseLine(line)!.duration == 210)
let paused = ["Music", "false", "Song B", "", "", "95", "12", ""].joined(separator: "\u{1F}")
let both = AppleScriptNowPlaying.pick(line + "\n" + paused)!
assert(both.app == "Spotify" && both.playing && both.artworkURL == "https://x/y.jpg")
assert(AppleScriptNowPlaying.pick(paused)!.duration == 95) // Music already reports seconds
assert(AppleScriptNowPlaying.pick("garbage") == nil)
assert(AppleScriptNowPlaying.parseLine(["Spotify", "true", "", "", "", "0", "0", ""].joined(separator: "\u{1F}")) == nil)

// Reminders widget selection: open ones first by due date, capped
let rItems = [
    RemindersService.Item(id: "1", title: "undated", due: nil, completed: false),
    RemindersService.Item(id: "2", title: "later", due: at(20, 0, friday), completed: false),
    RemindersService.Item(id: "3", title: "sooner", due: at(10, 0, friday), completed: false),
    RemindersService.Item(id: "4", title: "done", due: at(9, 0, friday), completed: true),
]
assert(RemindersService.select(rItems).map(\.title) == ["sooner", "later", "undated"])
assert(RemindersService.select(rItems, limit: 2).count == 2)

print("ok", PrayerTimeService.hijri(friday))
