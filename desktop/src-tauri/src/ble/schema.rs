use serde::{Deserialize, Serialize};

/// Action type triggered by phone button tap
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ActionType {
    Hotkey,
    Shell,
    Media,
    ObsAction,
    MultiAction,
}

/// Command Action Payload (Phone -> Desktop over Command Characteristic)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ActionPayload {
    pub id: String,
    pub action_type: ActionType,
    pub modifiers: Vec<String>,
    pub key: String,
    pub payload: String,
    pub sequence_delay_ms: u32,
}

/// System Metrics snapshot
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SystemMetrics {
    pub cpu: f32,
    pub ram: f32,
    pub mic_muted: bool,
    pub audio_playing: bool,
}

/// Telemetry Payload (Desktop -> Phone over Telemetry Characteristic)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TelemetryPayload {
    pub status: String,
    pub active_app: String,
    pub metrics: SystemMetrics,
}

/// Handshake & Pairing Payload (Bidirectional over Auth Characteristic)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HandshakePayload {
    pub client_id: String,
    pub client_public_key: String,
    pub auth_code: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_action_payload_serialization() {
        let action = ActionPayload {
            id: "btn_test_1".to_string(),
            action_type: ActionType::Hotkey,
            modifiers: vec!["PRIMARY_MOD".to_string(), "ALT".to_string()],
            key: "2".to_string(),
            payload: "".to_string(),
            sequence_delay_ms: 0,
        };

        // Serialize to MsgPack
        let buf = rmp_serde::to_vec_named(&action).expect("Serialization failed");
        assert!(buf.len() < 100, "Payload size too large");

        // Deserialize back
        let deserialized: ActionPayload =
            rmp_serde::from_slice(&buf).expect("Deserialization failed");
        assert_eq!(action, deserialized);
    }

    #[test]
    fn test_telemetry_payload_serialization() {
        let telemetry = TelemetryPayload {
            status: "READY".to_string(),
            active_app: "com.microsoft.VSCode".to_string(),
            metrics: SystemMetrics {
                cpu: 14.2,
                ram: 58.6,
                mic_muted: false,
                audio_playing: true,
            },
        };

        let buf = rmp_serde::to_vec_named(&telemetry).expect("Telemetry serialization failed");
        let deserialized: TelemetryPayload =
            rmp_serde::from_slice(&buf).expect("Telemetry deserialization failed");
        assert_eq!(telemetry, deserialized);
    }
}
