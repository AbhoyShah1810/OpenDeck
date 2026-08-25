// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck Engine — OBS Studio WebSocket v5 Connector
// ─────────────────────────────────────────────────────────────────────────────
// Connects to local obs-websocket (ws://127.0.0.1:4455) to issue scene switches,
// stream toggles, record toggles, and microphone mute actions directly without
// relying on global hotkeys or window focus.

use serde_json::json;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;
use futures_util::{SinkExt, StreamExt};

static IS_STREAMING: AtomicBool = AtomicBool::new(false);
static IS_RECORDING: AtomicBool = AtomicBool::new(false);
static IS_MIC_MUTED: AtomicBool = AtomicBool::new(false);

pub fn is_obs_streaming() -> bool {
    IS_STREAMING.load(Ordering::Relaxed)
}

pub fn is_obs_recording() -> bool {
    IS_RECORDING.load(Ordering::Relaxed)
}

pub fn is_mic_muted() -> bool {
    IS_MIC_MUTED.load(Ordering::Relaxed)
}

/// Dispatches an OBS control command over obs-websocket v5 protocol
pub async fn send_obs_command(action_raw: &str) -> Result<(), String> {
    let ws_url = "ws://127.0.0.1:4455";
    log::info!("[OBS] Connecting to OBS WebSocket at {}...", ws_url);

    let (mut ws_stream, _) = connect_async(ws_url)
        .await
        .map_err(|e| format!("Could not connect to OBS WebSocket (is OBS running on port 4455?): {}", e))?;

    // Step 1: Wait for Hello (op 0) from server
    if let Some(Ok(Message::Text(msg))) = ws_stream.next().await {
        log::debug!("[OBS] Hello received: {}", msg);
    }

    // Step 2: Send Identify (op 1)
    let identify_req = json!({
        "op": 1,
        "d": {
            "rpcVersion": 1
        }
    });
    ws_stream
        .send(Message::Text(identify_req.to_string().into()))
        .await
        .map_err(|e| format!("Failed to send Identify payload to OBS: {}", e))?;

    // Step 3: Wait for Identified (op 2)
    if let Some(Ok(Message::Text(msg))) = ws_stream.next().await {
        log::debug!("[OBS] Identified response: {}", msg);
    }

    // Step 4: Map input action to OBS request payload
    let trimmed = action_raw.trim();
    let (req_type, req_data) = if trimmed.starts_with("SCENE:") {
        let scene_name = trimmed.trim_start_matches("SCENE:").trim();
        ("SetCurrentProgramScene", json!({ "sceneName": scene_name }))
    } else if trimmed.starts_with("SWITCH_SCENE:") {
        let scene_name = trimmed.trim_start_matches("SWITCH_SCENE:").trim();
        ("SetCurrentProgramScene", json!({ "sceneName": scene_name }))
    } else if trimmed.eq_ignore_ascii_case("TOGGLE_STREAM") || trimmed.eq_ignore_ascii_case("STREAM_TOGGLE") {
        ("ToggleStream", json!({}))
    } else if trimmed.eq_ignore_ascii_case("START_STREAM") {
        ("StartStream", json!({}))
    } else if trimmed.eq_ignore_ascii_case("STOP_STREAM") {
        ("StopStream", json!({}))
    } else if trimmed.eq_ignore_ascii_case("TOGGLE_RECORD") || trimmed.eq_ignore_ascii_case("RECORD_TOGGLE") {
        ("ToggleRecord", json!({}))
    } else if trimmed.eq_ignore_ascii_case("START_RECORD") {
        ("StartRecord", json!({}))
    } else if trimmed.eq_ignore_ascii_case("STOP_RECORD") {
        ("StopRecord", json!({}))
    } else if trimmed.eq_ignore_ascii_case("TOGGLE_MUTE") || trimmed.eq_ignore_ascii_case("MUTE_MIC") {
        ("ToggleInputMute", json!({ "inputName": "Mic/Aux" }))
    } else {
        // Default treat payload as scene name if no prefix
        ("SetCurrentProgramScene", json!({ "sceneName": trimmed }))
    };

    let request_payload = json!({
        "op": 6,
        "d": {
            "requestType": req_type,
            "requestId": uuid::Uuid::new_v4().to_string(),
            "requestData": req_data
        }
    });

    log::info!("[OBS] Sending Request: {} ({:?})", req_type, req_data);
    ws_stream
        .send(Message::Text(request_payload.to_string().into()))
        .await
        .map_err(|e| format!("Failed to send request to OBS: {}", e))?;

    // Update internal state cache for telemetry
    if req_type == "ToggleStream" || req_type == "StartStream" {
        IS_STREAMING.fetch_xor(true, Ordering::Relaxed);
    } else if req_type == "StopStream" {
        IS_STREAMING.store(false, Ordering::Relaxed);
    } else if req_type == "ToggleRecord" || req_type == "StartRecord" {
        IS_RECORDING.fetch_xor(true, Ordering::Relaxed);
    } else if req_type == "StopRecord" {
        IS_RECORDING.store(false, Ordering::Relaxed);
    } else if req_type == "ToggleInputMute" {
        let cur = IS_MIC_MUTED.fetch_xor(true, Ordering::Relaxed);
        log::info!("[OBS] Mic mute state toggled to: {}", !cur);
    }

    Ok(())
}
