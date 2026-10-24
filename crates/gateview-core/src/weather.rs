//! Port of WeatherService.swift (forecast + air quality parsing, WMO labels).

use chrono::{DateTime, Duration, TimeZone, Utc};
use serde::Deserialize;

#[derive(Debug, Clone, PartialEq)]
pub struct Hour {
    pub time: DateTime<Utc>,
    pub temperature: i64,
    pub symbol: String,
    pub rain_chance: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Day {
    pub date: DateTime<Utc>,
    pub min: i64,
    pub max: i64,
    pub symbol: String,
    pub rain_chance: i64,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Weather {
    pub temperature: i64,
    pub code: i64,
    pub symbol: String,
    pub label: String,
    pub feels_like: i64,
    pub humidity: i64,
    pub wind: i64, // km/h
    pub hourly: Vec<Hour>, // next 12 h
    pub daily: Vec<Day>,   // next 5 days
    pub aqi: Option<i64>,  // US AQI; None when the air-quality endpoint failed
    pub pm25: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct Response {
    utc_offset_seconds: i64,
    current: Current,
    hourly: Hourly,
    daily: Daily,
}

#[derive(Debug, Deserialize)]
struct Current {
    temperature_2m: f64,
    apparent_temperature: f64,
    wind_speed_10m: f64,
    relative_humidity_2m: i64,
    weather_code: i64,
    is_day: i64,
}

#[derive(Debug, Deserialize)]
struct Hourly {
    time: Vec<String>,
    temperature_2m: Vec<f64>,
    weather_code: Vec<i64>,
    precipitation_probability: Vec<Option<i64>>,
    is_day: Vec<i64>,
}

#[derive(Debug, Deserialize)]
struct Daily {
    time: Vec<String>,
    weather_code: Vec<i64>,
    temperature_2m_max: Vec<f64>,
    temperature_2m_min: Vec<f64>,
    precipitation_probability_max: Vec<Option<i64>>,
}

/// Parse the Open-Meteo forecast payload (pure, so tests can run offline).
pub fn parse(data: &[u8], now: DateTime<Utc>) -> Result<Weather, String> {
    let r: Response = serde_json::from_slice(data).map_err(|e| e.to_string())?;
    // Times come as local wall clock; the payload carries the location's fixed UTC offset.
    let tz = chrono::FixedOffset::east_opt(r.utc_offset_seconds as i32).ok_or("bad offset")?;
    let f = |raw: &str, has_time: bool| -> Option<DateTime<Utc>> {
        let naive = if has_time {
            chrono::NaiveDateTime::parse_from_str(raw, "%Y-%m-%dT%H:%M").ok()?
        } else {
            chrono::NaiveDate::parse_from_str(raw, "%Y-%m-%d").ok()?.and_hms_opt(0, 0, 0)?
        };
        Some(tz.from_local_datetime(&naive).single()?.with_timezone(&Utc))
    };

    let mut hours: Vec<Hour> = r.hourly.time.iter().enumerate().filter_map(|(i, raw)| {
        let t = f(raw, true)?;
        if t <= now - Duration::hours(1) {
            return None;
        }
        Some(Hour {
            time: t,
            temperature: r.hourly.temperature_2m.get(i)?.round() as i64,
            symbol: describe(*r.hourly.weather_code.get(i)?, *r.hourly.is_day.get(i)? == 1, "id").0.to_string(),
            rain_chance: r.hourly.precipitation_probability.get(i).copied().flatten().unwrap_or(0),
        })
    }).collect();
    hours.truncate(12);

    let mut days: Vec<Day> = r.daily.time.iter().enumerate().skip(1).filter_map(|(i, raw)| {
        Some(Day {
            date: f(raw, false)?,
            min: r.daily.temperature_2m_min.get(i)?.round() as i64,
            max: r.daily.temperature_2m_max.get(i)?.round() as i64,
            symbol: describe(*r.daily.weather_code.get(i)?, true, "id").0.to_string(),
            rain_chance: r.daily.precipitation_probability_max.get(i).copied().flatten().unwrap_or(0),
        })
    }).collect();
    days.truncate(5);

    let c = &r.current;
    let (symbol, label) = describe(c.weather_code, c.is_day == 1, "id");
    Ok(Weather {
        temperature: c.temperature_2m.round() as i64,
        code: c.weather_code,
        symbol: symbol.to_string(),
        label: label.to_string(),
        feels_like: c.apparent_temperature.round() as i64,
        humidity: c.relative_humidity_2m,
        wind: c.wind_speed_10m.round() as i64,
        hourly: hours,
        daily: days,
        ..Default::default()
    })
}

/// US AQI + PM2.5 (separate Open-Meteo endpoint, also keyless). `None` on any failure.
pub fn air_quality(latitude: f64, longitude: f64) -> Option<(i64, f64)> {
    let body = ureq::get("https://air-quality-api.open-meteo.com/v1/air-quality")
        .query("latitude", &latitude.to_string())
        .query("longitude", &longitude.to_string())
        .query("current", "us_aqi,pm2_5")
        .query("timezone", "auto")
        .call()
        .ok()?;
    let mut reader = body.into_reader();
    let mut bytes = Vec::new();
    std::io::Read::read_to_end(&mut reader, &mut bytes).ok()?;
    parse_air_quality(&bytes).ok()
}

pub fn parse_air_quality(data: &[u8]) -> Result<(i64, f64), String> {
    #[derive(Deserialize)]
    struct Response {
        current: AqCurrent,
    }
    #[derive(Deserialize)]
    struct AqCurrent {
        us_aqi: i64,
        pm2_5: f64,
    }
    let r: Response = serde_json::from_slice(data).map_err(|e| e.to_string())?;
    Ok((r.current.us_aqi, r.current.pm2_5))
}

/// US AQI band → (hex colour, Indonesian label).
pub fn air_quality_band(aqi: i64) -> (&'static str, &'static str) {
    match aqi {
        ..50 => ("#34C759", "Baik"),
        51..=100 => ("#FFCC00", "Sedang"),
        101..=150 => ("#FF9500", "Tidak Sehat (Sensitif)"),
        151..=200 => ("#FF3B30", "Tidak Sehat"),
        201..=300 => ("#AF52DE", "Sangat Tidak Sehat"),
        _ => ("#8E3B3B", "Berbahaya"),
    }
}

/// WMO weather code → (SF Symbol, short label; Indonesian by default).
pub fn describe(code: i64, is_day: bool, lang: &str) -> (&'static str, &'static str) {
    use crate::l10n::tr;
    match code {
        0 => (if is_day { "sun.max.fill" } else { "moon.stars.fill" },
              tr(lang, "Cerah", if is_day { "Clear" } else { "Clear Night" })),
        1 | 2 => (if is_day { "cloud.sun.fill" } else { "cloud.moon.fill" },
                  tr(lang, "Cerah Berawan", "Partly Cloudy")),
        3 => ("cloud.fill", tr(lang, "Berawan", "Cloudy")),
        45 | 48 => ("cloud.fog.fill", tr(lang, "Berkabut", "Foggy")),
        51..=57 => ("cloud.drizzle.fill", tr(lang, "Gerimis", "Drizzle")),
        61..=67 | 80..=82 => ("cloud.rain.fill", tr(lang, "Hujan", "Rain")),
        71..=77 | 85 | 86 => ("cloud.snow.fill", tr(lang, "Salju", "Snow")),
        95..=99 => ("cloud.bolt.rain.fill", tr(lang, "Badai Petir", "Thunderstorm")),
        _ => ("cloud.fill", tr(lang, "Berawan", "Cloudy")),
    }
}

/// City search for settings (Open-Meteo geocoding, no key).
#[derive(Debug, Deserialize, Clone)]
pub struct Place {
    pub name: String,
    pub latitude: f64,
    pub longitude: f64,
    pub country: Option<String>,
    pub admin1: Option<String>,
}

pub fn search_places(query: &str) -> Result<Vec<Place>, String> {
    let body = ureq::get("https://geocoding-api.open-meteo.com/v1/search")
        .query("name", query)
        .query("count", "6")
        .query("language", "id")
        .call()
        .map_err(|e| e.to_string())?;
    #[derive(Deserialize)]
    struct Response {
        results: Option<Vec<Place>>,
    }
    let r: Response = body.into_json().map_err(|e| e.to_string())?;
    Ok(r.results.unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wmo_codes_match_swift() {
        assert_eq!(describe(0, false, "id").0, "moon.stars.fill");
        assert_eq!(describe(63, true, "id").1, "Hujan");
        assert_eq!(describe(63, true, "en").1, "Rain");
        assert_eq!(describe(96, true, "id").1, "Badai Petir");
        assert_eq!(describe(0, false, "id").1, "Cerah"); // default stays Indonesian
    }

    #[test]
    fn aq_parsing_and_bands() {
        let (aqi, pm25) = parse_air_quality(br#"{"current":{"us_aqi":78,"pm2_5":25.4}}"#).unwrap();
        assert_eq!((aqi, pm25), (78, 25.4));
        assert_eq!(air_quality_band(42).1, "Baik");
        assert_eq!(air_quality_band(190).1, "Tidak Sehat");
    }

    #[test]
    fn forecast_parsing_matches_swift() {
        let sample = br#"{"utc_offset_seconds":28800,"current":{"temperature_2m":29.6,"apparent_temperature":33.1,"wind_speed_10m":7.2,"relative_humidity_2m":80,"weather_code":63,"is_day":1},"hourly":{"time":["2026-10-23T15:00","2026-10-23T16:00"],"temperature_2m":[30,29],"weather_code":[3,61],"precipitation_probability":[20,null],"is_day":[1,1]},"daily":{"time":["2026-10-23","2026-10-24"],"weather_code":[63,1],"temperature_2m_max":[31.4,32],"temperature_2m_min":[24.2,24.8],"precipitation_probability_max":[80,null]}}"#;
        // 2026-10-23 14:00 +08:00 == 06:00 UTC
        let now = Utc.with_ymd_and_hms(2026, 10, 23, 6, 0, 0).unwrap();
        let w = parse(sample, now).unwrap();
        assert_eq!(w.temperature, 30);
        assert_eq!(w.feels_like, 33);
        assert_eq!(w.label, "Hujan");
        assert_eq!(w.code, 63);
        assert_eq!(w.hourly.len(), 2);
        assert_eq!(w.hourly[1].rain_chance, 0);
        assert_eq!(w.daily.len(), 1);
        assert_eq!(w.daily[0].max, 32);
    }
}
