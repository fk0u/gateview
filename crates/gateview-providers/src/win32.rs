//! Windows shell helpers: fullscreen detection and cursor position, both needed
//! for the desktop-overlay behaviour (auto-hide + click-through regions).

use windows::Win32::Foundation::{BOOL, POINT, RECT};
use windows::Win32::Graphics::Gdi::{
    GetMonitorInfoW, MonitorFromWindow, MONITORINFO, MONITOR_DEFAULTTONEAREST,
};
use windows::Win32::UI::WindowsAndMessaging::{GetCursorPos, GetForegroundWindow, GetWindowRect};

/// True when the foreground window exactly covers a monitor — a fullscreen app or game.
pub fn frontmost_is_fullscreen() -> bool {
    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.is_invalid() {
            return false;
        }
        let mut rect = RECT::default();
        if GetWindowRect(hwnd, &mut rect).is_err() {
            return false;
        }
        let mut info = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        let monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
        if !GetMonitorInfoW(monitor, &mut info).as_bool() {
            return false;
        }
        rect == info.rcMonitor
    }
}

/// Cursor position in physical screen pixels; None when unavailable.
pub fn cursor_pos() -> Option<(i32, i32)> {
    let mut p = POINT::default();
    unsafe {
        if GetCursorPos(&mut p).is_ok() {
            Some((p.x, p.y))
        } else {
            None
        }
    }
}

/// Suppress the unused-BOOL lint on non-Windows builds of this module's signature surface.
#[allow(dead_code)]
fn _assert_bool(b: BOOL) -> bool {
    b.as_bool()
}
