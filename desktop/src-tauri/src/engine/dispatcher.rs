// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck Engine — Action Dispatcher
// ─────────────────────────────────────────────────────────────────────────────
// Receives deserialized `ActionPayload` objects from BLE or UI and dispatches
// them to the appropriate sub-engine (keyboard hotkey, media, shell command).

use crate::ble::schema::{ActionPayload, ActionType};
use crate::engine::{keyboard, media, shell};

pub fn dispatch_action(action: &ActionPayload) -> Result<(), String> {
    log::info!(
        "[engine/dispatcher] Dispatching action: id='{}', type={:?}",
        action.id,
        action.action_type
    );

    match action.action_type {
        ActionType::Hotkey => {
            keyboard::simulate_hotkey(&action.modifiers, &action.key)?;
        }
        ActionType::Media => {
            // Action target is passed either in payload or key string
            let media_target = if !action.payload.is_empty() {
                &action.payload
            } else {
                &action.key
            };
            media::simulate_media(media_target)?;
        }
        ActionType::Shell => {
            shell::execute_shell_command(&action.payload)?;
        }
        ActionType::ObsAction => {
            // OBS websocket or shortcut action placeholder
            log::info!("[engine/dispatcher] OBS action triggered: {}", action.payload);
            if !action.payload.is_empty() {
                shell::execute_shell_command(&action.payload)?;
            }
        }
        ActionType::MultiAction => {
            // Multi-action macro payload (delay or sequential hotkeys)
            log::info!(
                "[engine/dispatcher] MultiAction triggered with delay {}ms: {}",
                action.sequence_delay_ms,
                action.payload
            );
            if !action.key.is_empty() {
                keyboard::simulate_hotkey(&action.modifiers, &action.key)?;
            }
        }
    }

    Ok(())
}
