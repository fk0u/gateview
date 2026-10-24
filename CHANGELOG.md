# Changelog

All notable changes to GateView. The app follows semver-ish numbering; every release ships as a universal (Apple Silicon + Intel) build.

## Unreleased

### Added
- **Rust engine, milestone M0** (`crates/gateview-core`): the platform-agnostic core for the upcoming Windows & Linux ports — prayer times (Aladhan), weather + air-quality parsing, countdown, mood, Indonesian/English strings, `theme.json` decoding, and the Umm al-Qura Hijri calendar. Verified against a golden dataset printed by the Swift app itself (prayer times identical to the minute); CI now runs both engines (macOS Swift self-check + `cargo test`).
- **Windows shell, milestone M1** (`app/src-tauri` + `app/ui` + `crates/gateview-providers`): Tauri 2 overlay — transparent, always-on-top, click-through outside widgets; clock, prayer times with phase countdown, weather + air quality, Now Playing via the Windows SMTC API (with artwork), Countdown and Notes widgets; acrylic glass; theme.json live reload (same schema as macOS); adzan reminders with audio playback; auto-hide on fullscreen apps. Type-checked for `x86_64-pc-windows-msvc`; the .msi build itself runs on Windows.


## 2.3.0 — 2026-10-24

### Added
- **Now Playing on macOS 15.4+.** When Apple's private MediaRemote framework is blocked (macOS 15.4+/26+), GateView now polls Spotify and Music via AppleScript — track, artist, album, artwork (from Spotify's artwork URL), play/pause/next/previous, and a working seek bar. macOS asks for Automation permission once per player. On macOS ≤ 15.3 all players (including browsers) keep working through MediaRemote with no prompts.
- **Reminders widget** for the glass panel: open Apple Reminders with checkmarks you can tick right on the desktop; the expanded card adds a field to create new reminders. Calendar access is only requested when the widget is actually in the panel.
- **Countdown widget**: days-until entries declared in theme.json (`"countdowns": [{"title": "Lebaran", "date": "2027-03-10"}]`) or edited in Settings → Widgets. Compact shows the nearest date with a big day count; expanded lists everything.
- **Adhan audio**: in chime mode, `adhanPath` (global) or `adhanPaths` (per prayer, e.g. `{"Fajr": "~/azan-subuh.mp3"}`) plays a real audio file at every adzan instead of the chime. `adhanVolume` (0–1) controls loudness; a missing file falls back to the chime.
- **Air quality** in the weather detail card: US AQI + PM2.5 from Open-Meteo's air-quality endpoint (still no API key), with a colour-coded band.
- **Auto-hide on fullscreen**: the dashboard fades out while a fullscreen app (presentation, game) is in front and returns when you're back on the desktop. Toggle in Settings → General (`autoHideFullscreen`).
- **Indonesian/English UI**: greeting, weather labels, Notes, Reminders and Countdown strings. `language`: `auto`/`id`/`en` in theme.json or Settings.
- **Update check**: once a day against GitHub Releases; shows in the menu bar ("Update x.y.z tersedia…") and in Settings → About. Works unsigned (chosen over Sparkle for exactly that reason).
- **Reduce Transparency** support: with the Accessibility setting on, glass panels render as a solid scrim instead of behind-window blur.
- **For maintainers**: `build.sh` signs with a Developer ID when `APPLE_DEVELOPER_ID` is set (ad-hoc otherwise); `release.sh` notarizes and staples the .dmg/.pkg when `APPLE_ID`/`APPLE_TEAM_ID`/`APPLE_KEYCHAIN_PROFILE` are present (from `~/.config/gateview/release.env`). `Casks/gateview.rb` is a Homebrew cask ready for homebrew-cask.

## 2.2.1 — 2026-10-23
- Fixed: widgets didn't open on click.
- Fixed: widget clicks were swallowed by Finder's desktop-icon window.

## 2.2 — 2026-10-23
- Modular glass panel: pick and order Prayer, Agenda, Now Playing, Calendar, Notes, Gallery (experimental).
- Calendar widget (month view, Hijri dates, per-day agenda), Notes widget (typed right on the desktop, saved to `~/.config/gateview/notes.md`), Gallery widget.
- Seekable Now Playing detail with a progress bar.

## 2.1 — 2026-10-23
- Menu bar fade: the translucent system menu bar becomes a soft gradient instead of a wallpaper-coloured strip.
- `.pkg` installer alongside the `.dmg` and `.zip`.

## 2.0 — 2026-10-23
- Performance pass (~16 MB RAM, ~2% CPU), test suite and self-check script, README.
- Interactive widgets: hover highlight, click-to-expand detail cards (prayer week, hourly + 5-day weather, agenda, CPU/RAM sparkline).
- Motion: rolling digits, entrance animation, phase cross-fade.
- Mood tint follows time of day and prayer; accent can follow the wallpaper.
- Live weather effects (drizzle, rain, storm flash, fog) drawn by Core Animation on the GPU.
- Settings app with sidebar, presets, city search, per-prayer reminders.

## 1.2 — 2026-10-23
- First ambient desktop dashboard: wallpaper-level click-through overlay, clock, prayer times (Aladhan), weather (Open-Meteo), Now Playing, agenda, system stats, glass, reminders, `theme.json`.
