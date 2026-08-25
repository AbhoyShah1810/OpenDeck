// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck Security — Host Permissions & Bonded Device Whitelist
// ─────────────────────────────────────────────────────────────────────────────
// Manages:
//  1. macOS TCC Accessibility Permission check and system prompt flow.
//  2. Bonded device whitelist persistence (JSON stored in local app data).

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

// ── macOS Accessibility Permission Check ──────────────────────────────────────

/// Checks whether the application has Accessibility permissions (required for key injection)
pub fn is_accessibility_granted() -> bool {
    #[cfg(target_os = "macos")]
    {
        #[link(name = "ApplicationServices", kind = "framework")]
        extern "C" {
            fn AXIsProcessTrusted() -> bool;
        }
        unsafe { AXIsProcessTrusted() }
    }

    #[cfg(not(target_os = "macos"))]
    {
        // Windows input injection doesn't require explicit TCC accessibility permission
        true
    }
}

/// Prompt the user to grant Accessibility permission in macOS System Settings
pub fn request_accessibility_permission() -> bool {
    #[cfg(target_os = "macos")]
    {
        use core_foundation::base::TCFType;
        use core_foundation::boolean::CFBoolean;
        use core_foundation::dictionary::CFDictionary;
        use core_foundation::string::CFString;

        #[link(name = "ApplicationServices", kind = "framework")]
        extern "C" {
            fn AXIsProcessTrustedWithOptions(
                options: core_foundation::dictionary::CFDictionaryRef,
            ) -> bool;
        }

        let key = CFString::new("AXTrustedCheckOptionPrompt");
        let value = CFBoolean::true_value();

        let options = CFDictionary::from_CFType_pairs(&[(key.as_CFType(), value.as_CFType())]);

        unsafe { AXIsProcessTrustedWithOptions(options.as_concrete_TypeRef()) }
    }

    #[cfg(not(target_os = "macos"))]
    {
        true
    }
}

// ── Bonded Device Whitelist ───────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BondedDevice {
    pub client_id: String,
    pub device_name: String,
    pub shared_secret: String,
    pub paired_at: u64,
}

pub struct WhitelistManager {
    config_path: PathBuf,
    devices: Mutex<Vec<BondedDevice>>,
}

impl WhitelistManager {
    pub fn new(config_dir: PathBuf) -> Self {
        let _ = fs::create_dir_all(&config_dir);
        let config_path = config_dir.join("bonded_devices.json");
        let devices = Self::load_from_file(&config_path);

        Self {
            config_path,
            devices: Mutex::new(devices),
        }
    }

    fn load_from_file(path: &PathBuf) -> Vec<BondedDevice> {
        if let Ok(data) = fs::read_to_string(path) {
            if let Ok(list) = serde_json::from_str::<Vec<BondedDevice>>(&data) {
                return list;
            }
        }
        Vec::new()
    }

    fn save_to_file(&self) -> Result<(), String> {
        let devices = self.devices.lock().unwrap();
        let json = serde_json::to_string_pretty(&*devices)
            .map_err(|e| format!("Failed to serialize whitelist: {}", e))?;

        fs::write(&self.config_path, json)
            .map_err(|e| format!("Failed to write whitelist to {:?}: {}", self.config_path, e))?;

        Ok(())
    }

    /// Checks if a client_id is in the bonded whitelist
    pub fn is_bonded(&self, client_id: &str) -> bool {
        let devices = self.devices.lock().unwrap();
        devices.iter().any(|d| d.client_id == client_id)
    }

    /// Retrieves shared secret for a bonded client_id
    pub fn get_secret(&self, client_id: &str) -> Option<String> {
        let devices = self.devices.lock().unwrap();
        devices.iter().find(|d| d.client_id == client_id).map(|d| d.shared_secret.clone())
    }

    /// Add or update a bonded device in the whitelist
    pub fn add_bonded_device(&self, device: BondedDevice) -> Result<(), String> {
        let mut devices = self.devices.lock().unwrap();
        devices.retain(|d| d.client_id != device.client_id);
        devices.push(device);
        drop(devices);
        self.save_to_file()
    }

    /// Remove a device from the whitelist (revoke pairing)
    pub fn remove_bonded_device(&self, client_id: &str) -> Result<(), String> {
        let mut devices = self.devices.lock().unwrap();
        devices.retain(|d| d.client_id != client_id);
        drop(devices);
        self.save_to_file()
    }

    /// Get all currently bonded devices
    pub fn list_devices(&self) -> Vec<BondedDevice> {
        self.devices.lock().unwrap().clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_whitelist_manager_crud() {
        let dir = tempdir().unwrap();
        let manager = WhitelistManager::new(dir.path().to_path_buf());

        assert!(!manager.is_bonded("phone_01"));

        let dev = BondedDevice {
            client_id: "phone_01".into(),
            device_name: "Pixel 8 Pro".into(),
            shared_secret: "secret_12345".into(),
            paired_at: 1700000000,
        };

        manager.add_bonded_device(dev.clone()).unwrap();
        assert!(manager.is_bonded("phone_01"));
        assert_eq!(manager.get_secret("phone_01"), Some("secret_12345".into()));

        // Persistence check: reload from disk
        let manager2 = WhitelistManager::new(dir.path().to_path_buf());
        assert!(manager2.is_bonded("phone_01"));

        // Revoke
        manager2.remove_bonded_device("phone_01").unwrap();
        assert!(!manager2.is_bonded("phone_01"));
    }
}
