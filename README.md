<p align="center"><img src="docs/banner.png" alt="GateView — ambient desktop dashboard for macOS" width="100%"></p>

# GateView

An ultra-light ambient dashboard that lives **on your macOS wallpaper**: below every window, on every Space, with click-through on by default. Inspired by the Apple TV screensaver and the macOS Golden Gate wallpaper. ([Changelog](CHANGELOG.md) · [Windows & Linux roadmap](docs/CROSSPLATFORM.md))

**~16 MB RAM · ~2% CPU · Universal (Apple Silicon + Intel) · macOS 13 Ventura+ · zero dependencies**

## Features

- **Clock**: big monospaced-digit clock, greeting, Indonesian date
- **Prayer times** ([Aladhan](https://aladhan.com/prayer-times-api)): countdown to adzan → iqomah → "sholat berjamaah", Friday Dzuhur becomes **Jumat**, Hijri date, cached once per day
- **Prayer reminder**: silent banner at each adzan, optional soft chime, or a **real adhan audio file** (per-prayer or global)
- **Weather** ([Open-Meteo](https://open-meteo.com), no API key) with **air quality** (US AQI + PM2.5)
- **Now Playing**: Spotify, Music, YouTube in the browser, with artwork
- **Agenda**: next 3 events today from Apple Calendar
- **Reminders**: your open Apple Reminders, checkable right on the desktop, add new ones inline
- **Countdown**: days until any date (declare them in theme.json or in Settings)
- **Modular panel**: pick and order any of Prayer, Agenda, Now Playing, **Calendar**, **Notes**, **Reminders**, **Countdown** and **Gallery** *(experimental)*, or drop Prayer entirely
- **Notes**: type right on the desktop; saved to `~/.config/gateview/notes.md`
- **System stats**: CPU, RAM, battery
- **Real glass**: behind-window blur of your wallpaper, not a flat card (solid scrim when Accessibility → Reduce Transparency is on)
- **Interactive**: hover a widget, click it to open details (full prayer schedule and 7 days, hourly and 5-day weather with air quality, agenda for tomorrow, music controls with a seekable progress bar, CPU/RAM sparkline, month calendar with Hijri dates). Everywhere else stays click-through.
- **Alive**: rolling digits, a mood tint that follows the day (cool Subuh, golden before Maghrib, calm night), an accent that can follow your wallpaper, and live rain, storm and fog drawn by Core Animation on the GPU
- **Considerate**: fades out while a fullscreen app is in front, Indonesian/English UI (auto-detected or forced in Settings), optional update check against GitHub Releases
- **Settings app**: sidebar, presets, city search, per-prayer reminders and sounds, live preview, plus a live-reloading `~/.config/gateview/theme.json`

## Install

Download from [Releases](../../releases/latest):

- **`.dmg`**: open it and drag GateView into Applications
- **`.pkg`**: double-click; installs into /Applications
- **`.zip`**: unzip and move GateView.app wherever you like

All three hold the same Universal app (Apple Silicon + Intel).

> The app and installer aren't notarized. On first launch, right-click → **Open** (or System Settings → Privacy & Security → **Open Anyway**). The .pkg may need the same.

## Build from source

Requires Xcode 15+ command line tools.

```bash
./build.sh      # → build/GateView.app (arm64 + x86_64)
./release.sh    # → dist/*.dmg, *.pkg, *.zip, SHA256SUMS.txt
```

Self-check for the prayer, weather, stats, countdown, theme and Now Playing logic:

```bash
swiftc GateView/Models/*.swift GateView/Services/{PrayerTimeService,WeatherService,SystemStatsService,ReminderService,ThemeStore,MoodEngine,WallpaperColorService,NowPlayingService,AppleScriptNowPlaying,RemindersService,GalleryService,L10n}.swift Tests/main.swift -o /tmp/gv-check && /tmp/gv-check
```

## Customize

Use the menu bar icon → **Settings…**, or edit `~/.config/gateview/theme.json`. Any subset of keys works; missing keys keep their defaults:

```json
{
  "accent": "#7FDBFF",
  "font": "rounded",
  "clockSize": 200,
  "panelSide": "left",
  "greetingName": "Ghani",
  "city": "Jakarta",
  "latitude": -6.2,
  "longitude": 106.82,
  "iqamah": { "Maghrib": 5 },
  "adhanPath": "~/Sounds/azan.mp3",
  "countdowns": [{ "title": "Lebaran", "date": "2027-03-10" }]
}
```

| Key | Values |
|---|---|
| `accent` | hex color |
| `font` | `default` · `rounded` · `serif` · `monospaced` |
| `clockWeight` | `ultraLight` · `thin` · `light` · `regular` · `medium` · `bold` |
| `clockSize`, `showSeconds`, `panelSide` (`right`/`left`) | layout |
| `glassTint`, `scrim`, `menuBarScrim` | 0–1 darkness of the glass, the bottom gradient and the menu bar fade |
| `showWeather`, `showStats` | left-side widgets on/off |
| `city`, `country`, `prayerMethod`, `latitude`, `longitude` | location ([method ids](https://aladhan.com/calculation-methods)) |
| `iqamah` | minutes after adzan, per `Fajr`/`Dhuhr`/`Asr`/`Maghrib`/`Isha` |
| `accentMode` | `custom` · `wallpaper` |
| `motion`, `mood`, `interactive` | animations, time/prayer tint, clickable widgets |
| `weatherEffects` | `off` · `subtle` · `full` |
| `widgetOrder` | panel widgets in order, any of `prayer`, `agenda`, `nowPlaying`, `calendar`, `notes`, `reminders`, `countdown`, `gallery` |
| `galleryFolder`, `galleryInterval` | photo folder (default `~/Pictures`), seconds per photo |
| `reminderMode`, `reminderSound`, `reminders` | `off`/`banner`/`chime`, a system sound name, per-prayer on/off |
| `adhanPath`, `adhanPaths`, `adhanVolume` | audio file played at each adzan instead of the chime (global, per-prayer overrides like `{"Fajr": "~/azan-subuh.mp3"}`, 0–1 volume) |
| `countdowns` | list of `{ "title", "date" ("yyyy-MM-dd"), "symbol" }` for the Countdown widget |
| `language`, `autoHideFullscreen` | `auto`/`id`/`en`, fade out while a fullscreen app is in front |
| `temperatureUnit`, `displayIndex` | `celsius`/`fahrenheit`, which screen (0 = main) |

## Roadmap

- **Windows & Linux (.deb) — coming soon.** GateView is coming to other desktops, with a bigger ambition than a port: a macOS-style **Dock** that replaces the Windows taskbar / Linux dock, and a macOS-style **menu bar** on top of the screen — the same ambient dashboard (clock, prayer times, weather, Now Playing, widgets) behind it all. The plan: a **Rust engine** (`gateview-core`, one shared implementation of prayer times, weather, config and localization) with a Tauri 2 shell — full breakdown, feature mapping and milestones in [docs/CROSSPLATFORM.md](docs/CROSSPLATFORM.md).

## Notes

- **Now Playing** uses Apple's private MediaRemote framework. On macOS 15.4 and newer Apple blocks it, so GateView falls back to polling **Spotify and Music via AppleScript** (macOS asks for Automation permission once; browser playback can't be read there). On older macOS versions all players keep working with no permission prompts.
- GateView isn't sandboxed (MediaRemote needs that), and it is not on the Mac App Store.
- Releasing with a Developer ID: put `APPLE_DEVELOPER_ID`, `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_KEYCHAIN_PROFILE` in `~/.config/gateview/release.env` and `./release.sh` signs, notarizes and staples automatically. `Casks/gateview.rb` is the Homebrew cask template for [homebrew-cask](https://github.com/Homebrew/homebrew-cask).

## Project layout

```
GateView/
├── GateViewApp.swift        app entry, menu bar, settings window
├── WindowManager.swift      desktop-level, click-through overlay window
├── DashboardView.swift      layout + glass
├── Views/                   widgets, Details/ cards, Settings/ app, weather effects, motion
├── ViewModels/              DashboardViewModel
├── Services/                prayer, weather (+air quality), calendar, reminders, now playing (+AppleScript fallback), stats, reminder/adhan, countdown, theme, mood, wallpaper colour, update check
└── Models/
```
