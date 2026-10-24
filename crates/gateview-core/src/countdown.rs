//! Port of Models/CountdownModel.swift.

use chrono::{DateTime, NaiveDate, TimeZone, Utc};

/// One "days until" entry, declared in theme.json:
/// `"countdowns": [{ "title": "Lebaran", "date": "2027-03-10", "symbol": "moon.stars" }]`
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Countdown {
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub date: String, // yyyy-MM-dd
    #[serde(default = "default_symbol")]
    pub symbol: String,
    /// Not (de)serialized and excluded from equality — a random id must never
    /// rewrite theme.json (the Swift port learned this the hard way).
    #[serde(skip)]
    pub uid: String,
}

fn default_symbol() -> String {
    "sparkles".into()
}

impl PartialEq for Countdown {
    fn eq(&self, other: &Self) -> bool {
        self.title == other.title && self.date == other.date && self.symbol == other.symbol
    }
}

impl Countdown {
    pub fn new(title: &str, date: &str) -> Self {
        Self { title: title.into(), date: date.into(), symbol: default_symbol(), uid: new_uid() }
    }

    pub fn target(&self) -> Option<DateTime<Utc>> {
        parse_date(&self.date)
    }

    /// Whole days from `now` (0 = today, negative once passed) — start-of-day difference, like Swift.
    pub fn days_until(target: DateTime<Utc>, now: DateTime<Utc>) -> i64 {
        (target.date_naive() - now.date_naive()).num_days()
    }
}

fn new_uid() -> String {
    // No uuid crate needed: uniqueness within one process's store lifetime is enough.
    use std::time::{SystemTime, UNIX_EPOCH};
    let n = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.subsec_nanos()).unwrap_or(0);
    format!("c{n}")
}

pub fn parse_date(raw: &str) -> Option<DateTime<Utc>> {
    if raw.len() != 10 {
        return None;
    }
    let d = NaiveDate::parse_from_str(raw, "%Y-%m-%d").ok()?;
    Some(Utc.from_utc_datetime(&d.and_hms_opt(0, 0, 0)?))
}

/// Declared countdowns still ahead (today counts), soonest first.
pub fn upcoming(items: &[Countdown], now: DateTime<Utc>) -> Vec<Countdown> {
    let mut keyed: Vec<(Countdown, i64)> = items
        .iter()
        .filter_map(|c| {
            let target = c.target()?;
            let days = Countdown::days_until(target, now);
            (days >= 0).then(|| (c.clone(), days))
        })
        .collect();
    keyed.sort_by_key(|(_, days)| *days);
    keyed.into_iter().map(|(c, _)| c).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn at(h: u32, m: u32, y: i32, mo: u32, d: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(y, mo, d, h, m, 0).unwrap()
    }

    #[test]
    fn whole_day_difference() {
        // 2026-10-23 is the Swift test's Friday.
        assert_eq!(Countdown::days_until(at(0, 0, 2026, 10, 23), at(23, 0, 2026, 10, 22)), 1);
        assert_eq!(Countdown::days_until(at(23, 0, 2026, 10, 23), at(8, 0, 2026, 10, 23)), 0);
    }

    #[test]
    fn upcoming_sorts_and_skips() {
        let lebaran = Countdown::new("Lebaran", "2027-03-10");
        let trip = Countdown::new("Trip", "2026-10-25");
        let bad = Countdown::new("x", "oops");
        assert!(lebaran.target().is_some() && bad.target().is_none());
        let got = upcoming(&[lebaran.clone(), trip.clone(), bad], at(0, 0, 2026, 10, 23));
        assert_eq!(got.iter().map(|c| c.title.as_str()).collect::<Vec<_>>(), ["Trip", "Lebaran"]);
        assert!(upcoming(&[Countdown::new("old", "2020-01-01")], at(0, 0, 2026, 10, 23)).is_empty());
    }

    #[test]
    fn uid_does_not_affect_equality() {
        assert_eq!(Countdown::new("a", "2027-03-10"), Countdown::new("a", "2027-03-10"));
    }
}
