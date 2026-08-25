// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck Engine — Telemetry Loop
// ─────────────────────────────────────────────────────────────────────────────
// Runs a background Tokio task that:
//  1. Polls the foreground application every `poll_interval` via engine::window.
//  2. On app change, serialises a TelemetryPayload (status + active_app + metrics).
//  3. Pushes the payload to the mobile client via GattServer::notify_telemetry.
//
// Gating: only transmits while the watch channel value is `true` (a Ready
// client is connected). Immediately resumes polling when value flips to true.
// Debouncing: skips the BLE notify if the active app hasn't changed.

use std::sync::Arc;
use sysinfo::System;
use tokio::sync::watch;
use tokio::time::{interval, Duration};

use crate::ble::{
    schema::{SystemMetrics, TelemetryPayload},
    server::{BleError, GattServer},
};
use crate::engine::window::get_active_window_id;

// ── Public launcher ──────────────────────────────────────────────────────────

/// Spawns the telemetry polling loop.
///
/// - `gatt_server`:   Arc handle to the running GATT server for notify calls
/// - `active_rx`:     watch::Receiver<bool> — true when a Ready client is connected
/// - `poll_interval`: how often to sample the foreground window (default 500 ms)
pub fn start_telemetry_loop(
    gatt_server: Arc<dyn GattServer>,
    mut active_rx: watch::Receiver<bool>,
    poll_interval: Duration,
) {
    tokio::spawn(async move {
        log::info!(
            "[Telemetry] Window tracking loop started (interval={}ms)",
            poll_interval.as_millis()
        );

        let mut ticker = interval(poll_interval);
        let mut last_active_app = String::new();
        let mut sys = System::new_all();

        loop {
            ticker.tick().await;

            // ── Gate: only transmit while a Ready client is connected ──────
            let client_ready = *active_rx.borrow();
            if !client_ready {
                // Client disconnected — wait for the next true signal
                // borrow_and_update ensures we don't spin on unchanged values
                let _ = active_rx.changed().await;
                // Reset debounce state so the first window event after
                // reconnect is always sent fresh
                last_active_app.clear();
                continue;
            }

            // ── Sample foreground window ──────────────────────────────────
            let active_app = get_active_window_id();

            // ── Collect system metrics ─────────────────────────────────────
            sys.refresh_cpu_usage();
            sys.refresh_memory();

            let cpu_usage = sys.global_cpu_usage();
            let ram_total = sys.total_memory();
            let ram_pct = if ram_total > 0 {
                (sys.used_memory() as f32 / ram_total as f32) * 100.0
            } else {
                0.0
            };

            let mic_muted = crate::engine::obs::is_mic_muted();
            let audio_playing = crate::engine::obs::is_obs_streaming();

            let metrics = SystemMetrics {
                cpu: cpu_usage,
                ram: ram_pct,
                mic_muted,
                audio_playing,
            };

            // ── Debounce: transmit on window or metrics state change ───────
            let state_fingerprint = format!("{}:{}:{}", active_app, mic_muted, audio_playing);
            if state_fingerprint == last_active_app {
                continue;
            }

            log::info!(
                "[Telemetry] 🪟 State updated: '{}' (mic_muted={}, streaming={})",
                active_app, mic_muted, audio_playing
            );

            last_active_app = state_fingerprint;

            let payload = TelemetryPayload {
                status: "READY".to_string(),
                active_app,
                metrics,
            };

            match rmp_serde::to_vec_named(&payload) {
                Ok(bytes) => {
                    match gatt_server.notify_telemetry(bytes) {
                        Ok(()) => {
                            log::debug!("[Telemetry] Payload dispatched to mobile client");
                        }
                        Err(BleError::SendFailed(reason)) => {
                            // CB transmit queue full — non-fatal, will send on next change
                            log::warn!("[Telemetry] Notify queue full: {}", reason);
                        }
                        Err(e) => {
                            log::error!("[Telemetry] Notify error: {}", e);
                        }
                    }
                }
                Err(e) => {
                    log::error!("[Telemetry] Serialization failed: {}", e);
                }
            }
        }
    });
}
