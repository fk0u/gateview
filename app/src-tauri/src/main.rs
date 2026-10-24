#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

//! GateView Windows/Linux shell (Tauri 2). All logic lives in gateview-core /
//! gateview-providers; this crate owns the window, the service loops and the
//! click-through overlay behaviour — a port of the macOS WindowManager flow.

use gateview_core::config::Theme;
use gateview_core::countdown::{self, Countdown};
use gateview_core::prayer::{self, Prayer, PrayerDay, PrayerPhase};
use gateview_core::weather::{self, Weather};
use gateview_providers::stats::{Sample, Stats};
use gateview_providers::NowPlayingInfo;
use serde::Serialize;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{mpsc, Mutex};
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_notification::NotificationExt;

#[derive(Default)]
struct State {
    theme: Mutex<Theme>,
    prayers: Mutex<Vec<Prayer>>,
    weather: Mutex<Option<Weather>>,
    now_playing: Mutex<Option<NowPlayingInfo>>,
    stats: Mutex<Option<Sample>>,
    regions: Mutex<HashMap<String, [i32; 4]>>, // physical px, relative to the window
}

#[derive(Serialize, Clone)]
struct PrayerRow {
    name: String,
    key: String,
    time: String,
    iqamah: Option<String>,
    is_jumat: bool,
}

#[derive(Serialize, Clone)]
struct PhaseRow {
    kind: String, // upcoming | iqamah | ongoing
    name: String,
    remaining: String,
}

#[derive(Serialize, Clone)]
struct CountdownRow {
    title: String,
    date: String,
    days: i64,
}

#[derive(Serialize, Clone)]
struct Payload {
    theme: Theme,
    prayers: Vec<PrayerRow>,
    phase: Option<PhaseRow>,
    weather: Option<Weather>,
    now_playing: Option<NowPlayingInfo>,
    countdowns: Vec<CountdownRow>,
    stats: Option<Sample>,
    notes: String,
}

fn build_payload(state: &State, notes: &str) -> Payload {
    let theme = state.theme.lock().unwrap().clone();
    let prayers = state.prayers.lock().unwrap().clone();
    let now = chrono::Utc::now();
    let rows: Vec<PrayerRow> = prayers
        .iter()
        .map(|p| PrayerRow {
            name: p.name.clone(),
            key: p.key.clone(),
            time: p.time.format("%H:%M").to_string(),
            iqamah: p.iqamah.map(|t| t.format("%H:%M").to_string()),
            is_jumat: p.is_jumat,
        })
        .collect();
    let phase = prayer::phase_at(now, &prayers).map(|ph| match ph {
        PrayerPhase::Upcoming(p) => PhaseRow {
            kind: "upcoming".into(),
            name: p.name.clone(),
            remaining: prayer::countdown_to(p.time, now),
        },
        PrayerPhase::Iqamah(p) => PhaseRow {
            kind: "iqamah".into(),
            name: p.name.clone(),
            remaining: prayer::countdown_to(p.iqamah.unwrap_or(p.time), now),
        },
        PrayerPhase::Ongoing(p) => PhaseRow { kind: "ongoing".into(), name: p.name.clone(), remaining: "".into() },
    });
    let countdowns = countdown::upcoming(&theme.countdowns, now)
        .iter()
        .filter_map(|c: &Countdown| {
            Some(CountdownRow {
                title: c.title.clone(),
                date: c.date.clone(),
                days: Countdown::days_until(c.target()?, now),
            })
        })
        .collect();
    Payload {
        theme,
        prayers: rows,
        phase,
        weather: state.weather.lock().unwrap().clone(),
        now_playing: state.now_playing.lock().unwrap().clone(),
        countdowns,
        stats: state.stats.lock().unwrap().clone(),
        notes: notes.to_string(),
    }
}

// MARK: - Commands

#[tauri::command]
fn get_state(state: tauri::State<'_, State>, notes: tauri::State<'_, Notes>) -> Payload {
    build_payload(&state, &notes.text.lock().unwrap())
}

#[tauri::command]
fn set_hit_regions(state: tauri::State<'_, State>, regions: HashMap<String, [i32; 4]>) {
    *state.regions.lock().unwrap() = regions;
}

#[derive(Default)]
struct Notes {
    text: Mutex<String>,
}

#[tauri::command]
fn save_notes(notes: tauri::State<'_, Notes>, path: tauri::State<'_, ConfigPaths>, text: String) {
    *notes.text.lock().unwrap() = text.clone();
    let _ = std::fs::write(&path.notes, text);
}

struct ConfigPaths {
    notes: PathBuf,
}

// MARK: - Service loops

fn load_theme(path: &PathBuf) -> Theme {
    std::fs::read(path)
        .map(|bytes| Theme::decode(&bytes).unwrap_or_else(|_| Theme::default()))
        .unwrap_or_default()
}

/// Reload theme.json whenever the editor saves it (same live-reload contract as macOS).
fn theme_watcher(app: AppHandle, theme_path: PathBuf) {
    let (tx, rx) = mpsc::channel::<()>();
    let mut watcher = notify::recommended_watcher(move |_| {
        let _ = tx.send(());
    })
    .expect("notify watcher");
    if let Some(dir) = theme_path.parent() {
        let _ = notify::Watcher::watch(&mut watcher, dir, notify::RecursiveMode::NonRecursive);
    }
    // Debounce editors that write in several steps.
    while let Ok(()) = rx.recv() {
        std::thread::sleep(Duration::from_millis(300));
        while rx.try_recv().is_ok() {}
        let theme = load_theme(&theme_path);
        {
            let state = app.state::<State>();
            *state.theme.lock().unwrap() = theme.clone();
        }
        let _ = app.emit("theme", &theme);
    }
}

/// Fetch prayer times when the day or location changes; re-emit with a fresh phase twice a minute.
fn prayer_loop(app: AppHandle) {
    let mut cached: Option<(String, String, PrayerDay)> = None; // (day_key, location_key, day)
    loop {
        let theme = app.state::<State>().theme.lock().unwrap().clone();
        let today = prayer::day_key(chrono::Utc::now());
        let location = theme.location_key();
        let needs_fetch = match &cached {
            Some((day, loc, _)) => day != &today || loc != &location,
            None => true,
        };
        if needs_fetch {
            match prayer::fetch_today(&theme.city, &theme.country, theme.prayer_method) {
                Ok(day) => {
                    let prayers = prayer::prayers_from(&day, chrono::Utc::now(), &theme.iqamah);
                    *app.state::<State>().prayers.lock().unwrap() = prayers;
                    cached = Some((today, location, day));
                }
                Err(e) => eprintln!("prayer fetch failed: {e}"),
            }
        }
        let notes = app.state::<Notes>().text.lock().unwrap().clone();
        let _ = app.emit("dashboard", build_payload(&app.state::<State>(), &notes));
        std::thread::sleep(Duration::from_secs(30));
    }
}

fn weather_loop(app: AppHandle) {
    loop {
        let theme = app.state::<State>().theme.lock().unwrap().clone();
        let unit = if theme.temperature_unit == "fahrenheit" { "fahrenheit" } else { "celsius" };
        match weather::fetch(theme.latitude, theme.longitude, unit) {
            Ok(w) => {
                *app.state::<State>().weather.lock().unwrap() = Some(w);
                let notes = app.state::<Notes>().text.lock().unwrap().clone();
                let _ = app.emit("dashboard", build_payload(&app.state::<State>(), &notes));
            }
            Err(e) => eprintln!("weather fetch failed: {e}"),
        }
        std::thread::sleep(Duration::from_secs(30 * 60));
    }
}

fn stats_loop(app: AppHandle) {
    let mut stats = Stats::new();
    loop {
        let sample = stats.sample();
        *app.state::<State>().stats.lock().unwrap() = Some(sample.clone());
        let _ = app.emit("stats", &sample);
        std::thread::sleep(Duration::from_secs(2));
    }
}

/// Windows: consume SMTC polls. Other platforms emit nothing yet (MPRIS is M3).
fn now_playing_loop(app: AppHandle, rx: Option<mpsc::Receiver<Option<NowPlayingInfo>>>) {
    let Some(rx) = rx else {
        loop {
            std::thread::sleep(Duration::from_secs(3600));
        }
    };
    let mut last: Option<NowPlayingInfo> = None;
    while let Ok(info) = rx.recv() {
        let structural = info.as_ref().map(|i| i.title.clone()) != last.as_ref().map(|i| i.title.clone())
            || info.as_ref().map(|i| i.is_playing) != last.as_ref().map(|i| i.is_playing);
        *app.state::<State>().now_playing.lock().unwrap() = info.clone();
        if structural {
            let notes = app.state::<Notes>().text.lock().unwrap().clone();
            let _ = app.emit("dashboard", build_payload(&app.state::<State>(), &notes));
        }
        last = info;
    }
}

/// Banner + adhan audio at each adzan (port of ReminderService's chime path).
fn reminder_loop(app: AppHandle) {
    let mut stream = None;
    loop {
        let theme = app.state::<State>().theme.lock().unwrap().clone();
        let prayers = app.state::<State>().prayers.lock().unwrap().clone();
        let now = chrono::Utc::now();
        let next = prayers.iter().find(|p| p.time > now).cloned();
        match next {
            Some(p) if theme.reminder_mode != "off" && theme.reminders.get(&p.key).copied().unwrap_or(true) => {
                let wait = (p.time - now).to_std().unwrap_or(Duration::from_secs(5));
                std::thread::sleep(wait);
                if chrono::Utc::now() < p.time + chrono::Duration::seconds(60) {
                    let _ = app.notification().builder().title(format!("Waktu {}", p.name)).body("Adzan").show();
                    if theme.reminder_mode == "chime" {
                        if let Some(path) = adhan_path(&theme, &p.key) {
                            stream = play_audio(&path, theme.adhan_volume as f32, stream);
                        }
                    }
                }
            }
            _ => std::thread::sleep(Duration::from_secs(300)),
        }
    }
}

fn expand_home(raw: &str) -> PathBuf {
    if let Some(rest) = raw.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("USERPROFILE").or_else(|| std::env::var_os("HOME")) {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(raw)
}

/// Per-prayer adhan file, else the global one (mirror of ReminderService.adhanPath).
fn adhan_path(theme: &Theme, key: &str) -> Option<PathBuf> {
    let raw = theme.adhan_paths.get(key).cloned().unwrap_or_else(|| theme.adhan_path.clone());
    if raw.is_empty() {
        return None;
    }
    let path = expand_home(&raw);
    path.exists().then_some(path)
}

/// Keeps the audio sink alive while playing; returns it so the loop can hold it.
#[cfg(windows)]
fn play_audio(path: &PathBuf, volume: f32, prev: Option<rodio::OutputStream>) -> Option<rodio::OutputStream> {
    drop(prev);
    let Ok((stream, sink)) = rodio::OutputStream::try_default() else { return None };
    if let Ok(file) = std::fs::File::open(path) {
        if let Ok(source) = rodio::Decoder::new(std::io::BufReader::new(file)) {
            sink.set_volume(volume.clamp(0.0, 1.0));
            sink.append(source);
            sink.sleep_until_end(); // simple: block this loop until the adhan finishes
        }
    }
    Some(stream)
}

#[cfg(not(windows))]
fn play_audio(_path: &PathBuf, _volume: f32, prev: Option<()>) -> Option<()> {
    prev
}

/// The overlay behaviour: auto-hide on fullscreen apps + click-through outside widgets.
#[cfg(windows)]
fn overlay_loop(app: AppHandle) {
    let Some(win) = app.get_webview_window("main") else { return };
    let mut last_suppress = false;
    let mut last_ignore: Option<bool> = None;
    loop {
        let state = app.state::<State>();
        let theme = state.theme.lock().unwrap().clone();
        let suppress = theme.auto_hide_fullscreen && gateview_providers::win32::frontmost_is_fullscreen();
        if suppress != last_suppress {
            last_suppress = suppress;
            let _ = if suppress { win.hide() } else { win.show() };
        }
        let ignore = if !theme.interactive || suppress {
            true
        } else {
            match gateview_providers::win32::cursor_pos().zip(win.outer_position().ok()) {
                Some(((cx, cy), pos)) => {
                    let (lx, ly) = (cx - pos.x, cy - pos.y);
                    state.regions.lock().unwrap().values().any(|[x, y, w, h]| {
                        lx >= *x && lx < *x + *w && ly >= *y && ly < *y + *h
                    })
                }
                None => true,
            }
        };
        if last_ignore != Some(ignore) {
            last_ignore = Some(ignore);
            let _ = win.set_ignore_cursor_events(ignore);
        }
        std::thread::sleep(Duration::from_millis(40));
    }
}

#[cfg(not(windows))]
fn overlay_loop(_app: AppHandle) {}

// MARK: - Setup

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .invoke_handler(tauri::generate_handler![get_state, set_hit_regions, save_notes])
        .setup(|app| {
            let config_dir = app.path().app_config_dir()?;
            std::fs::create_dir_all(&config_dir).ok();
            let theme_path = config_dir.join("theme.json");
            let notes_path = config_dir.join("notes.md");
            if !theme_path.exists() {
                let json = serde_json::to_string_pretty(&Theme::default()).unwrap();
                std::fs::write(&theme_path, json).ok();
            }
            let notes_text = std::fs::read_to_string(&notes_path).unwrap_or_default();
            let theme = load_theme(&theme_path);

            // Overlay covers the whole monitor, like the macOS window.
            if let Some(win) = app.get_webview_window("main") {
                if let Some(monitor) = win.current_monitor().ok().flatten() {
                    let _ = win.set_size(tauri::PhysicalSize::new(monitor.size().width, monitor.size().height));
                    let _ = win.set_position(tauri::PhysicalPosition::new(monitor.position().x, monitor.position().y));
                }
                #[cfg(windows)]
                {
                    // Acrylic glass; solid scrim is the fallback (window background stays dark).
                    if let Err(e) = window_vibrancy::apply_acrylic(&win, Some((18, 24, 38, 125))) {
                        eprintln!("acrylic unavailable: {e}");
                    }
                }
            }

            app.manage(ConfigPaths { notes: notes_path });
            app.manage(Notes { text: Mutex::new(notes_text) });
            app.manage(State { theme: Mutex::new(theme), ..Default::default() });

            let handle = app.handle().clone();
            std::thread::spawn(move || theme_watcher(handle.clone(), theme_path));

            let handle = app.handle().clone();
            std::thread::spawn(move || prayer_loop(handle));

            let handle = app.handle().clone();
            std::thread::spawn(move || weather_loop(handle));

            let handle = app.handle().clone();
            std::thread::spawn(move || stats_loop(handle));

            let (tx, rx) = mpsc::channel();
            #[cfg(windows)]
            gateview_providers::smtc::spawn(tx);
            #[cfg(not(windows))]
            drop(tx);
            let handle = app.handle().clone();
            std::thread::spawn(move || now_playing_loop(handle, Some(rx)));

            let handle = app.handle().clone();
            std::thread::spawn(move || reminder_loop(handle));

            let handle = app.handle().clone();
            std::thread::spawn(move || overlay_loop(handle));
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running GateView");
}
