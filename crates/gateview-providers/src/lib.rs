//! Platform service implementations for the Tauri shells (Windows, later Linux).
//! Windows-specific code is `cfg(windows)`; stubs keep other targets compiling.

pub mod stats;

#[cfg(windows)]
pub mod smtc;
#[cfg(windows)]
pub mod win32;

/// What a media provider reports — the Rust twin of the macOS `NowPlaying` struct.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct NowPlayingInfo {
    pub title: String,
    pub artist: String,
    pub album: String,
    /// PNG-encoded thumbnail, if the player exposes artwork.
    pub artwork_png: Option<Vec<u8>>,
    pub is_playing: bool,
    /// Reported elapsed at `timestamp`; advances at `rate` while playing.
    pub elapsed: f64,
    /// Unix seconds when `elapsed` was reported (SMTC has no track duration,
    /// so the UI only advances the bar while `duration > 0`).
    pub timestamp: f64,
    pub rate: f64,
    /// Which player supplied it (e.g. "Spotify.exe", "chrome.exe").
    pub source: String,
}

impl NowPlayingInfo {
    /// Current position, advancing locally between polls (same math as the macOS app).
    pub fn position_at(&self, now_unix: f64) -> f64 {
        let delta = (now_unix - self.timestamp).max(0.0);
        let p = self.elapsed + if self.is_playing { delta * self.rate.max(1.0) } else { 0.0 };
        p.max(0.0)
    }
}
