//! Port of Services/L10n.swift — the minimal ID/EN string switch.

pub fn tr<'a>(lang: &str, id: &'a str, en: &'a str) -> &'a str {
    if lang == "id" {
        id
    } else {
        en
    }
}

pub fn greeting(date_hour: u32, name: &str, lang: &str) -> String {
    let suffix = if name.is_empty() { String::new() } else { format!(", {name}") };
    if lang == "id" {
        match date_hour {
            4..=10 => format!("Selamat Pagi{suffix}"),
            11..=14 => format!("Selamat Siang{suffix}"),
            15..=17 => format!("Selamat Sore{suffix}"),
            _ => format!("Selamat Malam{suffix}"),
        }
    } else {
        match date_hour {
            4..=11 => format!("Good Morning{suffix}"),
            12..=17 => format!("Good Afternoon{suffix}"),
            _ => format!("Good Evening{suffix}"),
        }
    }
}

pub fn days_left(n: i64, lang: &str) -> String {
    match (lang, n) {
        ("id", 0) => "Hari ini!".into(),
        ("id", 1) => "Besok".into(),
        ("id", _) => format!("{n} hari lagi"),
        (_, 0) => "Today!".into(),
        (_, 1) => "Tomorrow".into(),
        (_, _) => format!("{n} days left"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_swift_strings() {
        assert_eq!(greeting(9, "", "id"), "Selamat Pagi");
        assert_eq!(greeting(13, "Ghani", "id"), "Selamat Siang, Ghani");
        assert_eq!(greeting(20, "", "en"), "Good Evening");
        assert_eq!(days_left(0, "id"), "Hari ini!");
        assert_eq!(days_left(3, "en"), "3 days left");
    }
}
