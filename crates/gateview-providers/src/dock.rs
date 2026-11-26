//! Window enumeration, focus/minimize/close, and live window preview capture
//! for the macOS-style Dock on Windows (with clean stubs on other targets).

use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DockWindow {
    pub hwnd: isize,
    pub pid: u32,
    pub title: String,
    pub process_name: String,
    pub is_active: bool,
    pub is_minimized: bool,
}

/// Encodes arbitrary bytes as standard base64 (avoids adding an external crate).
pub fn base64_encode(input: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity((input.len() + 2) / 3 * 4);
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as usize;
        let b1 = if chunk.len() > 1 { chunk[1] as usize } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as usize } else { 0 };
        out.push(TABLE[b0 >> 2] as char);
        out.push(TABLE[((b0 & 0x03) << 4) | (b1 >> 4)] as char);
        out.push(if chunk.len() > 1 { TABLE[((b1 & 0x0F) << 2) | (b2 >> 6)] as char } else { '=' });
        out.push(if chunk.len() > 2 { TABLE[b2 & 0x3F] as char } else { '=' });
    }
    out
}

/// Computes target thumbnail dimensions preserving aspect ratio within `max_w x max_h`.
pub fn fit_preview_size(w: i32, h: i32, max_w: u32, max_h: u32) -> Option<(u32, u32)> {
    if w <= 0 || h <= 0 || max_w == 0 || max_h == 0 {
        return None;
    }
    let scale = (max_w as f64 / w as f64).min(max_h as f64 / h as f64).min(1.0);
    let tw = ((w as f64 * scale).round() as u32).max(1);
    let th = ((h as f64 * scale).round() as u32).max(1);
    Some((tw, th))
}

#[cfg(windows)]
mod imp {
    use super::{base64_encode, fit_preview_size, DockWindow};
    use image::{ImageBuffer, ImageFormat, Rgba};
    use std::ffi::c_void;
    use std::io::Cursor;
    use windows::Win32::Foundation::{BOOL, HWND, LPARAM, RECT, WPARAM};
    use windows::Win32::Graphics::Gdi::{
        BitBlt, CreateCompatibleBitmap, CreateCompatibleDC, DeleteDC, DeleteObject, GetDIBits,
        GetWindowDC, ReleaseDC, SelectObject, BITMAPINFO, BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS,
        SRCCOPY,
    };
    use windows::Win32::UI::WindowsAndMessaging::{
        EnumWindows, GetForegroundWindow, GetWindowLongW, GetWindowRect, GetWindowTextLengthW,
        GetWindowTextW, GetWindowThreadProcessId, IsIconic, IsWindowVisible, PostMessageW,
        SetForegroundWindow, ShowWindow, GWL_EXSTYLE, SW_MINIMIZE, SW_RESTORE, WM_CLOSE,
        WS_EX_TOOLWINDOW,
    };

    struct EnumCtx {
        fg: HWND,
        out: Vec<DockWindow>,
    }

    unsafe extern "system" fn enum_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
        let ctx = &mut *(lparam.0 as *mut EnumCtx);
        if !IsWindowVisible(hwnd).as_bool() {
            return BOOL(1);
        }
        let ex_style = GetWindowLongW(hwnd, GWL_EXSTYLE) as u32;
        if (ex_style & WS_EX_TOOLWINDOW.0) != 0 {
            return BOOL(1);
        }
        let len = GetWindowTextLengthW(hwnd);
        if len <= 0 {
            return BOOL(1);
        }
        let mut buf = vec![0u16; (len + 1) as usize];
        let copied = GetWindowTextW(hwnd, &mut buf);
        if copied <= 0 {
            return BOOL(1);
        }
        let title = String::from_utf16_lossy(&buf[..copied as usize]).trim().to_string();
        if title.is_empty() || title == "GateView" || title == "Program Manager" {
            return BOOL(1);
        }
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        let process_name = format!("app-{}", pid);
        ctx.out.push(DockWindow {
            hwnd: hwnd.0 as isize,
            pid,
            title,
            process_name,
            is_active: hwnd == ctx.fg,
            is_minimized: IsIconic(hwnd).as_bool(),
        });
        BOOL(1)
    }

    pub fn list_windows() -> Vec<DockWindow> {
        unsafe {
            let mut ctx = EnumCtx {
                fg: GetForegroundWindow(),
                out: Vec::with_capacity(24),
            };
            let _ = EnumWindows(Some(enum_proc), LPARAM(&mut ctx as *mut EnumCtx as isize));
            ctx.out
        }
    }

    pub fn focus_window(hwnd_raw: isize) {
        let hwnd = HWND(hwnd_raw as *mut c_void);
        unsafe {
            if IsIconic(hwnd).as_bool() {
                let _ = ShowWindow(hwnd, SW_RESTORE);
            }
            let _ = SetForegroundWindow(hwnd);
        }
    }

    pub fn minimize_window(hwnd_raw: isize) {
        let hwnd = HWND(hwnd_raw as *mut c_void);
        unsafe {
            let _ = ShowWindow(hwnd, SW_MINIMIZE);
        }
    }

    pub fn close_window(hwnd_raw: isize) {
        let hwnd = HWND(hwnd_raw as *mut c_void);
        unsafe {
            let _ = PostMessageW(hwnd, WM_CLOSE, WPARAM(0), LPARAM(0));
        }
    }

    pub fn quit_app(target_pid: u32) {
        unsafe extern "system" fn quit_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
            let wanted = lparam.0 as u32;
            let mut pid: u32 = 0;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            if pid == wanted && IsWindowVisible(hwnd).as_bool() {
                let _ = PostMessageW(hwnd, WM_CLOSE, WPARAM(0), LPARAM(0));
            }
            BOOL(1)
        }
        unsafe {
            let _ = EnumWindows(Some(quit_proc), LPARAM(target_pid as isize));
        }
    }

    /// Captures a live downscaled PNG data-URL preview of the target window.
    pub fn capture_preview_data_url(hwnd_raw: isize) -> Option<String> {
        let hwnd = HWND(hwnd_raw as *mut c_void);
        unsafe {
            if !IsWindowVisible(hwnd).as_bool() || IsIconic(hwnd).as_bool() {
                return None;
            }
            let mut rect = RECT::default();
            if GetWindowRect(hwnd, &mut rect).is_err() {
                return None;
            }
            let w = rect.right - rect.left;
            let h = rect.bottom - rect.top;
            let (tw, th) = fit_preview_size(w, h, 320, 200)?;

            let hdc_win = GetWindowDC(hwnd);
            if hdc_win.is_invalid() {
                return None;
            }
            let hdc_mem = CreateCompatibleDC(hdc_win);
            if hdc_mem.is_invalid() {
                ReleaseDC(hwnd, hdc_win);
                return None;
            }
            let hbm = CreateCompatibleBitmap(hdc_win, w, h);
            if hbm.is_invalid() {
                let _ = DeleteDC(hdc_mem);
                ReleaseDC(hwnd, hdc_win);
                return None;
            }
            let old = SelectObject(hdc_mem, hbm);
            let ok = BitBlt(hdc_mem, 0, 0, w, h, hdc_win, 0, 0, SRCCOPY).is_ok();
            let mut pixels = vec![0u8; (w * h * 4) as usize];
            let mut bmi = BITMAPINFO {
                bmiHeader: BITMAPINFOHEADER {
                    biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                    biWidth: w,
                    biHeight: -h, // top-down
                    biPlanes: 1,
                    biBitCount: 32,
                    biCompression: BI_RGB.0,
                    ..Default::default()
                },
                ..Default::default()
            };
            let lines = if ok {
                GetDIBits(hdc_mem, hbm, 0, h as u32, Some(pixels.as_mut_ptr() as *mut c_void), &mut bmi, DIB_RGB_COLORS)
            } else {
                0
            };
            SelectObject(hdc_mem, old);
            let _ = DeleteObject(hbm);
            let _ = DeleteDC(hdc_mem);
            ReleaseDC(hwnd, hdc_win);

            if lines == 0 {
                return None;
            }
            // BGRA -> RGBA
            for px in pixels.chunks_exact_mut(4) {
                px.swap(0, 2);
                px[3] = 255;
            }
            let img: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::from_raw(w as u32, h as u32, pixels)?;
            let thumb = image::imageops::resize(&img, tw, th, image::imageops::FilterType::Triangle);
            let mut png = Vec::new();
            thumb.write_to(&mut Cursor::new(&mut png), ImageFormat::Png).ok()?;
            Some(format!("data:image/png;base64,{}", base64_encode(&png)))
        }
    }
}

#[cfg(not(windows))]
mod imp {
    use super::DockWindow;
    pub fn list_windows() -> Vec<DockWindow> {
        Vec::new()
    }
    pub fn focus_window(_hwnd: isize) {}
    pub fn minimize_window(_hwnd: isize) {}
    pub fn close_window(_hwnd: isize) {}
    pub fn quit_app(_pid: u32) {}
    pub fn capture_preview_data_url(_hwnd: isize) -> Option<String> {
        None
    }
}

pub use imp::{capture_preview_data_url, close_window, focus_window, list_windows, minimize_window, quit_app};

#[cfg(test)]
mod tests {
    use super::{base64_encode, fit_preview_size};

    #[test]
    fn base64_matches_standard() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"GateView"), "R2F0ZVZpZXc=");
    }

    #[test]
    fn preview_size_preserves_aspect_and_clamps() {
        assert_eq!(fit_preview_size(1920, 1080, 320, 200), Some((320, 180)));
        assert_eq!(fit_preview_size(160, 100, 320, 200), Some((160, 100)));
        assert_eq!(fit_preview_size(0, 100, 320, 200), None);
    }
}
