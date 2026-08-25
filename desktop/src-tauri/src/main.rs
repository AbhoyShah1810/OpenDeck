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

use app_lib::ble::{
    schema::{HandshakePayload, TelemetryPayload, SystemMetrics},
    server::{create_gatt_server, generate_pairing_pin, BleEvent, GattServer},
};
use app_lib::engine::telemetry::start_telemetry_loop;

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

// ── Tauri commands ────────────────────────────────────────────────────────────

/// Get current daemon state as JSON (called from settings UI)
#[tauri::command]
fn get_daemon_state(state: tauri::State<Arc<Mutex<DaemonState>>>) -> serde_json::Value {
    let s = state.lock().unwrap();
    serde_json::json!({
        "status": s.connection_status.name(),
        "statusLabel": s.connection_status.label(),
        "pairedDeviceId": s.paired_device_id,
        "pairingPin": s.pairing_pin,
        "accessibilityGranted": app_lib::security::is_accessibility_granted(),
    })
}

/// Request macOS Accessibility permissions (triggers OS prompt)
#[tauri::command]
fn request_accessibility() -> bool {
    app_lib::security::request_accessibility_permission()
}

// ── Tray menu builder ─────────────────────────────────────────────────────────

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
    let pin_item    = MenuItem::with_id(app, "pin", &pin_label, false, None::<&str>)?;
    let sep1        = tauri::menu::PredefinedMenuItem::separator(app)?;
    let open_settings = MenuItem::with_id(app, "settings", "Open Settings...", true, None::<&str>)?;
    let sep2        = tauri::menu::PredefinedMenuItem::separator(app)?;
    let quit_item   = MenuItem::with_id(app, "quit", "Quit OpenDeck", true, None::<&str>)?;

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

// ── BLE event loop ────────────────────────────────────────────────────────────

/// Spawns a Tokio task that drains the BLE event channel and updates DaemonState
fn start_ble_event_loop(
    mut rx: app_lib::ble::server::BleReceiver,
    shared_state: Arc<Mutex<DaemonState>>,
    whitelist: Arc<app_lib::security::WhitelistManager>,
    gatt_server: Arc<dyn GattServer>,
    app_handle: AppHandle,
    telemetry_tx: tokio::sync::watch::Sender<bool>,
) {
    tokio::spawn(async move {
        log::info!("[BLE] Event loop started.");
        while let Some(event) = rx.recv().await {
            let mut state = shared_state.lock().unwrap();
            match event {
                BleEvent::PoweredOn => {
                    state.connection_status = ConnectionStatus::Advertising;
                    state.pairing_pin = Some(generate_pairing_pin());
                    log::info!("[BLE] Advertising. PIN: {}", state.pairing_pin.as_deref().unwrap_or("?"));
                }
                BleEvent::ClientConnected { client_id } => {
                    log::info!("[BLE] Client connected: {}", client_id);
                    if whitelist.is_bonded(&client_id) {
                        log::info!("[Security] Client '{}' is in whitelist — transition to Ready.", client_id);
                        state.connection_status = ConnectionStatus::Ready;
                        // Signal telemetry loop to start broadcasting
                        let _ = telemetry_tx.send(true);
                    } else {
                        log::info!("[Security] Client '{}' is unbonded — requires PIN handshake. PIN={}",
                            client_id,
                            state.pairing_pin.as_deref().unwrap_or("N/A")
                        );
                        state.connection_status = ConnectionStatus::Pairing;
                    }
                    state.paired_device_id = Some(client_id);
                }
                BleEvent::ClientDisconnected { client_id } => {
                    log::info!("[BLE] Client disconnected: {}", client_id);
                    state.connection_status = ConnectionStatus::Advertising;
                    state.paired_device_id  = None;
                    // Rotate PIN on every disconnect for security
                    state.pairing_pin = Some(generate_pairing_pin());
                    // Signal telemetry loop to pause
                    let _ = telemetry_tx.send(false);
                }
                BleEvent::AuthReceived { raw } => {
                    log::info!("[BLE] Auth payload received ({} bytes) — verifying PIN...", raw.len());

                    let current_pin = state.pairing_pin.clone().unwrap_or_default();

                    if let Ok(handshake) = rmp_serde::from_slice::<HandshakePayload>(&raw) {
                        let pin_matches = handshake.auth_code.trim() == current_pin.trim();

                        if pin_matches {
                            log::info!("[Security] ✅ PIN verified for client '{}'. Bonding.", handshake.client_id);

                            let device = app_lib::security::BondedDevice {
                                client_id: handshake.client_id.clone(),
                                device_name: format!("Mobile Device ({})", &handshake.client_id[..handshake.client_id.len().min(12)]),
                                shared_secret: handshake.auth_code.clone(),
                                paired_at: std::time::SystemTime::now()
                                    .duration_since(std::time::UNIX_EPOCH)
                                    .map(|d| d.as_secs())
                                    .unwrap_or(0),
                            };

                            if let Err(e) = whitelist.add_bonded_device(device) {
                                log::error!("[Security] Failed to save bonded device: {}", e);
                            } else {
                                log::info!("[Security] Device '{}' saved to whitelist.", handshake.client_id);
                            }

                            state.connection_status = ConnectionStatus::Ready;
                            state.pairing_pin = None; // Clear PIN display once paired
                            // Start telemetry broadcast for the newly paired client
                            let _ = telemetry_tx.send(true);

                            // Notify mobile: AUTH OK
                            let auth_ok = TelemetryPayload {
                                status: "AUTH_OK".to_string(),
                                active_app: String::new(),
                                metrics: SystemMetrics { cpu: 0.0, ram: 0.0, mic_muted: false, audio_playing: false },
                            };
                            if let Ok(bytes) = rmp_serde::to_vec_named(&auth_ok) {
                                if let Err(e) = gatt_server.notify_telemetry(bytes) {
                                    log::warn!("[BLE] Failed to send AUTH_OK telemetry: {}", e);
                                }
                            }
                        } else {
                            log::warn!(
                                "[Security] ❌ PIN mismatch for '{}': expected='{}' got='{}'",
                                handshake.client_id, current_pin, handshake.auth_code
                            );

                            // Rotate PIN immediately after a failed attempt
                            state.pairing_pin = Some(generate_pairing_pin());
                            log::info!("[Security] New PIN generated: {}", state.pairing_pin.as_deref().unwrap_or("?"));

                            // Notify mobile: AUTH FAILED
                            let auth_fail = TelemetryPayload {
                                status: "AUTH_FAIL".to_string(),
                                active_app: String::new(),
                                metrics: SystemMetrics { cpu: 0.0, ram: 0.0, mic_muted: false, audio_playing: false },
                            };
                            if let Ok(bytes) = rmp_serde::to_vec_named(&auth_fail) {
                                if let Err(e) = gatt_server.notify_telemetry(bytes) {
                                    log::warn!("[BLE] Failed to send AUTH_FAIL telemetry: {}", e);
                                }
                            }
                        }
                    } else {
                        log::error!("[BLE] Failed to deserialize HandshakePayload — dropping auth packet.");
                        state.pairing_pin = Some(generate_pairing_pin());
                    }
                }
                BleEvent::CommandReceived { raw } => {
                    log::debug!("[BLE] Command payload received ({} bytes)", raw.len());

                    let is_authorised = state.connection_status == ConnectionStatus::Ready
                        || state.paired_device_id.as_ref().map_or(false, |id| whitelist.is_bonded(id));

                    if !is_authorised {
                        log::warn!(
                            "[Security] ❌ Rejected macro command from unauthenticated client (device: {:?}, status: {:?})",
                            state.paired_device_id,
                            state.connection_status
                        );
                        continue;
                    }

                    match rmp_serde::from_slice::<app_lib::ble::schema::ActionPayload>(&raw) {
                        Ok(action) => {
                            if let Err(e) = app_lib::engine::dispatcher::dispatch_action(&action) {
                                log::error!("[BLE] Action dispatch failed: {}", e);
                            }
                        }
                        Err(e) => {
                            log::error!("[BLE] Failed to deserialize ActionPayload: {}", e);
                        }
                    }
                }
                BleEvent::Error { reason } => {
                    log::error!("[BLE] Error: {}", reason);
                    state.connection_status = ConnectionStatus::Disconnected;
                }
            }

            // Rebuild tray menu to reflect latest state on every event
            let state_snapshot = state.clone();
            drop(state); // release lock before UI work
            let handle = app_handle.clone();
            if let Ok(tray_menu) = build_tray_menu(&handle, &state_snapshot) {
                if let Some(tray) = handle.tray_by_id("main") {
                    let _ = tray.set_menu(Some(tray_menu));
                }
            }
        }
    });
}

// ── Entry point ───────────────────────────────────────────────────────────────

fn main() {
    let shared_state = Arc::new(Mutex::new(DaemonState::default()));
    let state_for_setup = shared_state.clone();
    let state_for_ble   = shared_state.clone();

    tauri::Builder::default()
        .manage(shared_state)
        .plugin(tauri_plugin_log::Builder::default().build())
        .invoke_handler(tauri::generate_handler![get_daemon_state, request_accessibility])
        .setup(move |app| {
            // Hide the settings window on start — daemon lives in the tray only
            if let Some(window) = app.get_webview_window("main") {
                window.hide().ok();
            }

            // Build initial tray menu
            let state_snapshot = state_for_setup.lock().unwrap().clone();
            let tray_menu = build_tray_menu(app.handle(), &state_snapshot)?;

            let _tray = TrayIconBuilder::with_id("main")
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

            // ── Whitelist Security Manager ────────────────────────────────────
            let config_dir = app
                .path()
                .app_data_dir()
                .unwrap_or_else(|_| std::path::PathBuf::from(".opendeck"));
            let whitelist = Arc::new(app_lib::security::WhitelistManager::new(config_dir));

            // ── Start BLE GATT server ─────────────────────────────────────────
            let (gatt_server, ble_rx) = create_gatt_server();

            // Watch channel: true = client connected & Ready, false = paused
            let (telemetry_tx, telemetry_rx) = tokio::sync::watch::channel(false);

            // Spin up the event loop BEFORE starting the server
            start_ble_event_loop(
                ble_rx,
                state_for_ble,
                whitelist,
                gatt_server.clone(),
                app.handle().clone(),
                telemetry_tx,
            );

            // Start advertising (non-blocking: CoreBluetooth uses delegate callbacks)
            if let Err(e) = gatt_server.start() {
                log::error!("[BLE] Failed to start GATT server: {}", e);
            }

            // ── Start window telemetry broadcast loop ─────────────────────────
            // Polls active window every 500ms; only transmits when a client is Ready.
            start_telemetry_loop(
                gatt_server.clone(),
                telemetry_rx,
                tokio::time::Duration::from_millis(500),
            );

            // Keep the server alive for the process lifetime
            app.manage(gatt_server);

            let acc_granted = app_lib::security::is_accessibility_granted();
            if acc_granted {
                log::info!("[Security] TCC Accessibility permission is GRANTED.");
            } else {
                log::warn!("[Security] TCC Accessibility permission is MISSING! Synthetic keypresses will require permission in System Settings.");
            }

            log::info!("OpenDeck Daemon ready.");
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("Error building OpenDeck daemon")
        .run(|_app_handle, event| {
            if let RunEvent::ExitRequested { api, .. } = event {
                // Keep daemon alive when settings window is closed
                api.prevent_exit();
            }
        });
}
