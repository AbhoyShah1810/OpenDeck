// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck BLE GATT Server — Windows WinRT Implementation
// ─────────────────────────────────────────────────────────────────────────────
// Uses the official `windows` crate to interact with the Windows Runtime
// Bluetooth GATT Server APIs (GattServiceProvider).
//
// Flow:
//  1. Create GattServiceProvider for the primary service UUID.
//  2. Add three characteristics: Command (Write), Telemetry (Notify), Auth (RW).
//  3. Call StartAdvertising() to begin broadcasting the service UUID.
//  4. Handle WriteRequested / ReadRequested / SubscribedClientsChanged events
//     via WinRT delegates, forwarding them to the Rust BleEvent channel.

#![cfg(target_os = "windows")]
#![allow(non_snake_case)]

use std::sync::{Arc, Mutex};
use windows::{
    core::{GUID, IInspectable, Result as WinResult},
    Devices::Bluetooth::GenericAttributeProfile::{
        GattCharacteristicProperties, GattLocalCharacteristic,
        GattLocalCharacteristicParameters, GattLocalService,
        GattProtectionLevel, GattReadRequestedEventArgs,
        GattServiceProvider, GattServiceProviderAdvertisingParameters,
        GattServiceProviderResult, GattServiceProviderStatus,
        GattSubscribedClient, GattWriteRequestedEventArgs,
    },
    Foundation::Collections::IVectorView,
    Storage::Streams::{DataReader, DataWriter},
};

use crate::ble::{
    schema::BleUuid,
    server::{BleError, BleEvent, BleSender, GattServer},
};

// ── UUID helper: parse the OpenDeck UUID string → Windows GUID ────────────────
fn parse_uuid(uuid_str: &str) -> GUID {
    GUID::from(uuid_str)
}

// ── Read bytes from a Windows IBuffer ────────────────────────────────────────
fn read_ibuffer(buf: &windows::Storage::Streams::IBuffer) -> Vec<u8> {
    let reader = DataReader::FromBuffer(buf).unwrap();
    let len = reader.UnconsumedBufferLength().unwrap() as usize;
    let mut bytes = vec![0u8; len];
    reader.ReadBytes(&mut bytes).unwrap();
    bytes
}

// ── Write bytes to a Windows IBuffer ─────────────────────────────────────────
fn write_ibuffer(data: &[u8]) -> windows::Storage::Streams::IBuffer {
    let writer = DataWriter::new().unwrap();
    writer.WriteBytes(data).unwrap();
    writer.DetachBuffer().unwrap()
}

// ── Public server struct ──────────────────────────────────────────────────────
pub struct WindowsGattServer {
    tx: BleSender,
    service_provider: Mutex<Option<GattServiceProvider>>,
    telemetry_char: Mutex<Option<GattLocalCharacteristic>>,
}

impl WindowsGattServer {
    pub fn new(tx: BleSender) -> Self {
        Self {
            tx,
            service_provider: Mutex::new(None),
            telemetry_char: Mutex::new(None),
        }
    }

    /// Create all three GATT characteristics on the given local service.
    fn create_characteristics(
        &self,
        service: &GattLocalService,
    ) -> WinResult<GattLocalCharacteristic> {
        // ── Command: WriteWithoutResponse ─────────────────────────────────────
        let cmd_params = GattLocalCharacteristicParameters::new()?;
        cmd_params.SetCharacteristicProperties(
            GattCharacteristicProperties::WriteWithoutResponse,
        )?;
        cmd_params.SetReadProtectionLevel(GattProtectionLevel::Plain)?;
        cmd_params.SetWriteProtectionLevel(GattProtectionLevel::Plain)?;

        let cmd_result = service
            .CreateCharacteristicAsync(parse_uuid(BleUuid::COMMAND), &cmd_params)?
            .get()?;
        let cmd_char = cmd_result.Characteristic()?;

        // Bind write handler for incoming macro commands
        let tx_cmd = self.tx.clone();
        cmd_char.WriteRequested(&windows::Foundation::TypedEventHandler::new(
            move |_sender: &Option<GattLocalCharacteristic>,
                  args: &Option<GattWriteRequestedEventArgs>| {
                if let Some(args) = args {
                    let deferral = args.GetDeferral()?;
                    let request = args.GetRequestAsync()?.get()?;
                    let raw = read_ibuffer(&request.Value()?);
                    log::debug!("[BLE/Windows] Command received ({} bytes)", raw.len());
                    let _ = tx_cmd.send(BleEvent::CommandReceived { raw });
                    request.Respond()?;
                    deferral.Complete()?;
                }
                Ok(())
            },
        ))?;

        // ── Telemetry: Notify | Read ──────────────────────────────────────────
        let tele_params = GattLocalCharacteristicParameters::new()?;
        tele_params.SetCharacteristicProperties(
            GattCharacteristicProperties::Notify
                | GattCharacteristicProperties::Read,
        )?;
        tele_params.SetReadProtectionLevel(GattProtectionLevel::Plain)?;
        tele_params.SetWriteProtectionLevel(GattProtectionLevel::Plain)?;

        let tele_result = service
            .CreateCharacteristicAsync(parse_uuid(BleUuid::TELEMETRY), &tele_params)?
            .get()?;
        let tele_char = tele_result.Characteristic()?;

        // Track subscribe / unsubscribe events
        let tx_tele = self.tx.clone();
        tele_char.SubscribedClientsChanged(
            &windows::Foundation::TypedEventHandler::new(
                move |char: &Option<GattLocalCharacteristic>, _| {
                    if let Some(char) = char {
                        let clients = char.SubscribedClients()?;
                        let count = clients.Size().unwrap_or(0);
                        log::info!("[BLE/Windows] Telemetry subscribers: {}", count);
                        if count > 0 {
                            // Report first subscribed client ID
                            if let Ok(client) = clients.GetAt(0) {
                                let id = client.Session()?.DeviceId()?.Id()?.to_string();
                                let _ = tx_tele.send(BleEvent::ClientConnected { client_id: id });
                            }
                        } else {
                            let _ = tx_tele.send(BleEvent::ClientDisconnected {
                                client_id: "unknown".into(),
                            });
                        }
                    }
                    Ok(())
                },
            ),
        )?;

        // ── Auth: Write | Read ────────────────────────────────────────────────
        let auth_params = GattLocalCharacteristicParameters::new()?;
        auth_params.SetCharacteristicProperties(
            GattCharacteristicProperties::Write | GattCharacteristicProperties::Read,
        )?;
        auth_params.SetReadProtectionLevel(GattProtectionLevel::Plain)?;
        auth_params.SetWriteProtectionLevel(GattProtectionLevel::Plain)?;

        let auth_result = service
            .CreateCharacteristicAsync(parse_uuid(BleUuid::AUTH), &auth_params)?
            .get()?;
        let auth_char = auth_result.Characteristic()?;

        let tx_auth = self.tx.clone();
        auth_char.WriteRequested(&windows::Foundation::TypedEventHandler::new(
            move |_: &Option<GattLocalCharacteristic>,
                  args: &Option<GattWriteRequestedEventArgs>| {
                if let Some(args) = args {
                    let deferral = args.GetDeferral()?;
                    let request = args.GetRequestAsync()?.get()?;
                    let raw = read_ibuffer(&request.Value()?);
                    log::debug!("[BLE/Windows] Auth received ({} bytes)", raw.len());
                    let _ = tx_auth.send(BleEvent::AuthReceived { raw });
                    request.Respond()?;
                    deferral.Complete()?;
                }
                Ok(())
            },
        ))?;

        Ok(tele_char)
    }
}

impl GattServer for WindowsGattServer {
    fn start(&self) -> Result<(), BleError> {
        log::info!("[BLE/Windows] Creating GattServiceProvider for UUID: {}", BleUuid::SERVICE);

        let result = GattServiceProvider::CreateAsync(parse_uuid(BleUuid::SERVICE))
            .map_err(|e| BleError::PlatformError(e.to_string()))?
            .get()
            .map_err(|e| BleError::PlatformError(e.to_string()))?;

        let provider = result
            .ServiceProvider()
            .map_err(|e| BleError::PlatformError(e.to_string()))?;

        let service = provider
            .Service()
            .map_err(|e| BleError::PlatformError(e.to_string()))?;

        // Register all three characteristics
        let tele_char = self
            .create_characteristics(&service)
            .map_err(|e| BleError::PlatformError(e.to_string()))?;

        // Start advertising the primary service UUID
        let adv_params = GattServiceProviderAdvertisingParameters::new()
            .map_err(|e| BleError::PlatformError(e.to_string()))?;
        adv_params
            .SetIsConnectable(true)
            .map_err(|e| BleError::PlatformError(e.to_string()))?;
        adv_params
            .SetIsDiscoverable(true)
            .map_err(|e| BleError::PlatformError(e.to_string()))?;

        provider
            .StartAdvertisingWithParameters(&adv_params)
            .map_err(|e| BleError::PlatformError(e.to_string()))?;

        log::info!("[BLE/Windows] ✅ GattServiceProvider advertising started.");
        let _ = self.tx.send(BleEvent::PoweredOn);

        *self.service_provider.lock().unwrap() = Some(provider);
        *self.telemetry_char.lock().unwrap() = Some(tele_char);
        Ok(())
    }

    fn stop(&self) {
        if let Some(provider) = self.service_provider.lock().unwrap().as_ref() {
            let _ = provider.StopAdvertising();
            log::info!("[BLE/Windows] Advertising stopped.");
        }
    }

    fn notify_telemetry(&self, payload: Vec<u8>) -> Result<(), BleError> {
        let guard = self.telemetry_char.lock().unwrap();
        let tele_char = guard
            .as_ref()
            .ok_or_else(|| BleError::PlatformError("Telemetry char not ready".into()))?;

        let ibuf = write_ibuffer(&payload);
        tele_char
            .NotifyValueAsync(&ibuf)
            .map_err(|e| BleError::SendFailed(e.to_string()))?
            .get()
            .map_err(|e| BleError::SendFailed(e.to_string()))?;
        Ok(())
    }
}
