//! Now Playing on Windows via the System Media Transport Controls (SMTC) —
//! the public WinRT API that every player (Spotify, browsers, foobar…) posts to.
//! Polling every few seconds keeps lifetimes simple; position advances locally
//! between polls, mirroring the macOS AppleScript fallback.

use crate::NowPlayingInfo;
use std::sync::mpsc::Sender;
use std::time::Duration;
use windows::Graphics::Imaging::BitmapDecoder;
use windows::Media::Control::{
    GlobalSystemMediaTransportControlsSessionManager, GlobalSystemMediaTransportControlsSessionPlaybackStatus,
};

/// Spawns a polling thread that sends the current track through `tx`.
/// The manager is created once (its session list is process-wide) and kept alive
/// for the lifetime of the thread.
pub fn spawn(tx: Sender<Option<NowPlayingInfo>>) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || {
        let manager = match GlobalSystemMediaTransportControlsSessionManager::RequestAsync() {
            Ok(op) => match op.get() {
                Ok(m) => m,
                Err(e) => {
                    eprintln!("SMTC RequestAsync failed: {e}");
                    return;
                }
            },
            Err(e) => {
                eprintln!("SMTC unavailable: {e}");
                return;
            }
        };

        let mut last_key = String::new();
        let mut last: Option<NowPlayingInfo> = None;
        loop {
            let info = poll_once(&manager, &mut last_key, &mut last);
            let _ = tx.send(info);
            std::thread::sleep(Duration::from_secs(3));
        }
    })
}

fn poll_once(
    manager: &GlobalSystemMediaTransportControlsSessionManager,
    last_key: &mut String,
    last: &mut Option<NowPlayingInfo>,
) -> Option<NowPlayingInfo> {
    let sessions = manager.GetSessions().ok()?;
    let count = sessions.Size().ok()?;
    let mut playing: Option<windows::Media::Control::GlobalSystemMediaTransportControlsSession> = None;
    let mut any: Option<windows::Media::Control::GlobalSystemMediaTransportControlsSession> = None;
    for i in 0..count {
        let Ok(session) = sessions.GetAt(i) else { continue };
        let is_playing = session
            .GetPlaybackInfo()
            .ok()
            .and_then(|p| p.PlaybackStatus().ok())
            .is_some_and(|s| s == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing);
        if any.is_none() {
            any = Some(session.clone());
        }
        if is_playing && playing.is_none() {
            playing = Some(session);
        }
    }
    let session = playing.or(any)?;

    let props = session.TryGetMediaPropertiesAsync().ok()?.get().ok()?;
    let title = props.Title().ok()?.to_string();
    if title.is_empty() {
        return None;
    }
    let artist = props.Artist().map(|s| s.to_string()).unwrap_or_default();
    let album = props.AlbumTitle().map(|s| s.to_string()).unwrap_or_default();
    let source = session.SourceAppUserModelId().map(|s| s.to_string()).unwrap_or_default();

    let playback = session.GetPlaybackInfo().ok();
    let is_playing = playback
        .as_ref()
        .and_then(|p| p.PlaybackStatus().ok())
        .is_some_and(|s| s == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing);
    let rate = playback
        .as_ref()
        .and_then(|p| p.PlaybackRate().ok())
        .and_then(|r| r.Value().ok())
        .unwrap_or(if is_playing { 1.0 } else { 0.0 });

    // Timeline: SMTC reports position; we anchor it at "now" and advance locally.
    let elapsed = session
        .GetTimelineProperties()
        .ok()
        .and_then(|t| t.Position().ok())
        .map(|p| p.Duration as f64 / 10_000_000.0)
        .unwrap_or(0.0);

    let key = format!("{source}|{title}|{artist}");
    let artwork_png = if key != *last_key {
        *last_key = key;
        thumbnail_png(&props.Thumbnail().ok()?)
    } else {
        last.as_ref().and_then(|t| t.artwork_png.clone())
    };

    Some(NowPlayingInfo {
        title,
        artist,
        album,
        artwork_png,
        is_playing,
        elapsed,
        timestamp: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0),
        rate,
        source,
    })
}

/// SMTC artwork arrives as a stream reference → decode to PNG bytes.
fn thumbnail_png(reference: &windows::Storage::Streams::IRandomAccessStreamReference) -> Option<Vec<u8>> {
    let stream = reference.OpenReadAsync().ok()?.get().ok()?;
    let decoder = BitmapDecoder::CreateAsync(&stream).ok()?.get().ok()?;
    let pixels = decoder.GetPixelDataAsync().ok()?.get().ok()?;
    let data: Vec<u8> = pixels.DetachPixelData().ok()?.to_vec();
    let (w, h) = (decoder.PixelWidth().ok()?, decoder.PixelHeight().ok()?);
    if data.len() < (w as usize) * (h as usize) * 4 {
        return None;
    }
    // BGRA → RGBA
    let mut rgba = data;
    for px in rgba.chunks_exact_mut(4) {
        px.swap(0, 2);
    }
    let img = image::RgbaImage::from_raw(w, h, rgba)?;
    let mut png = std::io::Cursor::new(Vec::new());
    image::DynamicImage::ImageRgba8(img)
        .write_to(&mut png, image::ImageFormat::Png)
        .ok()?;
    Some(png.into_inner())
}
