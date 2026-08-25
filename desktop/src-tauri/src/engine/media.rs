// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck Engine — Media Control Triggers
// ─────────────────────────────────────────────────────────────────────────────
// Synthesizes OS-level media keys: Play/Pause, Next Track, Previous Track, Volume Mute/Up/Down

use enigo::{Direction, Enigo, Key, Keyboard, Settings};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaAction {
    PlayPause,
    NextTrack,
    PrevTrack,
    VolumeMute,
    VolumeUp,
    VolumeDown,
}

impl MediaAction {
    pub fn parse(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "PLAY_PAUSE" | "PLAY" | "PAUSE" | "PLAYPAUSE" => Some(Self::PlayPause),
            "NEXT" | "NEXT_TRACK" | "SKIP" => Some(Self::NextTrack),
            "PREV" | "PREVIOUS" | "PREV_TRACK" => Some(Self::PrevTrack),
            "MUTE" | "VOLUME_MUTE" => Some(Self::VolumeMute),
            "VOLUME_UP" | "VOL_UP" => Some(Self::VolumeUp),
            "VOLUME_DOWN" | "VOL_DOWN" => Some(Self::VolumeDown),
            _ => None,
        }
    }

    pub fn to_enigo_key(self) -> Key {
        match self {
            Self::PlayPause => Key::MediaPlayPause,
            Self::NextTrack => Key::MediaNextTrack,
            Self::PrevTrack => Key::MediaPrevTrack,
            Self::VolumeMute => Key::VolumeMute,
            Self::VolumeUp => Key::VolumeUp,
            Self::VolumeDown => Key::VolumeDown,
        }
    }
}

/// Execute a media action directly via hardware key simulation
pub fn simulate_media(action_str: &str) -> Result<(), String> {
    let action = MediaAction::parse(action_str)
        .ok_or_else(|| format!("Unknown media action: {}", action_str))?;

    let mut enigo = Enigo::new(&Settings::default()).map_err(|e| format!("Failed to init Enigo: {:?}", e))?;
    let key = action.to_enigo_key();

    enigo.key(key, Direction::Click).map_err(|e| format!("Media key simulation failed: {:?}", e))?;
    log::info!("[engine/media] Triggered media action: {:?}", action);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_media_action_parsing() {
        assert_eq!(MediaAction::parse("PLAY_PAUSE"), Some(MediaAction::PlayPause));
        assert_eq!(MediaAction::parse("NEXT"), Some(MediaAction::NextTrack));
        assert_eq!(MediaAction::parse("PREV"), Some(MediaAction::PrevTrack));
        assert_eq!(MediaAction::parse("MUTE"), Some(MediaAction::VolumeMute));
        assert_eq!(MediaAction::parse("VOL_UP"), Some(MediaAction::VolumeUp));
        assert_eq!(MediaAction::parse("VOL_DOWN"), Some(MediaAction::VolumeDown));
        assert_eq!(MediaAction::parse("UNKNOWN"), None);
    }
}

