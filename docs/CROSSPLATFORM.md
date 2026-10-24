# GateView on Windows & Linux — Rust Architecture

Status: proposal, October 2026. macOS GateView (Swift/SwiftUI, shipped as v2.3) stays as-is; this document covers the second front: **Windows + Linux (.deb)**, where the headline feature is a **macOS-style Dock that replaces the taskbar / native dock**, plus a **macOS-style menu bar**.

---

## 1. Why Rust is the right base (and where it isn't enough alone)

Rust covers everything GateView is *underneath* the pixels: HTTP services, parsing, scheduling, config. What it does not give you out of the box is the desktop shell experience (transparent click-through overlays, blur, global shortcuts, per-DE integration) — that comes from the crates below plus platform APIs.

**UI framework decision** — the one big fork in the road:

| Option | Verdict | Why |
|---|---|---|
| **Tauri 2** (Rust core + webview UI) | ✅ **Recommended** | Widgets are static-ish glass cards — HTML/CSS nails this (backdrop-filter, fonts, animations). Tauri ships transparency, `set_ignore_cursor_events` (click-through), always-on-top, multi-window, tray, global shortcut, MSI/.deb/AppImage bundling — all cross-platform. Rust stays in charge of all logic. |
| iced / egui (pure Rust UI) | Reserve for the Dock itself if needed | GPU-drawn, low latency, but glass blur + typography + animations mean hand-rolling what CSS gives free. Egui has no retained widget tree; iced's ecosystem is young. |
| Slint | No | Nice declarative Rust, but licensing (GPL/commercial) and smaller ecosystem. |
| GTK4-rs | No for Windows | First-class on Linux, second-class on Windows (theming, packaging pain). |

**Consequence:** hybrid — **Rust workspace for the engine, Tauri 2 for the chrome**. The webview cost (~40–80 MB per window) is acceptable on Windows/Linux, and we can keep one rendering path for widgets while the Dock (the latency-sensitive piece) can later graduate to a dedicated `iced`/raw-WGPU window if the webview ever shows jank — the shell design below allows that swap without touching the core.

## 2. Workspace layout

```
gateview/
├── crates/
│   ├── gateview-core/        # pure Rust, no UI, no platform deps — 100% shared with any UI
│   │   ├── prayer/           #   Aladhan client + cache (port of PrayerTimeService)
│   │   ├── weather/          #   Open-Meteo forecast + air quality (port of WeatherService)
│   │   ├── countdown.rs      #   CountdownService
│   │   ├── mood.rs           #   MoodEngine
│   │   ├── config.rs         #   theme.json — same schema, partial decode, live reload (notify crate)
│   │   ├── l10n.rs           #   the ID/EN string table (port of L10n.swift)
│   │   └── reminders-core.rs #   list/toggle semantics, provider-agnostic
│   ├── gateview-shell/       # dock + menu bar window management (platform trait + impls)
│   └── gateview-providers/   # per-platform service impls (feature-gated)
│       ├── src/windows/      #   windows-rs: SMTC, stats, notifications, DWM blur
│       └── src/linux/        #   zbus: MPRIS, notifications, EDS/KCalendarCore, sysinfo
├── app/                      # Tauri 2 app: frontend/ (TS + Svelte or Solid) + src-tauri/
└── desktop/                  # macOS (existing Swift project) — untouched
```

`gateview-core` mirrors the Swift services 1:1, so the JSON schema of `~/.config/gateview/theme.json` stays identical on all three OSes — docs, presets and user habits carry over.

## 3. Feature mapping macOS → Windows/Linux

| GateView feature | Windows | Linux |
|---|---|---|
| Glass blur | Win11: DWM backdrop (`DwmSetWindowAttribute` `SystemBackdrop`, acrylic via `windows-rs`); Win10: `SetWindowCompositionAttribute` blur, solid-scrim fallback (same as our Reduce-Transparency path) | KDE: blur behind via KWin; wlroots: layer-shell + compositor blur; GNOME: solid scrim (GNOME blocks third-party blur) |
| Click-through overlay | `WS_EX_TRANSPARENT`/`WS_EX_LAYERED` or Tauri `set_ignore_cursor_events` + per-region toggle (same hit-region idea as `WindowManager`) | X11: shape extension / input region; Wayland: layer-shell input region |
| Now Playing | `GlobalSystemMediaTransportSessionManager` (SMTC) via windows-rs — Spotify, browsers, everything that posts to SMTC | MPRIS over D-Bus (`zbus` crate) — Spotify, browsers, players; richer than SMTC (position seek works) |
| Media control | SMTC `TryPlayAsync`/`TrySkipNextAsync`, or virtual key events | MPRIS `PlayPause`/`Next`/`Seek` |
| Prayer reminder | Windows notifications (Tauri notification plugin / WinRT toast) + `rodio` for adhan/chime | org.freedesktop.Notifications + `rodio` |
| Stats (CPU/RAM/battery) | `sysinfo` (works everywhere) | `sysinfo` |
| Agenda / Reminders | v1: ICS subscription URL or local `.ics`; v2: WinRT Appointments API | v1: ICS; v2: Evolution Data Server (GNOME) / KCalendarCore (KDE) via D-Bus |
| Wallpaper accent | Read active wallpaper via `IDesktopWallpaper`, downsample + dominant colour (port of WallpaperColorService) | `org.freedesktop.portal.Settings`/plasma D-Bus, same algorithm |
| Notes | Plain file `~/.config/gateview/notes.md` — identical | Identical |
| Update check | Same UpdateService logic → GitHub Releases | Same |

## 4. The Dock (the headline feature)

### 4.1 What "replace the taskbar/dock" realistically means

True shell replacement is possible on both platforms but is fragile and scary for users:

- **Windows**: replacing the taskbar = killing Explorer and registering a shell replacement. Breaks with every Windows update; not what 99% of users want.
- **GNOME**: no dock API; extensions like Dash to Dock exist but GateView can't require extension installs.
- **KDE**: panels are replaceable-ish but again, invasive.

**Strategy: edge-occupying overlay dock, not shell replacement.** GateView's dock is a bottom-edge, always-on-top, click-through-outside-dots surface that:

1. **Windows**: reserving space via `SHAppBarMessage` (the official AppBar API — the same one used by RocketDock/ObjectDock). The real taskbar can be auto-hidden (we offer a one-click toggle that sets `STUCKRECTS`/`AppBar` autohide for the user), giving the GateView dock the taskbar's place without killing Explorer. Zoom regions, jump lists (v2: `ITaskbarList3` thumbs are out of reach for foreign windows — skip) — icons: pinned apps read from `%APPDATA%` taskbar pins in v2, v1 ships a manual pin list + running windows via `EnumWindows`.
2. **KDE Plasma / wlroots Wayland**: a **layer-shell surface anchored bottom with exclusive zone** — the compositor literally reserves space for us like it does for its own panel. `smithay-client-toolkit` or GTK-layer-shell does this; it is the cleanest dock API of any DE.
3. **X11**: `_NET_WM_STRUT_PARTIAL` reserves edge space; always-on-top + input shaping for the magnification area.
4. **GNOME**: v1 = floating dock (no exclusive zone), documented limitation; v2 = companion extension that grants an edge zone.

Mac-like behaviours, in order of user-visible impact: magnification on hover ( neighbouring-icon spread — pure math on the webview or iced side), running-window dots, indicator for the frontmost app, right-click context menu, drag-to-pin (v2), minimized-window previews (v2: Windows DWM thumbnails; KDE PipeWire/plasma thumbnailer; X11 compositing of window IDs).

### 4.2 The menu bar

- Top edge, same layer-shell/AppBar/strut mechanism as the dock.
- v1 content: app launcher menu, our status items (clock, prayer countdown, Now Playing title), and a **tray/SNI area** — StatusNotifierItem via D-Bus on Linux (both KDE and modern GNOME-with-extension understand SNI), `Shell_NotifyIcon` re-hosting on Windows (v1 shows our own items only; showing *other apps'* tray icons on Windows means spawning an actual tray window and is a v2 project).
- App menus of the focused app (true macOS global menu): KDE supports it via the D-Bus global menu protocol (`com.canonical.AppMenu.Registrar`) — v2 on KDE. GNOME/Windows: not v1 (GNOME killed appmenu; Windows has no global menu protocol — only full window hacks). Be explicit in docs: on Windows/GNOME the bar shows GateView's own items, on KDE it shows the focused app's menus.

## 5. Runtime shape

- **Async core**: `tokio` + `reqwest` for Aladhan/Open-Meteo/air quality, `chrono-tz` for prayer times, `notify` for theme.json live-reload, `serde` with the exact same partial-merge decoding semantics (`Theme::decode`).
- **State ↔ UI bridge**: Tauri commands + events. Services publish `Event { PrayerUpdate, WeatherUpdate, NowPlayingUpdate, … }`; the webview widgets subscribe — a direct port of our ObservableObject flow.
- **Audio**: `rodio` for adhan/chime (mp3 via `symphonia`), replacing AVAudioPlayer.
- **Config dir**: `~/.config/gateview/` on Linux (identical), `%APPDATA%\gateview\` on Windows.

## 6. Distribution

| Platform | Artifact | Tooling |
|---|---|---|
| Windows | `.msi` + NSIS `.exe` | Tauri bundler (WiX) |
| Linux | `.deb` (primary, as requested), AppImage, AUR later | Tauri bundler `deb` target; AppImage via linuxdeploy |

Both bundle webview dependencies: Windows uses WebView2 (preinstalled on Win11, auto-installed otherwise), Linux uses WebKitGTK — **the `.deb` must `Depends: libwebkit2gtk-4.1-0, libgtk-3-0`**; AppImage sidesteps that for non-Debian distros.

## 7. Milestones

- **M0 — core extraction (weeks 1–2):** `gateview-core` with prayer/weather/countdown/config/l10n + Rust test suite mirroring `Tests/main.swift`. Deliverable: same numbers as the Swift implementation on a golden dataset (assert prayer times equal to the minute).
- **M1 — Windows MVP (weeks 3–6):** Tauri shell, dashboard widgets (clock, prayer, weather+AQ, Now Playing via SMTC, countdown, notes), auto-hide-on-fullscreen, glass/acrylic, installer. No dock yet — dashboard first.
- **M2 — Dock & menu bar Windows (weeks 7–10):** AppBar edge reservation, magnification, pins, tray area.
- **M3 — Linux MVP + .deb (weeks 11–14):** same widget set, MPRIS, notifications, KDE layer-shell dock, X11 strut fallback, `.deb` + AppImage.
- **M4 — parity:** ICS agenda/reminders, wallpaper accent, global menu on KDE, per-DE polish.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Wayland fragmentation (GNOME's no-layer-shell stance) | Target KDE + wlroots first-class, X11 fallback, GNOME floating mode documented |
| WebView2/WebKitGTK differences (fonts, backdrop-filter support) | Feature-detect; solid-scrim fallback path already exists as a design pattern from Reduce Transparency |
| Magnification jank in webview | Dock window is small & isolated; if needed, swap the dock window to iced/WGPU without touching core (§1) |
| Windows taskbar autohide tampering feels invasive | Make it opt-in with a clear explanation; dock works fine stacked above the taskbar too |
| Solo-dev bandwidth across 3 OSes | M0–M1 are pure Rust + web, one codebase; platform surface is confined to `gateview-providers` behind traits |

## 9. Alternatives considered

- **Electron**: ships Chromium (~150 MB), memory profile contradicts GateView's "ultra-light" identity. Rust keeps the brand honest.
- **Flutter Desktop**: good Windows, weak Linux dock/layer-shell story, Dart core means the "engine" isn't shareable with the macOS codebase's concepts and testing style.
- **Continue Swift via SkiaKit/GNUstep**: non-starters — no credible Windows/Linux shell integration.
- **Native per-platform (C#/WinUI + GTK/Rust)**: best integration, triple the maintenance. The hybrid Rust-core approach captures ~80% of the benefit at ~40% of the cost.
