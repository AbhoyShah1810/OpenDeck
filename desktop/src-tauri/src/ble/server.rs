// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck BLE GATT Server — Cross-Platform Abstraction Layer
// ─────────────────────────────────────────────────────────────────────────────
// Defines the platform-agnostic GattServer trait, shared event types, and the
// PIN generation helper. Platform implementations live in macos.rs / windows.rs.

use std::sync::Arc;
use tokio::sync::mpsc;

// ── Event Bus ─────────────────────────────────────────────────────────────────

/// Events emitted by the BLE GATT server to the rest of the daemon
#[derive(Debug, Clone)]
pub enum BleEvent {
    /// Peripheral manager powered on and is ready to advertise
    PoweredOn,
    /// A central has connected to our peripheral
    ClientConnected { client_id: String },
    /// The connected central disconnected
    ClientDisconnected { client_id: String },
    /// A macro command was received on the Command Characteristic
    CommandReceived { raw: Vec<u8> },
    /// Auth / handshake bytes received on the Auth Characteristic
    AuthReceived { raw: Vec<u8> },
    /// A generic error occurred in the BLE subsystem
    Error { reason: String },
}

pub type BleSender = mpsc::UnboundedSender<BleEvent>;
pub type BleReceiver = mpsc::UnboundedReceiver<BleEvent>;

pub fn ble_channel() -> (BleSender, BleReceiver) {
    mpsc::unbounded_channel()
}

// ── Trait ─────────────────────────────────────────────────────────────────────

/// Platform-agnostic GATT server interface
pub trait GattServer: Send + Sync + 'static {
    /// Power-on the BLE stack, register GATT services, and begin advertising.
    fn start(&self) -> Result<(), BleError>;

    /// Stop advertising and tear down the GATT server cleanly.
    fn stop(&self);

    /// Push a telemetry payload to all subscribed centrals via Notify.
    /// `payload` is a MessagePack-serialized `TelemetryPayload`.
    fn notify_telemetry(&self, payload: Vec<u8>) -> Result<(), BleError>;
}

// ── Errors ────────────────────────────────────────────────────────────────────

#[derive(Debug)]
pub enum BleError {
    NotSupported(String),
    Unauthorized,
    PoweredOff,
    AlreadyRunning,
    SendFailed(String),
    PlatformError(String),
}

impl std::fmt::Display for BleError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BleError::NotSupported(s) => write!(f, "BLE not supported: {}", s),
            BleError::Unauthorized    => write!(f, "BLE permission denied — check OS Bluetooth privacy settings"),
            BleError::PoweredOff      => write!(f, "Bluetooth is powered off"),
            BleError::AlreadyRunning  => write!(f, "GATT server is already running"),
            BleError::SendFailed(s)   => write!(f, "Notify failed: {}", s),
            BleError::PlatformError(s)=> write!(f, "Platform BLE error: {}", s),
        }
    }
}

// ── PIN Generator ─────────────────────────────────────────────────────────────

/// Generate a secure 6-digit numeric pairing PIN
pub fn generate_pairing_pin() -> String {
    use rand::Rng;
    let mut rng = rand::rng();
    format!("{:06}", rng.random_range(0u32..=999999))
}

// ── Factory ──────────────────────────────────────────────────────────────────

/// Construct the correct platform-specific GATT server and return it
/// together with the BLE event receiver.
pub fn create_gatt_server() -> (Arc<dyn GattServer>, BleReceiver) {
    let (tx, rx) = ble_channel();

    #[cfg(target_os = "macos")]
    {
        let server = Arc::new(crate::ble::macos::MacosGattServer::new(tx));
        (server, rx)
    }

    #[cfg(target_os = "windows")]
    {
        let server = Arc::new(crate::ble::windows::WindowsGattServer::new(tx));
        (server, rx)
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        let server = Arc::new(StubGattServer { tx });
        (server, rx)
    }
}

// ── Stub (Linux / unsupported) ────────────────────────────────────────────────

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub struct StubGattServer {
    pub tx: BleSender,
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
impl GattServer for StubGattServer {
    fn start(&self) -> Result<(), BleError> {
        log::warn!("[BLE] Stub server: BLE not implemented on this platform.");
        Err(BleError::NotSupported("Linux peripheral role not yet implemented".into()))
    }
    fn stop(&self) {}
    fn notify_telemetry(&self, _payload: Vec<u8>) -> Result<(), BleError> {
        Err(BleError::NotSupported("Stub".into()))
    }
}
