// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck Engine — Active Window Tracker
// ─────────────────────────────────────────────────────────────────────────────
// Returns the bundle ID (macOS) or executable stem (Windows) of the currently
// focused foreground application.
//
// macOS:   NSWorkspace.sharedWorkspace.frontmostApplication?.bundleIdentifier
// Windows: GetForegroundWindow → QueryFullProcessImageNameW

/// Returns the bundle ID / process name of the active foreground application.
/// Returns "unknown" if the query fails or is unsupported on the current platform.
pub fn get_active_window_id() -> String {
    #[cfg(target_os = "macos")]
    {
        get_active_window_macos()
    }

    #[cfg(target_os = "windows")]
    {
        get_active_window_windows()
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        "unknown".to_string()
    }
}

// ── macOS implementation ──────────────────────────────────────────────────────

#[cfg(target_os = "macos")]
fn get_active_window_macos() -> String {
    use objc2::rc::autoreleasepool;
    use objc2_app_kit::NSWorkspace;

    autoreleasepool(|_| {
        let workspace = NSWorkspace::sharedWorkspace();
        let app = workspace.frontmostApplication();

        match app {
            Some(a) => {
                // Prefer stable bundle ID (locale-independent)
                if let Some(bundle_id) = a.bundleIdentifier() {
                    return bundle_id.to_string();
                }
                // Fallback: localised display name
                if let Some(name) = a.localizedName() {
                    return name.to_string();
                }
                "unknown".to_string()
            }
            None => "unknown".to_string(),
        }
    })
}

// ── Windows implementation ────────────────────────────────────────────────────

#[cfg(target_os = "windows")]
fn get_active_window_windows() -> String {
    use windows::Win32::System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
        PROCESS_QUERY_LIMITED_INFORMATION,
    };
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};

    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.0 == 0 {
            return "unknown".to_string();
        }

        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == 0 {
            return "unknown".to_string();
        }

        let handle = match OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) {
            Ok(h) => h,
            Err(_) => return "unknown".to_string(),
        };

        let mut buf = vec![0u16; 1024];
        let mut len = buf.len() as u32;

        if QueryFullProcessImageNameW(
            handle,
            PROCESS_NAME_WIN32,
            windows::core::PWSTR(buf.as_mut_ptr()),
            &mut len,
        )
        .is_ok()
        {
            let path = String::from_utf16_lossy(&buf[..len as usize]);
            std::path::Path::new(&path)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("unknown")
                .to_lowercase()
        } else {
            "unknown".to_string()
        }
    }
}
