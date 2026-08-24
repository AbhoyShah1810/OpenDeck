# OpenDeck Shared Protocol & BLE UUID Constants

pub struct BleUuid;

impl BleUuid {
    /// OpenDeck Primary GATT Service UUID
    pub const SERVICE: &'static str = "13370001-DEAD-BEEF-FEED-CAFE00000001";

    /// Command Characteristic UUID (WriteWithoutResponse: Phone -> Desktop)
    pub const COMMAND: &'static str = "13370002-DEAD-BEEF-FEED-CAFE00000001";

    /// Telemetry Characteristic UUID (Notify / Read: Desktop -> Phone)
    pub const TELEMETRY: &'static str = "13370003-DEAD-BEEF-FEED-CAFE00000001";

    /// Auth & Pairing Characteristic UUID (Write / Read: Bidirectional PIN Handshake)
    pub const AUTH: &'static str = "13370004-DEAD-BEEF-FEED-CAFE00000001";
}
