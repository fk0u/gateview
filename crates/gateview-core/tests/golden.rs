//! Golden dataset: the values below are PRINTED BY THE SWIFT APP ITSELF
//! (`Tests/golden.swift` on macOS) and must stay identical here, to the minute.
//! Regenerate with:
//!   swiftc GateView/Models/*.swift GateView/Services/{PrayerTimeService,ThemeStore}.swift \
//!     Tests/golden.swift -o /tmp/gv-golden && /tmp/gv-golden Tests/fixtures/aladhan-timings.json

use gateview_core::config::Theme;
use gateview_core::hijri::hijri_id;
use gateview_core::l10n::greeting;
use gateview_core::prayer::{countdown_to, default_iqamah, prayers_from, PrayerDay};
use chrono::TimeZone;
use std::collections::BTreeMap;

const FIXTURE: &str = include_str!("../../../Tests/fixtures/aladhan-timings.json");

fn friday() -> chrono::DateTime<chrono::Utc> {
    chrono::Utc.with_ymd_and_hms(2026, 10, 23, 0, 0, 0).unwrap() // a Friday; UTC fields = local wall clock
}

fn timings() -> BTreeMap<String, String> {
    #[derive(serde::Deserialize)]
    struct Payload {
        data: Dat,
    }
    #[derive(serde::Deserialize)]
    struct Dat {
        timings: BTreeMap<String, String>,
    }
    serde_json::from_str::<Payload>(FIXTURE).unwrap().data.timings
}

#[test]
fn prayers_friday_default_iqamah_match_swift() {
    let day = PrayerDay { date: "23-10-2026".into(), timings: timings() };
    let got: Vec<String> = prayers_from(&day, friday(), &default_iqamah())
        .iter()
        .map(|p| format!(
            "{} {} iqamah={} jumat={}",
            p.key,
            p.time.format("%H:%M"),
            p.iqamah.map(|t| t.format("%H:%M").to_string()).unwrap_or_else(|| "-".into()),
            p.is_jumat
        ))
        .collect();
    let expected = [
        "Fajr 04:34 iqamah=04:44 jumat=false",
        "Dhuhr 11:56 iqamah=- jumat=true",
        "Asr 15:13 iqamah=15:23 jumat=false",
        "Maghrib 18:00 iqamah=18:07 jumat=false",
        "Isha 19:10 iqamah=19:20 jumat=false",
    ];
    assert_eq!(got, expected);
}

#[test]
fn prayers_thursday_custom_iqamah_match_swift() {
    let day = PrayerDay { date: "23-10-2026".into(), timings: timings() };
    let thursday = friday() - chrono::Duration::days(1);
    let mut iq = default_iqamah();
    iq.insert("Maghrib".into(), 3);
    let got: Vec<String> = prayers_from(&day, thursday, &iq)
        .iter()
        .map(|p| format!(
            "{} {} iqamah={}",
            p.key,
            p.time.format("%H:%M"),
            p.iqamah.map(|t| t.format("%H:%M").to_string()).unwrap_or_else(|| "-".into())
        ))
        .collect();
    let expected = [
        "Fajr 04:34 iqamah=04:44",
        "Dhuhr 11:56 iqamah=12:06",
        "Asr 15:13 iqamah=15:23",
        "Maghrib 18:00 iqamah=18:03",
        "Isha 19:10 iqamah=19:20",
    ];
    assert_eq!(got, expected);
}

#[test]
fn countdown_matches_swift() {
    let base = |h: u32, m: u32| chrono::Utc.with_ymd_and_hms(2026, 10, 23, h, m, 0).unwrap();
    assert_eq!(countdown_to(base(15, 23), base(15, 18)), "05:00");
    assert_eq!(countdown_to(base(16, 23), base(15, 18)), "01:05:00");
}

#[test]
fn hijri_matches_swift_umm_al_qura() {
    assert_eq!(hijri_id(2026, 10, 23).as_deref(), Some("12 Jumadilawal 1448 H"));
    assert_eq!(hijri_id(2026, 3, 20).as_deref(), Some("1 Syawal 1447 H"));
    assert_eq!(hijri_id(2025, 2, 28).as_deref(), Some("29 Syakban 1446 H"));
    assert_eq!(hijri_id(2027, 1, 1).as_deref(), Some("23 Rajab 1448 H"));
    assert_eq!(hijri_id(2026, 6, 17).as_deref(), Some("2 Muharam 1448 H"));
}

#[test]
fn greetings_and_theme_behave_like_swift() {
    assert_eq!(greeting(9, "", "id"), "Selamat Pagi");
    assert_eq!(greeting(13, "Ghani", "id"), "Selamat Siang, Ghani");
    assert_eq!(greeting(20, "", "en"), "Good Evening");
    assert_eq!(Theme::decode(br##"{"accent": "#00FF88", "panelSide": "left"}"##).unwrap().city, "Samarinda");
    assert_eq!(Theme::default().location_key().split('|').next(), Some("Samarinda"));
}
