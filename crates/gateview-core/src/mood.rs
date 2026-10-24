//! Port of Services/MoodEngine.swift — ambient tint that follows the day and the prayer times.

use crate::prayer::Prayer;
use chrono::{DateTime, Duration, Utc};

#[derive(Debug, Clone, PartialEq)]
pub struct Mood {
    pub name: String,
    pub tint: String, // hex colour washed over the scrim and glass
    pub tint_opacity: f64,
    pub scrim_delta: f64, // added to the theme's scrim
}

impl Default for Mood {
    fn default() -> Self {
        Mood { name: "day".into(), tint: "#000000".into(), tint_opacity: 0.0, scrim_delta: 0.0 }
    }
}

pub fn mood_at(now: DateTime<Utc>, prayers: &[Prayer]) -> Mood {
    let time = |key: &str| prayers.iter().find(|p| p.key == key).map(|p| p.time);
    let (Some(fajr), Some(asr), Some(maghrib), Some(isha)) =
        (time("Fajr"), time("Asr"), time("Maghrib"), time("Isha"))
    else {
        return Mood::default();
    };
    let sunrise = fajr + Duration::seconds(75 * 60);
    let night = isha + Duration::seconds(60 * 60);

    if now < fajr || now >= night {
        Mood { name: "night".into(), tint: "#0B1530".into(), tint_opacity: 0.3, scrim_delta: 0.2 }
    } else if now < sunrise {
        Mood { name: "dawn".into(), tint: "#4A6FA5".into(), tint_opacity: 0.2, scrim_delta: 0.05 }
    } else if now < asr {
        Mood::default()
    } else if now < maghrib {
        // Warmer the closer Maghrib gets.
        let progress = (now - asr).num_seconds() as f64 / (maghrib - asr).num_seconds() as f64;
        Mood { name: "golden".into(), tint: "#F2A65A".into(), tint_opacity: 0.06 + 0.2 * progress, scrim_delta: 0.0 }
    } else if now < isha {
        Mood { name: "dusk".into(), tint: "#6B4E9B".into(), tint_opacity: 0.24, scrim_delta: 0.1 }
    } else {
        let progress = (now - isha).num_seconds() as f64 / (night - isha).num_seconds() as f64;
        Mood {
            name: "evening".into(),
            tint: "#2A2350".into(),
            tint_opacity: 0.24 + 0.06 * progress,
            scrim_delta: 0.1 + 0.1 * progress,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::prayer::{default_iqamah, prayers_from, PrayerDay};
    use chrono::{Datelike, TimeZone, Utc};
    use std::collections::BTreeMap;

    fn at(h: u32, m: u32, base: DateTime<Utc>) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(base.year(), base.month(), base.day(), h, m, 0).unwrap()
    }

    fn friday_prayers() -> Vec<Prayer> {
        let day = PrayerDay {
            date: "".into(),
            timings: [
                ("Fajr", "04:34"), ("Dhuhr", "11:56 (WITA)"), ("Asr", "15:13"),
                ("Maghrib", "18:00"), ("Isha", "19:10"),
            ].iter().map(|(k, v)| (k.to_string(), v.to_string())).collect::<BTreeMap<_, _>>(),
        };
        // 2026-10-23, a Friday.
        let friday = Utc.with_ymd_and_hms(2026, 10, 23, 0, 0, 0).unwrap();
        prayers_from(&day, friday, &default_iqamah())
    }

    #[test]
    fn follows_the_day_like_swift() {
        let fri = friday_prayers();
        let friday = Utc.with_ymd_and_hms(2026, 10, 23, 0, 0, 0).unwrap();
        assert_eq!(mood_at(at(3, 0, friday), &fri).name, "night");
        assert_eq!(mood_at(at(5, 0, friday), &fri).name, "dawn");
        assert_eq!(mood_at(at(10, 0, friday), &fri).name, "day");
        let early = mood_at(at(15, 30, friday), &fri);
        let late = mood_at(at(17, 45, friday), &fri);
        assert_eq!(early.name, "golden");
        assert!(late.tint_opacity > early.tint_opacity); // warmer toward Maghrib
        assert_eq!(mood_at(at(18, 30, friday), &fri).name, "dusk");
        assert_eq!(mood_at(at(23, 0, friday), &fri).name, "night");
    }
}
