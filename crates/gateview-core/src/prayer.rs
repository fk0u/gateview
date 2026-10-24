//! Port of PrayerTimeService.swift (+ PrayerTimeModel.swift). Behaviour must stay
//! identical: same Friday ("Jumat") rule, same iqamah defaults, same phase logic.

use chrono::{DateTime, Datelike, Duration, NaiveDate, TimeZone, Timelike, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// (Aladhan key, Indonesian display label).
pub const SCHEDULE: [(&str, &str); 5] = [
    ("Fajr", "Subuh"),
    ("Dhuhr", "Dzuhur"),
    ("Asr", "Ashar"),
    ("Maghrib", "Maghrib"),
    ("Isha", "Isya"),
];

/// Default iqamah minutes, mirroring `Theme().iqamah`.
pub const DEFAULT_IQAMAH: [(&str, i64); 5] = [
    ("Fajr", 10),
    ("Dhuhr", 10),
    ("Asr", 10),
    ("Maghrib", 7),
    ("Isha", 10),
];

pub fn default_iqamah() -> BTreeMap<String, i64> {
    DEFAULT_IQAMAH.iter().map(|(k, v)| (k.to_string(), *v)).collect()
}

/// One day's raw timings ("HH:mm", possibly with a "(WITA)" suffix), as cached/stored.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PrayerDay {
    /// dd-MM-yyyy, local — same format as the Swift app's cache key.
    pub date: String,
    pub timings: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Prayer {
    pub name: String,
    /// Adzan.
    pub time: DateTime<Utc>,
    /// Iqamah; `None` for Jumat (khutbah comes first).
    pub iqamah: Option<DateTime<Utc>>,
    pub is_jumat: bool,
    pub key: String,
}

impl Prayer {
    /// When the congregation is roughly over.
    pub fn end(&self) -> DateTime<Utc> {
        let start = self.iqamah.unwrap_or(self.time);
        start + Duration::minutes(if self.is_jumat { 45 } else { 10 })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum PrayerPhase {
    /// Counting down to adzan.
    Upcoming(Prayer),
    /// Adzan done, counting down to iqamah.
    Iqamah(Prayer),
    /// Sholat / khutbah in progress.
    Ongoing(Prayer),
}

/// "HH:mm[: extra]" → same wall-clock time on `date` (local calendar semantics of the Swift app).
pub fn time_on(raw: &str, date: DateTime<Utc>) -> Option<DateTime<Utc>> {
    let hhmm = raw.get(0..5)?;
    let (h, m) = hhmm.split_once(':')?;
    let h: u32 = h.parse().ok()?;
    let m: u32 = m.parse().ok()?;
    if h > 23 || m > 59 {
        return None;
    }
    let local = local_date(date);
    Some(local
        .with_hour(h)?
        .with_minute(m)?
        .with_second(0)?
        .with_nanosecond(0)?)
}

/// The Swift app works in the Mac's local calendar. The Rust core keeps the same
/// contract: callers hand in a `DateTime<Utc>` that was built from local fields.
/// Here we interpret `date` as already-local wall clock stored in UTC fields —
/// matching how the Swift tests construct dates (bySettingHour of a local date).
fn local_date(date: DateTime<Utc>) -> DateTime<Utc> {
    date
}

/// "dd-MM-yyyy" → date at midnight (UTC fields = local wall clock, see `time_on`).
pub fn date_from_key(key: &str) -> Option<DateTime<Utc>> {
    let mut p = key.split('-');
    let d: u32 = p.next()?.parse().ok()?;
    let m: u32 = p.next()?.parse().ok()?;
    let y: i32 = p.next()?.parse().ok()?;
    Some(Utc.from_utc_datetime(&NaiveDate::from_ymd_opt(y, m, d)?.and_hms_opt(0, 0, 0)?))
}

fn iqamah_for(iqamah: &BTreeMap<String, i64>, key: &str) -> i64 {
    iqamah.get(key).copied().unwrap_or(10)
}

/// The five prayers of `date` from one day's raw timings. On Friday, Dhuhr becomes "Jumat" with no iqamah.
pub fn prayers_from(day: &PrayerDay, date: DateTime<Utc>, iqamah: &BTreeMap<String, i64>) -> Vec<Prayer> {
    // chrono Weekday: Mon..Sun; Friday is the Jumat case (Swift weekday 6).
    let friday = date.weekday() == chrono::Weekday::Fri;
    SCHEDULE.iter().filter_map(|(key, label)| {
        let raw = day.timings.get(*key)?;
        let time = time_on(raw, date)?;
        if friday && *key == "Dhuhr" {
            return Some(Prayer {
                name: "Jumat".into(),
                time,
                iqamah: None,
                is_jumat: true,
                key: key.to_string(),
            });
        }
        Some(Prayer {
            name: label.to_string(),
            time,
            iqamah: Some(time + Duration::minutes(iqamah_for(iqamah, key))),
            is_jumat: false,
            key: key.to_string(),
        })
    }).collect()
}

pub fn phase_at(now: DateTime<Utc>, prayers: &[Prayer]) -> Option<PrayerPhase> {
    if let Some(current) = prayers.iter().rev().find(|p| p.time <= now && now < p.end()) {
        if let Some(iqamah) = current.iqamah {
            if now < iqamah {
                return Some(PrayerPhase::Iqamah(current.clone()));
            }
        }
        return Some(PrayerPhase::Ongoing(current.clone()));
    }
    next_after(now, prayers).map(PrayerPhase::Upcoming)
}

pub fn next_after(now: DateTime<Utc>, prayers: &[Prayer]) -> Option<Prayer> {
    if let Some(upcoming) = prayers.iter().find(|p| p.time > now) {
        return Some(upcoming.clone());
    }
    // After Isya, tomorrow's Subuh ≈ today's + 1 day (off by ~1 min); the real value loads at midnight.
    let fajr = prayers.first()?;
    Some(Prayer {
        name: fajr.name.clone(),
        time: fajr.time + Duration::days(1),
        iqamah: fajr.iqamah.map(|t| t + Duration::days(1)),
        is_jumat: false,
        key: fajr.key.clone(),
    })
}

/// "HH:MM:SS" when an hour or more remains, else "MM:SS" — ceil to the second, like the Swift app.
pub fn countdown_to(target: DateTime<Utc>, now: DateTime<Utc>) -> String {
    let s = (target - now).num_seconds().max(0) as u64;
    if s >= 3600 {
        format!("{:02}:{:02}:{:02}", s / 3600, s % 3600 / 60, s % 60)
    } else {
        format!("{:02}:{:02}", s / 60, s % 60)
    }
}

/// "dd-MM-yyyy" of the given date.
pub fn day_key(date: DateTime<Utc>) -> String {
    format!("{:02}-{:02}-{:04}", date.day(), date.month(), date.year())
}

/// Aladhan `timingsByCity` / `calendarByCity` response subset.
#[derive(Debug, Deserialize)]
struct AladhanResponse {
    data: AladhanPayload,
}

#[derive(Debug, Deserialize)]
struct AladhanPayload {
    timings: BTreeMap<String, String>,
}

/// Fetch today's timings (mirrors `todayTimings`; caching stays with the shell app).
pub fn fetch_today(city: &str, country: &str, method: u32) -> Result<PrayerDay, String> {
    let body = ureq::get("https://api.aladhan.com/v1/timingsByCity")
        .query("city", city)
        .query("country", country)
        .query("method", &method.to_string())
        .call()
        .map_err(|e| e.to_string())?;
    let r: AladhanResponse = body.into_json().map_err(|e| e.to_string())?;
    Ok(PrayerDay {
        date: day_key(Utc::now()),
        timings: r.data.timings,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{Datelike, TimeZone};

    fn at(h: u32, m: u32, base: DateTime<Utc>) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(base.year(), base.month(), base.day(), h, m, 0).unwrap()
    }

    fn sample_day() -> PrayerDay {
        PrayerDay {
            date: "".into(),
            timings: [
                ("Fajr", "04:34"),
                ("Dhuhr", "11:56 (WITA)"),
                ("Asr", "15:13"),
                ("Maghrib", "18:00"),
                ("Isha", "19:10"),
            ].iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
        }
    }

    // 2026-10-23 is a Friday.
    fn friday() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 10, 23, 0, 0, 0).unwrap()
    }

    #[test]
    fn jumat_replaces_dhuhr() {
        let p = prayers_from(&sample_day(), friday(), &default_iqamah());
        assert_eq!(p[1].name, "Jumat");
        assert_eq!(p[1].iqamah, None);
        assert!(p[1].is_jumat);
        let thursday = friday() - Duration::days(1);
        assert_eq!(prayers_from(&sample_day(), thursday, &default_iqamah())[1].name, "Dzuhur");
    }

    #[test]
    fn phases_match_swift() {
        let fri = prayers_from(&sample_day(), friday(), &default_iqamah());
        match phase_at(at(11, 0, friday()), &fri) {
            Some(PrayerPhase::Upcoming(p)) => assert!(p.is_jumat),
            other => panic!("before jumat: {other:?}"),
        }
        assert!(matches!(phase_at(at(12, 30, friday()), &fri), Some(PrayerPhase::Ongoing(p)) if p.is_jumat));
        assert!(matches!(phase_at(at(15, 18, friday()), &fri), Some(PrayerPhase::Iqamah(p)) if p.name == "Ashar"));
        assert!(matches!(phase_at(at(15, 25, friday()), &fri), Some(PrayerPhase::Ongoing(_))));
        assert!(matches!(phase_at(at(15, 40, friday()), &fri), Some(PrayerPhase::Upcoming(p)) if p.name == "Maghrib"));
        match phase_at(at(22, 0, friday()), &fri) {
            Some(PrayerPhase::Upcoming(p)) => {
                assert_eq!(p.name, "Subuh");
                assert!(p.time > at(22, 0, friday()));
            }
            other => panic!("tomorrow subuh: {other:?}"),
        }
    }

    #[test]
    fn countdown_format() {
        assert_eq!(countdown_to(at(15, 23, friday()), at(15, 18, friday())), "05:00");
        assert_eq!(countdown_to(at(16, 23, friday()), at(15, 18, friday())), "01:05:00");
    }

    #[test]
    fn custom_iqamah_applies() {
        let mut iq = default_iqamah();
        iq.insert("Maghrib".into(), 3);
        let thursday = friday() - Duration::days(1);
        let p = prayers_from(&sample_day(), thursday, &iq);
        assert_eq!(p[3].iqamah, Some(p[3].time + Duration::seconds(180)));
    }

    #[test]
    fn per_prayer_keys_parse() {
        assert_eq!(day_key(friday()), "23-10-2026");
        assert_eq!(date_from_key("23-10-2026"), Some(friday()));
        assert_eq!(time_on("garbage", friday()), None);
    }
}
