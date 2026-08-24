// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck BLE Module Root
// ─────────────────────────────────────────────────────────────────────────────
// Exposes: schema (MessagePack structs), server (cross-platform trait + events),
//          and platform-specific GATT implementations.

pub mod schema;
pub mod server;

#[cfg(target_os = "macos")]
pub mod macos;

#[cfg(target_os = "windows")]
pub mod windows;
