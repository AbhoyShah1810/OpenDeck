// OpenDeck Desktop Companion Agent - Main Entry Point
// Runs as a persistent background daemon in the macOS Menu Bar / Windows System Tray.
// Manages: BLE GATT Server, Macro Execution Engine, Pairing PIN display, and Connection status.

// Prevents a console window from appearing on Windows in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::sync::{Arc, Mutex};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, RunEvent,
};

/// Shared global daemon state accessible across Tauri commands and the tray menu
#[derive(Debug, Clone)]
pub struct DaemonState {
    pub connection_status: ConnectionStatus,
    pub paired_device_id: Option<String>,
    pub pairing_pin: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ConnectionStatus {
    Disconnected,
    Advertising,
    Connecting,
    Pairing,
    Ready,
}

impl ConnectionStatus {
    pub fn label(&self) -> &'static str {
        match self {
            ConnectionStatus::Disconnected => "⚫ Disconnected",
            ConnectionStatus::Advertising  => "🔵 Advertising — Waiting for device",
            ConnectionStatus::Connecting   => "🟡 Connecting...",
            ConnectionStatus::Pairing      => "🟠 Pairing — Check PIN below",
            ConnectionStatus::Ready        => "🟢 Connected & Ready",
        }
    }
    pub fn name(&self) -> &'static str {
        match self {
            ConnectionStatus::Disconnected => "Disconnected",
            ConnectionStatus::Advertising  => "Advertising",
            ConnectionStatus::Connecting   => "Connecting",
            ConnectionStatus::Pairing      => "Pairing",
            ConnectionStatus::Ready        => "Ready",
        }
    }
}

impl Default for DaemonState {
    fn default() -> Self {
        Self {
            connection_status: ConnectionStatus::Disconnected,
            paired_device_id: None,
            pairing_pin: None,
        }
    }
}

/// Tauri command: Get current daemon state as JSON (called from settings UI)
#[tauri::command]
fn get_daemon_state(state: tauri::State<Arc<Mutex<DaemonState>>>) -> serde_json::Value {
    let s = state.lock().unwrap();
    serde_json::json!({
        "status": s.connection_status.name(),
        "statusLabel": s.connection_status.label(),
        "pairedDeviceId": s.paired_device_id,
        "pairingPin": s.pairing_pin,
    })
}

/// Build the system tray menu from current daemon state
fn build_tray_menu(app: &AppHandle, state: &DaemonState) -> tauri::Result<Menu<tauri::Wry>> {
    let status_item = MenuItem::with_id(
        app, "status", state.connection_status.label(), false, None::<&str>,
    )?;

    let device_label = match &state.paired_device_id {
        Some(id) => format!("Device: {}", id),
        None => "Device: None paired".to_string(),
    };
    let device_item = MenuItem::with_id(app, "device", &device_label, false, None::<&str>)?;

    let pin_label = match &state.pairing_pin {
        Some(pin) => format!("Pairing PIN: {}", pin),
        None => "Pairing PIN: —".to_string(),
    };
    let pin_item = MenuItem::with_id(app, "pin", &pin_label, false, None::<&str>)?;

    let sep1 = tauri::menu::PredefinedMenuItem::separator(app)?;
    let open_settings = MenuItem::with_id(app, "settings", "Open Settings...", true, None::<&str>)?;
    let sep2 = tauri::menu::PredefinedMenuItem::separator(app)?;
    let quit_item = MenuItem::with_id(app, "quit", "Quit OpenDeck", true, None::<&str>)?;

    Menu::with_items(app, &[
        &status_item,
        &device_item,
        &pin_item,
        &sep1,
        &open_settings,
        &sep2,
        &quit_item,
    ])
}

fn main() {
    let shared_state = Arc::new(Mutex::new(DaemonState::default()));
    let state_for_setup = shared_state.clone();

    tauri::Builder::default()
        .manage(shared_state)
        .plugin(tauri_plugin_log::Builder::default().build())
        .invoke_handler(tauri::generate_handler![get_daemon_state])
        .setup(move |app| {
            // Hide the settings window on start — daemon lives in the tray only
            if let Some(window) = app.get_webview_window("main") {
                window.hide().ok();
            }

            let state_snapshot = state_for_setup.lock().unwrap().clone();
            let tray_menu = build_tray_menu(app.handle(), &state_snapshot)?;

            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("OpenDeck — Macro Controller")
                .menu(&tray_menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => {
                        log::info!("OpenDeck: Quit triggered from tray.");
                        app.exit(0);
                    }
                    "settings" => {
                        if let Some(window) = app.get_webview_window("main") {
                            window.show().ok();
                            window.set_focus().ok();
                        }
                    }
                    _ => {}
                })
                .on_tray_icon_event(|_tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event {}
                })
                .build(app)?;

            log::info!("OpenDeck Daemon started — BLE GATT server initializing...");
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("Error building OpenDeck daemon")
        .run(|_app_handle, event| {
            if let RunEvent::ExitRequested { api, .. } = event {
                // Prevent full exit when settings window is closed — keep running in tray
                api.prevent_exit();
            }
        });
}
