//! Port of Services/ThemeStore.swift — the Theme struct and partial-decode semantics.
//! Same schema, same rules: any subset of keys is valid, missing keys keep defaults,
//! legacy flags (showAgenda/showNowPlaying) migrate, and unknown widgets are dropped.

use crate::countdown::Countdown;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// (key, name, SF Symbol, experimental) — every widget the glass panel can hold.
pub const CATALOG: [(&str, &str, &str, bool); 8] = [
    ("prayer", "Prayer times", "moon.stars.fill", false),
    ("agenda", "Agenda", "list.bullet.rectangle", false),
    ("nowPlaying", "Now Playing", "music.note", false),
    ("calendar", "Calendar", "calendar", false),
    ("notes", "Notes", "note.text", false),
    ("reminders", "Reminders", "checklist", false),
    ("countdown", "Countdown", "timer", false),
    ("gallery", "Gallery", "photo.on.rectangle", true),
];

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Theme {
    // Look
    pub accent: String,
    pub font: String,
    pub clock_size: f64,
    pub clock_weight: String,
    pub show_seconds: bool,
    pub panel_side: String,
    pub glass_tint: f64,
    pub scrim: f64,
    pub menu_bar_scrim: f64,
    pub greeting_name: String,

    // Widgets
    pub show_weather: bool,
    pub show_stats: bool,
    pub widget_order: Vec<String>,
    pub interactive: bool,
    pub display_index: usize,

    // Motion & mood
    pub accent_mode: String,
    pub motion: bool,
    pub mood: bool,
    pub weather_effects: String,

    // Reminder
    pub reminder_mode: String,
    pub reminder_sound: String,
    pub reminders: BTreeMap<String, bool>,
    pub temperature_unit: String,
    pub adhan_path: String,
    pub adhan_paths: BTreeMap<String, String>,
    pub adhan_volume: f64,

    // Behaviour
    pub language: String,
    pub auto_hide_fullscreen: bool,

    // Gallery (experimental)
    pub gallery_folder: String,
    pub gallery_interval: f64,

    // Countdown widget
    pub countdowns: Vec<Countdown>,

    // Location
    pub city: String,
    pub country: String,
    pub latitude: f64,
    pub longitude: f64,
    pub prayer_method: u32,
    pub iqamah: BTreeMap<String, i64>,
}

impl Default for Theme {
    fn default() -> Self {
        Theme {
            accent: "#FFC56B".into(),
            font: "default".into(),
            clock_size: 168.0,
            clock_weight: "ultraLight".into(),
            show_seconds: true,
            panel_side: "right".into(),
            glass_tint: 0.25,
            scrim: 0.45,
            menu_bar_scrim: 0.4,
            greeting_name: String::new(),

            show_weather: true,
            show_stats: true,
            widget_order: ["prayer", "agenda", "nowPlaying"].iter().map(|s| s.to_string()).collect(),
            interactive: true,
            display_index: 0,

            accent_mode: "custom".into(),
            motion: true,
            mood: true,
            weather_effects: "subtle".into(),

            reminder_mode: "off".into(),
            reminder_sound: "Glass".into(),
            reminders: ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].iter().map(|k| (k.to_string(), true)).collect(),
            temperature_unit: "celsius".into(),
            adhan_path: String::new(),
            adhan_paths: BTreeMap::new(),
            adhan_volume: 0.9,

            language: "auto".into(),
            auto_hide_fullscreen: true,

            gallery_folder: "~/Pictures".into(),
            gallery_interval: 30.0,

            countdowns: Vec::new(),

            city: "Samarinda".into(),
            country: "Indonesia".into(),
            latitude: -0.5022,
            longitude: 117.1536,
            prayer_method: 20, // Aladhan method id; 20 = Kemenag RI
            iqamah: crate::prayer::default_iqamah(),
        }
    }
}

impl Theme {
    /// Decodes a partial file exactly like the Swift app: user keys override defaults,
    /// old show*-flags migrate out of widgetOrder, everything else keeps its default.
    pub fn decode(data: &[u8]) -> Result<Theme, String> {
        let user: serde_json::Value = serde_json::from_slice(data).map_err(|e| e.to_string())?;
        if !user.is_object() {
            // Swift: a non-object JSON fails the array cast → decode error. Mirror that.
            return Err("theme.json must be an object".into());
        }
        let mut merged = serde_json::to_value(Theme::default()).expect("default theme serializes");
        merge(&mut merged, &user);

        // 2.1 → 2.2: the old show* flags become "not in widgetOrder".
        let flag_off = |flag: &str| user.get(flag) == Some(&serde_json::Value::Bool(false));
        if flag_off("showAgenda") {
            remove_key(&mut merged, "widgetOrder", "agenda");
        }
        if flag_off("showNowPlaying") {
            remove_key(&mut merged, "widgetOrder", "nowPlaying");
        }

        serde_json::from_value(merged).map_err(|e| e.to_string())
    }

    /// Known widgets only, no duplicates, in the user's order.
    pub fn panel_widgets(&self) -> Vec<String> {
        let mut seen = std::collections::HashSet::new();
        self.widget_order
            .iter()
            .filter(|k| CATALOG.iter().any(|c| c.0 == **k) && seen.insert(k.as_str()))
            .cloned()
            .collect()
    }

    /// Location identity: refetch prayer times & weather when it changes.
    pub fn location_key(&self) -> String {
        let iq: Vec<String> = self.iqamah.iter().map(|(k, v)| format!("{k}{v}")).collect();
        format!("{}|{}|{}|{}|{}|{}", self.city, self.country, self.latitude, self.longitude, self.prayer_method, iq.join(","))
    }

    /// Resolved UI language: "id" or "en" ("auto" follows the system locale).
    /// The shell passes the system language in; `system_is_indonesian` mirrors Locale.current.
    pub fn display_language(&self, system_is_indonesian: bool) -> String {
        match self.language.as_str() {
            "id" | "en" => self.language.clone(),
            _ => if system_is_indonesian { "id" } else { "en" }.into(),
        }
    }
}

fn merge(base: &mut serde_json::Value, user: &serde_json::Value) {
    match (base, user) {
        (serde_json::Value::Object(base), serde_json::Value::Object(user)) => {
            for (k, v) in user {
                match base.get_mut(k) {
                    Some(slot) if slot.is_object() && v.is_object() => merge(slot, v),
                    _ => {
                        base.insert(k.clone(), v.clone());
                    }
                }
            }
        }
        (base, user) => *base = user.clone(),
    }
}

fn remove_key(merged: &mut serde_json::Value, list_key: &str, value: &str) {
    if let Some(serde_json::Value::Array(items)) = merged.get_mut(list_key) {
        items.retain(|v| v.as_str() != Some(value));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_decode_keeps_defaults() {
        let t = Theme::decode(br##"{"accent": "#00FF88", "panelSide": "left"}"##).unwrap();
        assert_eq!(t.accent, "#00FF88");
        assert_eq!(t.panel_side, "left");
        assert_eq!(t.city, "Samarinda");
        assert_eq!(t.clock_size, 168.0);
        assert_eq!(t.adhan_volume, 0.9);
        assert!(t.auto_hide_fullscreen);
    }

    #[test]
    fn bad_json_fails() {
        assert!(Theme::decode(b"{oops").is_err());
        assert!(Theme::decode(b"[]").is_err()); // non-object, like the Swift cast failure
    }

    #[test]
    fn legacy_flags_migrate() {
        let t = Theme::decode(br#"{"showAgenda": false, "showNowPlaying": true}"#).unwrap();
        assert_eq!(t.panel_widgets(), ["prayer", "nowPlaying"]);
    }

    #[test]
    fn one_dot_two_theme_still_loads() {
        let t = Theme::decode(br##"{"accent": "#FFC56B", "showWeather": false}"##).unwrap();
        assert!(!t.show_weather);
        assert!(t.interactive);
        assert_eq!(t.weather_effects, "subtle");
        assert_eq!(t.widget_order.len(), 3);
    }

    #[test]
    fn panel_widgets_dedupe_and_filter() {
        let mut t = Theme::default();
        t.widget_order = ["notes", "bogus", "prayer", "notes", "gallery", "reminders", "countdown"]
            .iter().map(|s| s.to_string()).collect();
        assert_eq!(t.panel_widgets(), ["notes", "prayer", "gallery", "reminders", "countdown"]);
        t.widget_order.retain(|k| k != "prayer");
        assert!(!t.panel_widgets().contains(&"prayer".to_string()));
    }

    #[test]
    fn countdowns_decode_and_location_key_is_stable() {
        let t = Theme::decode(
            br#"{"countdowns":[{"title":"Lebaran","date":"2027-03-10","symbol":"moon.stars"}]}"#,
        ).unwrap();
        assert_eq!(t.countdowns.len(), 1);
        assert_eq!(t.countdowns[0].symbol, "moon.stars");
        assert_eq!(t.location_key(), Theme::default().location_key());
        let mut u = Theme::default();
        u.latitude = 1.0;
        assert_ne!(t.location_key(), u.location_key());
    }
}
