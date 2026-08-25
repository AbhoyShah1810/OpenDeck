// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck BLE GATT Server — macOS CoreBluetooth Implementation
// ─────────────────────────────────────────────────────────────────────────────
// objc2 v0.6.x API:
//   • define_class! with #[ivars = Type] struct attribute
//   • All methods inside define_class! are ObjC-dispatched — pure Rust helpers
//     must live OUTSIDE the macro in separate `impl` blocks.
//   • NSMutableArray<T> requires T: Message (the inner type, not Retained<T>)

#![cfg(target_os = "macos")]
#![allow(non_snake_case)]

use std::sync::Mutex;

use dispatch2::DispatchQueue;
use objc2::{
    define_class, msg_send,
    rc::Retained,
    runtime::{NSObject, ProtocolObject},
    AnyThread, DefinedClass, Message,
};
use objc2_core_bluetooth::{
    CBATTError, CBATTRequest, CBAttributePermissions, CBCharacteristicProperties,
    CBManagerState, CBMutableCharacteristic, CBMutableService,
    CBPeripheralManager, CBPeripheralManagerDelegate, CBUUID,
};
use objc2_foundation::{NSArray, NSData, NSObjectProtocol, NSString};

use crate::ble::{
    schema::BleUuid,
    server::{BleError, BleEvent, BleSender, GattServer},
};

// ── Instance variables ────────────────────────────────────────────────────────
pub struct DelegateIvars {
    pub tx: BleSender,
    pub telemetry_char: Mutex<Option<Retained<CBMutableCharacteristic>>>,
}

// ── ObjC Delegate class ───────────────────────────────────────────────────────
// SAFETY: NSObject is the correct superclass. All CoreBluetooth calls are
// dispatched on the main queue, so single-threaded ObjC access is guaranteed.
define_class!(
    #[unsafe(super(NSObject))]
    #[ivars = DelegateIvars]
    #[name = "OpenDeckPeripheralDelegate"]
    pub struct OpenDeckDelegate;

    // NSObjectProtocol is required as a supertrait of CBPeripheralManagerDelegate
    unsafe impl NSObjectProtocol for OpenDeckDelegate {}

    // ── CBPeripheralManagerDelegate protocol ──────────────────────────────────
    unsafe impl CBPeripheralManagerDelegate for OpenDeckDelegate {

        /// Bluetooth radio state changed
        #[unsafe(method(peripheralManagerDidUpdateState:))]
        fn peripheralManagerDidUpdateState_(&self, peripheral: &CBPeripheralManager) {
            let state = unsafe { peripheral.state() };
            match state {
                CBManagerState::PoweredOn => {
                    log::info!("[BLE/macOS] Powered on — registering GATT service...");
                    let _ = self.ivars().tx.send(BleEvent::PoweredOn);
                    // Delegate to free function outside the macro (not ObjC dispatch)
                    register_gatt_service(self, peripheral);
                }
                CBManagerState::PoweredOff => {
                    log::warn!("[BLE/macOS] Bluetooth powered OFF.");
                    let _ = self.ivars().tx.send(BleEvent::Error {
                        reason: "Bluetooth powered off".into(),
                    });
                }
                CBManagerState::Unauthorized => {
                    log::error!("[BLE/macOS] Bluetooth denied — check Privacy > Bluetooth.");
                    let _ = self.ivars().tx.send(BleEvent::Error {
                        reason: "Bluetooth permission denied".into(),
                    });
                }
                CBManagerState::Unsupported => {
                    log::error!("[BLE/macOS] BLE not supported on this device.");
                    let _ = self.ivars().tx.send(BleEvent::Error {
                        reason: "BLE not supported".into(),
                    });
                }
                _ => {}
            }
        }

        /// Service was added
        #[unsafe(method(peripheralManager:didAddService:error:))]
        fn peripheralManager_didAddService_error_(
            &self,
            _manager: &CBPeripheralManager,
            service: &objc2_core_bluetooth::CBService,
            error: Option<&objc2_foundation::NSError>,
        ) {
            if let Some(e) = error {
                log::error!("[BLE/macOS] Service add failed: {}", e.localizedDescription());
            } else {
                let uuid = unsafe { service.UUID().UUIDString() }.to_string();
                log::info!("[BLE/macOS] Service registered: {}", uuid);
            }
        }

        /// Advertising started (or failed)
        #[unsafe(method(peripheralManagerDidStartAdvertising:error:))]
        fn peripheralManagerDidStartAdvertising_(
            &self,
            _manager: &CBPeripheralManager,
            error: Option<&objc2_foundation::NSError>,
        ) {
            if let Some(e) = error {
                log::error!("[BLE/macOS] Advertising failed: {}", e.localizedDescription());
            } else {
                log::info!("[BLE/macOS] ✅ Advertising: {}", BleUuid::SERVICE);
            }
        }

        /// Incoming write (Command / Auth characteristics)
        #[unsafe(method(peripheralManager:didReceiveWriteRequests:))]
        fn peripheralManager_didReceiveWriteRequests_(
            &self,
            peripheral: &CBPeripheralManager,
            requests: &NSArray<CBATTRequest>,
        ) {
            let count = requests.count();
            for i in 0..count {
                let req = requests.objectAtIndex(i);
                let uuid_str = unsafe { req.characteristic().UUID().UUIDString() }
                    .to_string()
                    .to_uppercase();

                let raw: Vec<u8> = match unsafe { req.value() } {
                    Some(d) => nsdata_to_vec(&d),
                    None => Vec::new(),
                };

                if uuid_str == BleUuid::COMMAND.to_uppercase() {
                    log::debug!("[BLE/macOS] Command ({} bytes)", raw.len());
                    let _ = self.ivars().tx.send(BleEvent::CommandReceived { raw });
                } else if uuid_str == BleUuid::AUTH.to_uppercase() {
                    log::debug!("[BLE/macOS] Auth ({} bytes)", raw.len());
                    let _ = self.ivars().tx.send(BleEvent::AuthReceived { raw });
                }

                unsafe {
                    peripheral.respondToRequest_withResult(&req, CBATTError::Success);
                }
            }
        }

        /// Central subscribed to Telemetry characteristic (connected)
        #[unsafe(method(peripheralManager:central:didSubscribeToCharacteristic:))]
        fn peripheralManager_central_didSubscribeToCharacteristic_(
            &self,
            _manager: &CBPeripheralManager,
            central: &objc2_core_bluetooth::CBCentral,
            _characteristic: &objc2_core_bluetooth::CBCharacteristic,
        ) {
            let id = unsafe { central.identifier() }.to_string();
            log::info!("[BLE/macOS] Client connected: {}", id);
            let _ = self.ivars().tx.send(BleEvent::ClientConnected { client_id: id });
        }

        /// Central unsubscribed or disconnected
        #[unsafe(method(peripheralManager:central:didUnsubscribeFromCharacteristic:))]
        fn peripheralManager_central_didUnsubscribeFromCharacteristic_(
            &self,
            _manager: &CBPeripheralManager,
            central: &objc2_core_bluetooth::CBCentral,
            _characteristic: &objc2_core_bluetooth::CBCharacteristic,
        ) {
            let id = unsafe { central.identifier() }.to_string();
            log::info!("[BLE/macOS] Client disconnected: {}", id);
            let _ = self.ivars().tx.send(BleEvent::ClientDisconnected { client_id: id });
        }
    }
);

// ── Constructor (outside define_class! — pure Rust) ───────────────────────────
impl OpenDeckDelegate {
    pub fn new(ivars: DelegateIvars) -> Retained<Self> {
        let this = Self::alloc().set_ivars(ivars);
        unsafe { msg_send![super(this), init] }
    }
}

// ── Free helper: register GATT service (pure Rust, not ObjC dispatched) ───────
fn register_gatt_service(delegate: &OpenDeckDelegate, mgr: &CBPeripheralManager) {
    let cmd_uuid  = make_cbuuid(BleUuid::COMMAND);
    let tele_uuid = make_cbuuid(BleUuid::TELEMETRY);
    let auth_uuid = make_cbuuid(BleUuid::AUTH);
    let svc_uuid  = make_cbuuid(BleUuid::SERVICE);

    // ── Characteristics ───────────────────────────────────────────────────────
    let cmd_char = unsafe {
        CBMutableCharacteristic::initWithType_properties_value_permissions(
            CBMutableCharacteristic::alloc(),
            &cmd_uuid,
            CBCharacteristicProperties::WriteWithoutResponse,
            None,
            CBAttributePermissions::Writeable,
        )
    };
    let tele_char = unsafe {
        CBMutableCharacteristic::initWithType_properties_value_permissions(
            CBMutableCharacteristic::alloc(),
            &tele_uuid,
            CBCharacteristicProperties::Notify | CBCharacteristicProperties::Read,
            None,
            CBAttributePermissions::Readable,
        )
    };
    let auth_char = unsafe {
        CBMutableCharacteristic::initWithType_properties_value_permissions(
            CBMutableCharacteristic::alloc(),
            &auth_uuid,
            CBCharacteristicProperties::Write | CBCharacteristicProperties::Read,
            None,
            CBAttributePermissions::Writeable | CBAttributePermissions::Readable,
        )
    };

    // Persist the Telemetry characteristic for later notify calls
    *delegate.ivars().telemetry_char.lock().unwrap() = Some(tele_char.retain());

    // ── Service ───────────────────────────────────────────────────────────────
    let service = unsafe {
        CBMutableService::initWithType_primary(CBMutableService::alloc(), &svc_uuid, true)
    };

    // Build NSArray<CBMutableCharacteristic>  (inner type must satisfy Message)
    let chars_array =
        NSArray::from_slice(&[
            cmd_char.as_ref(),
            tele_char.as_ref(),
            auth_char.as_ref(),
        ]);
    unsafe { service.setCharacteristics(Some(&chars_array)) };

    // Add service and start advertising
    unsafe {
        mgr.addService(&service);
        mgr.startAdvertising(None);
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn make_cbuuid(uuid_str: &str) -> Retained<CBUUID> {
    let ns = NSString::from_str(uuid_str);
    unsafe { CBUUID::UUIDWithString(&ns) }
}

/// Copy bytes from an NSData object into a Rust Vec<u8>
fn nsdata_to_vec(data: &NSData) -> Vec<u8> {
    // SAFETY: NSData guarantees the buffer is valid and immutable for its lifetime.
    // We immediately copy into a Vec so the lifetime is sound.
    unsafe { data.as_bytes_unchecked() }.to_vec()
}

// ── Public Rust GattServer wrapper ───────────────────────────────────────────
pub struct MacosGattServer {
    tx: BleSender,
    _delegate: Mutex<Option<Retained<OpenDeckDelegate>>>,
    _manager: Mutex<Option<Retained<CBPeripheralManager>>>,
}

impl MacosGattServer {
    pub fn new(tx: BleSender) -> Self {
        Self {
            tx,
            _delegate: Mutex::new(None),
            _manager: Mutex::new(None),
        }
    }
}

// SAFETY: CBPeripheralManager and our ObjC objects are only ever accessed on
// the main dispatch queue. We guarantee this by passing DispatchQueue::main()
// on creation. The Mutex guards prevent concurrent Rust-side mutation.
unsafe impl Send for MacosGattServer {}
unsafe impl Sync for MacosGattServer {}

impl GattServer for MacosGattServer {
    fn start(&self) -> Result<(), BleError> {
        log::info!("[BLE/macOS] Initialising CBPeripheralManager on main dispatch queue...");

        let delegate = OpenDeckDelegate::new(DelegateIvars {
            tx: self.tx.clone(),
            telemetry_char: Mutex::new(None),
        });

        let queue = DispatchQueue::main();

        let mgr = unsafe {
            CBPeripheralManager::initWithDelegate_queue_options(
                CBPeripheralManager::alloc(),
                Some(ProtocolObject::from_ref(&*delegate)),
                Some(&queue),
                None,
            )
        };

        *self._delegate.lock().unwrap() = Some(delegate);
        *self._manager.lock().unwrap() = Some(mgr);
        Ok(())
    }

    fn stop(&self) {
        if let Some(mgr) = self._manager.lock().unwrap().as_ref() {
            unsafe { mgr.stopAdvertising() };
            log::info!("[BLE/macOS] Advertising stopped.");
        }
    }

    fn notify_telemetry(&self, payload: Vec<u8>) -> Result<(), BleError> {
        let delegate_guard = self._delegate.lock().unwrap();
        let delegate = delegate_guard
            .as_ref()
            .ok_or_else(|| BleError::PlatformError("Delegate not initialised".into()))?;

        let tele_guard = delegate.ivars().telemetry_char.lock().unwrap();
        let tele_char = tele_guard
            .as_ref()
            .ok_or_else(|| BleError::PlatformError("Telemetry char not ready".into()))?;

        let mgr_guard = self._manager.lock().unwrap();
        let mgr = mgr_guard
            .as_ref()
            .ok_or_else(|| BleError::PlatformError("Manager not initialised".into()))?;

        let sent = unsafe {
            let data = NSData::with_bytes(&payload);
            mgr.updateValue_forCharacteristic_onSubscribedCentrals(&data, tele_char, None)
        };

        if !sent {
            return Err(BleError::SendFailed(
                "CoreBluetooth transmit queue full — will retry".into(),
            ));
        }
        Ok(())
    }
}
