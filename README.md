# OpenDeck

OpenDeck is an open-source, ultra-low latency macro controller pad that transforms your mobile device into a powerful stream deck companion. Using direct Bluetooth Low Energy (BLE), OpenDeck provides sub-15ms physical-feel tactile buttons, OBS Studio integration, dynamic application-based profile switching, and complete local privacy without any cloud accounts or mandatory subscriptions.

---

## Developer Quick-Start Guide

Want to build OpenDeck from source or contribute? Follow these steps to set up the development toolchain for both the desktop daemon and the mobile client.

### Toolchain Prerequisites

Ensure your system has the following installed before proceeding:

1. **Rust (v1.75+)**
   - Install via [rustup](https://rustup.rs/): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
   - **Windows Builders:** You will also need the MSVC C++ Build Tools installed via Visual Studio Installer.
2. **Flutter (v3.19+)**
   - Install via the official [Flutter SDK guide](https://docs.flutter.dev/get-started/install).
   - Ensure you run `flutter doctor` and resolve any missing native toolchains (Android Studio / Xcode).
3. **Node.js (v18+)**
   - Required for building the Tauri UI bindings and desktop package manager.

### 1. Cloning the Repository

```bash
git clone https://github.com/yourusername/OpenDeck.git
cd OpenDeck
```

### 2. Running the Desktop Daemon (Tauri / Rust)

The desktop agent sits in your system tray, hosts the BLE GATT Server, and executes the incoming macros natively on macOS or Windows.

```bash
cd desktop
npm install

# Run the daemon in development mode (spawns in system tray)
npm run tauri dev
```

*Note on macOS:* The first time you launch the desktop daemon and execute a hotkey, macOS will prompt you to grant Accessibility permissions in System Settings -> Privacy & Security.

### 3. Running the Mobile Client (Flutter)

The mobile app acts as the BLE Central, automatically connecting to the desktop daemon and presenting the dynamic macro grid.

```bash
cd mobile
flutter pub get

# Run on an attached physical device (required for BLE)
flutter run
```

*Note:* iOS simulators and Android emulators do **not** support Bluetooth hardware access. You must use a physical iPhone or Android device plugged in via USB or Wireless Debugging to test OpenDeck.

---

## Directory Structure

- `desktop/`: The Rust-powered Tauri background daemon. Contains the GATT server (`src-tauri/src/ble`) and the action dispatcher (`src-tauri/src/engine`).
- `mobile/`: The Flutter mobile application. Contains the UI grid (`lib/ui`) and BLE client (`lib/core/ble`).
- `shared/`: Shared assets, icon libraries, and binary schema specs.
- `.github/workflows/`: Automated GitHub Actions pipelines for compiling cross-platform release installers on Git tags.

## Sideloading (iOS)
Don't want to compile from source or pay for an Apple Developer Account? You can install the OpenDeck `.ipa` using free sideloading tools like AltStore. Read the [iOS Sideloading Guide](Doc/IOS_SIDELOAD_GUIDE.md) for instructions.

## Verification & Testing

OpenDeck's core engines have been thoroughly verified and audited:
- **Encoding:** Binary `MsgPack` schemas are perfectly mirrored across Rust (`rmp_serde`) and Dart (`msgpack_dart`).
- **Security:** Out-of-band PIN pairing and encrypted local whitelists strictly reject unrecognized BLE devices attempting to send macros.
- **Latency:** Core BLE layers negotiate a connection priority interval of ~11.25ms with MTU > 185 bytes, ensuring single-packet frame deliveries and sub-15ms trigger-to-screen responsiveness.

To run tests locally:
```bash
# Run Rust core tests
cd desktop
cargo test --manifest-path src-tauri/Cargo.toml

# Run Dart unit tests
cd mobile
flutter test
```

## License
OpenDeck is released under the [MIT License](LICENSE).
