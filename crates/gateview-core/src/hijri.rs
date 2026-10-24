//! Port of PrayerTimeService.hijri — Umm al-Qura Hijri date, Indonesian month names.
//!
//! Apple's islamicUmmAlQura follows the official KACST tables; ICU4X's bundled
//! fallback computation drifts by a day on some month boundaries, so the exact
//! month-start table (AH 1441–1472, Gregorian 2020–2050) is exported from the
//! Swift app into `Tests/fixtures/umm-alqura-months.json` and consumed here.
//! Dates outside the table fall back to ICU (may differ by a day near boundaries).

use chrono::{Datelike, NaiveDate};
use icu_calendar::islamic::IslamicUmmAlQura;
use icu_calendar::{Date, Iso};

/// Indonesian (id_ID) names of the 12 Hijri months, golden-copied from the Swift app.
const MONTHS_ID: [&str; 12] = [
    "Muharam", "Safar", "Rabiulawal", "Rabiulakhir", "Jumadilawal", "Jumadilakhir",
    "Rajab", "Syakban", "Ramadan", "Syawal", "Zulkaidah", "Zulhijah",
];

const MONTH_TABLE: &str = include_str!("../../../Tests/fixtures/umm-alqura-months.json");

#[derive(serde::Deserialize)]
struct MonthStart {
    g: String, // first Gregorian day of the Hijri month, yyyy-MM-dd
    h: String, // "1448-12"
}

/// Hijri (year, month 1–12, day) for a Gregorian civil date.
pub fn hijri_parts(year: i32, month: u32, day: u32) -> Option<(i32, u32, u32)> {
    let date = NaiveDate::from_ymd_opt(year, month, day)?;
    let rows: Vec<MonthStart> = serde_json::from_str(MONTH_TABLE).ok()?;

    let mut best: Option<(NaiveDate, (i32, u32))> = None;
    for row in &rows {
        let start = NaiveDate::parse_from_str(&row.g, "%Y-%m-%d").ok()?;
        let h = parse_h(&row.h)?;
        if start > date {
            break; // sorted ascending
        }
        best = Some((start, h));
    }
    if let Some((start, (hy, hm))) = best {
        let day_in_month = (date - start).num_days() as u32 + 1;
        // Within the last known month we trust up to 30 days, else fall back.
        let is_last_row = date > rows.last().and_then(|r| NaiveDate::parse_from_str(&r.g, "%Y-%m-%d").ok()).unwrap_or(date);
        if day_in_month >= 1 && (!is_last_row || day_in_month <= 30) {
            return Some((hy, hm, day_in_month));
        }
    }

    // Outside the table (before 2020 / after 2050): ICU's computation.
    let iso: Date<Iso> = Date::try_new_iso_date(year, month as u8, day as u8).ok()?;
    let hijri = iso.to_calendar(IslamicUmmAlQura::new());
    Some((hijri.year().number, hijri.month().ordinal, hijri.day_of_month().0))
}

fn parse_h(raw: &str) -> Option<(i32, u32)> {
    let (y, m) = raw.split_once('-')?;
    Some((y.parse().ok()?, m.parse().ok()?))
}

/// "d MMMM yyyy H" — e.g. "12 Jumadilawal 1448 H".
pub fn hijri_id(year: i32, month: u32, day: u32) -> Option<String> {
    let (y, m, d) = hijri_parts(year, month, day)?;
    let name = *MONTHS_ID.get(m.checked_sub(1)? as usize)?;
    Some(format!("{d} {name} {y} H"))
}

/// Convenience for chrono dates.
pub fn hijri_id_from_ymd(date: impl Datelike) -> Option<String> {
    hijri_id(date.year(), date.month(), date.day())
}

/// Days in a Hijri month (for callers that need the month end; within the table).
pub fn days_in_month(year: i32, month: u32) -> Option<u32> {
    let rows: Vec<MonthStart> = serde_json::from_str(MONTH_TABLE).ok()?;
    let target = (year, month);
    let mut starts = rows.iter().filter_map(|r| Some((NaiveDate::parse_from_str(&r.g, "%Y-%m-%d").ok()?, parse_h(&r.h)?)));
    while let Some((start, h)) = starts.next() {
        if h == target {
            return Some(starts.next().map_or(30, |(next, _)| (next - start).num_days() as u32));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_swift_golden() {
        // Printed by Tests/golden.swift (Calendar islamicUmmAlQura, id_ID).
        assert_eq!(hijri_id(2026, 10, 23).as_deref(), Some("12 Jumadilawal 1448 H"));
        assert_eq!(hijri_id(2026, 3, 20).as_deref(), Some("1 Syawal 1447 H"));
        assert_eq!(hijri_id(2025, 2, 28).as_deref(), Some("29 Syakban 1446 H"));
        assert_eq!(hijri_id(2027, 1, 1).as_deref(), Some("23 Rajab 1448 H"));
        assert_eq!(hijri_id(2026, 6, 17).as_deref(), Some("2 Muharam 1448 H"));
    }

    #[test]
    fn month_lengths_exist() {
        // Ramadan 1447 began 2026-02-19; its length is 29 or 30 days.
        let len = days_in_month(1447, 9).unwrap_or(0);
        assert!(len == 29 || len == 30);
    }
}
