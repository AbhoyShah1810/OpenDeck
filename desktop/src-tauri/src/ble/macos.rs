// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck BLE GATT Server — macOS CoreBluetooth Implementation
// ─────────────────────────────────────────────────────────────────────────────
// Uses objc2-core-bluetooth to operate in Peripheral role.
// Architecture:
//   • MacosGattServer::new()      — build the Rust wrapper (no ObjC yet)
//   • MacosGattServer::start()    — spawn an OS thread with a CFRunLoop /
//                                   DispatchQueue, init CBPeripheralManager,
//                                   add GATT services, start advertising.
//   • Delegate callbacks          — forwarded through a Rust channel to the
//                                   main Tauri state loop.

#![allow(non_snake_case, clippy::too_many_arguments)]

use std::{
    ptr::NonNull,
    sync::{Arc, Mutex},
};

use objc2::{
    declare_class, msg_send, msg_send_id,
    rc::{Allocated, Id, Retained},
    runtime::{AnyObject, NSObject, ProtocolObject},
    ClassType, DeclaredClass,
};
use objc2_core_bluetooth::{
    CBAdvertisementDataLocalNameKey, CBAdvertisementDataServiceUUIDsKey,
    CBAttributePermissions, CBCharacteristicProperties, CBManagerState,
    CBMutableCharacteristic, CBMutableService, CBPeripheralManager,
    CBPeripheralManagerDelegate, CBUUID,
};
use objc2_foundation::{NSArray, NSData, NSDictionary, NSMutableArray, NSString};

use crate::ble::{
    schema::BleUuid,
    server::{BleError, BleEvent, BleSender, GattServer},
};

// ── State held inside the ObjC delegate object ────────────────────────────────
struct DelegateIvars {
    tx: BleSender,
    telemetry_char: Mutex<Option<Retained<CBMutableCharacteristic>>>,
    manager: Mutex<Option<Retained<CBPeripheralManager>>>,
}

// ── ObjC Delegate class declaration ──────────────────────────────────────────
declare_class!(
    struct OpenDeckDelegate;

    unsafe impl ClassType for OpenDeckDelegate {
        type Super = NSObject;
        type Mutability = objc2::mutability::MainThreadOnly;
        const NAME: &'static str = "OpenDeckPeripheralDelegate";
    }

    impl DeclaredClass for OpenDeckDelegate {
        type Ivars = DelegateIvars;
    }

    // CBPeripheralManagerDelegate protocol methods
    #[allow(non_snake_case)]
    unsafe impl CBPeripheralManagerDelegate for OpenDeckDelegate {

        // Called when the Bluetooth radio state changes
        #[method(peripheralManagerDidUpdateState:)]
        fn did_update_state(&self, peripheral: &CBPeripheralManager) {
            let state = unsafe { peripheral.state() };
            match state {
                CBManagerState::PoweredOn => {
                    log::info!("[BLE/macOS] Bluetooth powered on — registering GATT services...");
                    let _ = self.ivars().tx.send(BleEvent::PoweredOn);
                    // Set up and advertise GATT services now that the radio is ready
                    if let Err(e) = self.register_and_advertise(peripheral) {
                        log::error!("[BLE/macOS] Failed to register services: {}", e);
                    }
                }
                CBManagerState::PoweredOff => {
                    log::warn!("[BLE/macOS] Bluetooth powered OFF.");
                    let _ = self.ivars().tx.send(BleEvent::Error {
                        reason: "Bluetooth powered off".into(),
                    });
                }
                CBManagerState::Unauthorized => {
                    log::error!("[BLE/macOS] Bluetooth access denied — check Privacy settings.");
                    let _ = self.ivars().tx.send(BleEvent::Error {
                        reason: "Bluetooth permission denied".into(),
                    });
                }
                CBManagerState::Unsupported => {
                    log::error!("[BLE/macOS] Bluetooth LE is not supported on this device.");
                    let _ = self.ivars().tx.send(BleEvent::Error {
                        reason: "BLE not supported".into(),
                    });
                }
                _ => {
                    log::debug!("[BLE/macOS] BT state changed: {:?}", state as u8);
                }
            }
        }

        // Called when a central writes to the Command or Auth characteristic
        #[method(peripheralManager:didReceiveWriteRequests:)]
        fn did_receive_write_requests(
            &self,
            peripheral: &CBPeripheralManager,
            requests: &NSArray<objc2_core_bluetooth::CBATTRequest>,
        ) {
            for i in 0..unsafe { requests.count() } {
                let req = unsafe { requests.objectAtIndex(i) };
                let char = unsafe { req.characteristic() };
                let uuid_str = uuid_to_string(unsafe { char.UUID() });

                let raw: Vec<u8> = if let Some(data) = unsafe { req.value() } {
                    unsafe { data.bytes() }.to_vec()
                } else {
                    Vec::new()
                };

                if uuid_str == BleUuid::COMMAND.to_lowercase() {
                    log::debug!("[BLE/macOS] Command received ({} bytes)", raw.len());
                    let _ = self.ivars().tx.send(BleEvent::CommandReceived { raw });
                } else if uuid_str == BleUuid::AUTH.to_lowercase() {
                    log::debug!("[BLE/macOS] Auth received ({} bytes)", raw.len());
                    let _ = self.ivars().tx.send(BleEvent::AuthReceived { raw });
                }

                // Respond with success for Write requests (not WriteWithoutResponse)
                unsafe {
                    peripheral.respondToRequest_withResult(
                        &req,
                        objc2_core_bluetooth::CBATTError::Success,
                    );
                }
            }
        }

        // Called when a central subscribes to the Telemetry characteristic
        #[method(peripheralManager:central:didSubscribeToCharacteristic:)]
        fn central_did_subscribe(
            &self,
            _peripheral: &CBPeripheralManager,
            central: &objc2_core_bluetooth::CBCentral,
            _char: &objc2_core_bluetooth::CBCharacteristic,
        ) {
            let id = peer_id_string(central);
            log::info!("[BLE/macOS] Central subscribed to telemetry: {}", id);
            let _ = self.ivars().tx.send(BleEvent::ClientConnected { client_id: id });
        }

        // Called when a central disconnects or unsubscribes
        #[method(peripheralManager:central:didUnsubscribeFromCharacteristic:)]
        fn central_did_unsubscribe(
            &self,
            _peripheral: &CBPeripheralManager,
            central: &objc2_core_bluetooth::CBCentral,
            _char: &objc2_core_bluetooth::CBCharacteristic,
        ) {
            let id = peer_id_string(central);
            log::info!("[BLE/macOS] Central unsubscribed: {}", id);
            let _ = self.ivars().tx.send(BleEvent::ClientDisconnected { client_id: id });
        }

        // Called when service addition is complete
        #[method(peripheralManager:didAddService:error:)]
        fn did_add_service(
            &self,
            _peripheral: &CBPeripheralManager,
            service: &objc2_core_bluetooth::CBService,
            error: Option<&objc2_foundation::NSError>,
        ) {
            if let Some(e) = error {
                log::error!("[BLE/macOS] Failed to add service: {}", unsafe { e.localizedDescription() });
            } else {
                let uuid = uuid_to_string(unsafe { service.UUID() });
                log::info!("[BLE/macOS] Service registered: {}", uuid);
            }
        }

        // Called when advertising starts
        #[method(peripheralManagerDidStartAdvertising:)]
        fn did_start_advertising(
            &self,
            _peripheral: &CBPeripheralManager,
            error: Option<&objc2_foundation::NSError>,
        ) {
            if let Some(e) = error {
                log::error!("[BLE/macOS] Advertising failed: {}", unsafe { e.localizedDescription() });
            } else {
                log::info!("[BLE/macOS] ✅ Advertising started for service: {}", BleUuid::SERVICE);
            }
        }
    }
);

// ── Helper: Build a CBUUID from a 128-bit UUID string ────────────────────────
fn cbuuid_from_str(uuid_str: &str) -> Retained<CBUUID> {
    let ns_str = NSString::from_str(uuid_str);
    unsafe { CBUUID::UUIDWithString(&ns_str) }
}

// ── Helper: Extract a printable UUID string from a CBUUID ────────────────────
fn uuid_to_string(uuid: &CBUUID) -> String {
    unsafe { uuid.UUIDString() }.to_string().to_lowercase()
}

// ── Helper: Get peer identifier string from CBCentral ────────────────────────
fn peer_id_string(central: &objc2_core_bluetooth::CBCentral) -> String {
    unsafe { central.identifier() }.to_string()
}

impl OpenDeckDelegate {
    // Called from did_update_state after PoweredOn — sets up the full GATT hierarchy
    fn register_and_advertise(&self, mgr: &CBPeripheralManager) -> Result<(), String> {
        unsafe {
            // ── Characteristics ───────────────────────────────────────────────
            let cmd_uuid    = cbuuid_from_str(BleUuid::COMMAND);
            let tele_uuid   = cbuuid_from_str(BleUuid::TELEMETRY);
            let auth_uuid   = cbuuid_from_str(BleUuid::AUTH);

            // Command: WriteWithoutResponse
            let cmd_char = CBMutableCharacteristic::initWithType_properties_value_permissions(
                CBMutableCharacteristic::alloc(),
                &cmd_uuid,
                CBCharacteristicProperties::WriteWithoutResponse,
                None,
                CBAttributePermissions::Writeable,
            );

            // Telemetry: Notify | Read
            let tele_char = CBMutableCharacteristic::initWithType_properties_value_permissions(
                CBMutableCharacteristic::alloc(),
                &tele_uuid,
                CBCharacteristicProperties::Notify
                    | CBCharacteristicProperties::Read,
                None,
                CBAttributePermissions::Readable,
            );

            // Auth: Write | Read
            let auth_char = CBMutableCharacteristic::initWithType_properties_value_permissions(
                CBMutableCharacteristic::alloc(),
                &auth_uuid,
                CBCharacteristicProperties::Write
                    | CBCharacteristicProperties::Read,
                None,
                CBAttributePermissions::Writeable
                    | CBAttributePermissions::Readable,
            );

            // Store telemetry characteristic for later notify calls
            *self.ivars().telemetry_char.lock().unwrap() = Some(tele_char.retain());

            // ── Service ───────────────────────────────────────────────────────
            let svc_uuid = cbuuid_from_str(BleUuid::SERVICE);
            let service = CBMutableService::initWithType_primary(
                CBMutableService::alloc(),
                &svc_uuid,
                true,
            );

            // Build characteristics array: [cmd, tele, auth]
            let chars_array: Retained<NSArray<CBMutableCharacteristic>> =
                NSArray::from_retained_slice(&[cmd_char, tele_char, auth_char]);
            service.setCharacteristics(Some(&chars_array));

            // Add service to peripheral manager
            mgr.addService(&service);

            // ── Advertising payload ───────────────────────────────────────────
            let svc_uuid_for_adv = cbuuid_from_str(BleUuid::SERVICE);
            let uuids_array: Retained<NSArray<CBUUID>> =
                NSArray::from_retained_slice(&[svc_uuid_for_adv]);
            let local_name = NSString::from_str("OpenDeck");

            let adv_keys: Retained<NSArray<NSString>> = NSArray::from_retained_slice(&[
                NSString::from_str(&CBAdvertisementDataServiceUUIDsKey.to_string()),
                NSString::from_str(&CBAdvertisementDataLocalNameKey.to_string()),
            ]);
            // NSDictionary of advertising data
            let adv_values: Retained<NSArray<AnyObject>> = NSArray::from_retained_slice(&[
                Retained::into_super(Retained::into_super(uuids_array)),
                Retained::into_super(Retained::into_super(local_name)),
            ]);
            let adv_dict = NSDictionary::from_keys_and_objects(&adv_keys, &adv_values);
            mgr.startAdvertising(Some(&adv_dict));
        }
        Ok(())
    }
}

// ── Public Rust struct wrapping the ObjC machinery ───────────────────────────

pub struct MacosGattServer {
    tx: BleSender,
    /// Holds the ObjC objects alive for the server's lifetime
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

impl GattServer for MacosGattServer {
    fn start(&self) -> Result<(), BleError> {
        // CoreBluetooth must run on the main thread (or a dedicated serial queue).
        // Tauri already runs its setup on the main thread, so we initialise here.
        // CBPeripheralManager creation automatically triggers did_update_state.
        log::info!("[BLE/macOS] Initialising CBPeripheralManager...");

        // Use main dispatch queue (required for CoreBluetooth)
        let queue = unsafe { dispatch2::DispatchQueue::main() };

        let delegate = OpenDeckDelegate::new(DelegateIvars {
            tx: self.tx.clone(),
            telemetry_char: Mutex::new(None),
            manager: Mutex::new(None),
        });

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
        let delegate = delegate_guard.as_ref().ok_or_else(|| BleError::PlatformError("Delegate not ready".into()))?;
        let tele_guard = delegate.ivars().telemetry_char.lock().unwrap();
        let tele_char = tele_guard.as_ref().ok_or_else(|| BleError::PlatformError("Telemetry char not registered".into()))?;
        let mgr_guard = self._manager.lock().unwrap();
        let mgr = mgr_guard.as_ref().ok_or_else(|| BleError::PlatformError("Manager not ready".into()))?;

        unsafe {
            let ns_data = NSData::with_bytes(&payload);
            let sent = mgr.updateValue_forCharacteristic_onSubscribedCentrals(
                &ns_data,
                tele_char,
                None,
            );
            if !sent {
                return Err(BleError::SendFailed("Transmit queue full — will retry on next cycle".into()));
            }
        }
        Ok(())
    }
}
