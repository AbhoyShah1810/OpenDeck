# OpenDeck: Comprehensive Step-by-Step Implementation Plan

This plan documents the end-to-end production implementation for **OpenDeck**—a 100% free, zero-cost, open-source cross-platform macro controller using **Flutter (Dart)** for iOS/Android and **Tauri (Rust)** for macOS/Windows over custom **Bluetooth Low Energy (BLE) GATT**.

---

## Architecture & Data Flow Overview

```
+-------------------------------------------------+                   +-------------------------------------------------+
|         Flutter Mobile App (GATT Central)       |   Custom BLE GATT |       Tauri Desktop Daemon (GATT Server)        |
|               [iOS / Android]                   |    Sub-15ms MTU   |               [macOS / Windows]                 |
|                                                 |                   |                                                 |
|  • Flutter Canvas & 60-120 FPS Touch Grid       | <===============> |  • System Tray Menu & App Lifecycle             |
|  • flutter_blue_plus (BLE Central Scanner)      |  128-bit UUID Service |  • WinRT / CoreBluetooth GATT Peripheral       |
|  • Isar / Hive Local NoSQL Storage              |  MsgPack Binary   |  • Native Input Engine (enigo / rdev)           |
|  • Micro-Haptic Tactile Engine                  |  Payload Encodings|  • Active Window Listener (Auto Profiles)       |
+-------------------------------------------------+                   +-------------------------------------------------+
```

---

## Implementation Phases & Step-by-Step Action Items

### Phase 1: Repository Setup & Shared Data Protocol
- [x] **Step 1.1: Monorepo Initialization**
  - Initialize git monorepo layout: `mobile/`, `desktop/`, `shared/`, `.github/`.
  - Set up root project configuration and license metadata (MIT).
- [x] **Step 1.2: BLE UUID & Protocol Freezing**
  - Define primary Service UUID: `13370001-DEAD-BEEF-FEED-CAFE00000001`.
  - Define Command Characteristic UUID (`WriteWithoutResponse`): `13370002-DEAD-BEEF-FEED-CAFE00000001`.
  - Define Telemetry Characteristic UUID (`Notify`, `Read`): `13370003-DEAD-BEEF-FEED-CAFE00000001`.
  - Define Auth Characteristic UUID (`Write`, `Read`): `13370004-DEAD-BEEF-FEED-CAFE00000001`.
- [x] **Step 1.3: MessagePack Binary Schema Definition**
  - Implement binary payload schemas in Rust (`rmp_serde`) under `desktop/src-tauri/src/ble/schema.rs`.
  - Implement binary payload schemas in Dart (`msgpack_dart`) under `mobile/lib/core/protocol/schema.dart`.
  - Add cross-platform unit test suites verifying binary encoding equivalence for `ActionPayload`, `TelemetryPayload`, and `HandshakePayload`.

---

### Phase 2: Desktop Companion Daemon (macOS & Windows)
- [x] **Step 2.1: Tauri Project Setup & System Tray**
  - Scaffold `desktop/` using Tauri (Rust core + minimal HTML/JS settings UI).
  - Configure native system tray menu (`main.rs`) displaying pairing PINs, connection status, connected devices, and logs.
- [x] **Step 2.2: Cross-Platform Native GATT Peripheral**
  - **macOS:** CoreBluetooth `CBPeripheralManager` via `objc2-core-bluetooth 0.3.2` with full delegate implementation.
  - **Windows:** WinRT `GattServiceProvider` via `windows 0.61` crate with typed event handlers.
  - Dynamic BLE advertising of custom 128-bit Primary Service UUID.
- [x] **Step 2.3: Native Input Automation Engine**
  - Synthesize synthetic keypresses, mouse clicks, and shortcuts using `enigo 0.6.1`.
  - Abstract modifier translation: `PRIMARY_MOD` $\rightarrow$ `Cmd` on macOS / `Control` on Windows.
  - Native hardware media triggers (Play/Pause, Next/Prev, Mute, Vol Up/Down).
  - Shell command runner with argument splitting via `shell-words`.
- [x] **Step 2.4: Host Permissions & Security Whitelist**
  - Added macOS `NSBluetoothAlwaysUsageDescription` & `NSBluetoothPeripheralUsageDescription` in `Info.plist` and `tauri.conf.json`.
  - Implemented TCC Accessibility permission check (`AXIsProcessTrustedWithOptions`) and Settings prompt UI flow.
  - Implemented persistent bonded device whitelist (`WhitelistManager`) and enforced whitelist validation in the GATT event loop.

---

### Phase 3: Mobile Client Application (Flutter)
- [x] **Step 3.1: Flutter Mobile Foundation**
  - Initialized Flutter app under `mobile/` configured for iOS (iOS 13.0+) and Android (API 21+).
  - Added core dependencies: `flutter_blue_plus`, `hive`, `wakelock_plus`, `haptic_feedback`, `msgpack_dart`, `google_fonts`.
  - Configured Bluetooth usage descriptions & background modes in `Info.plist` & `AndroidManifest.xml`.
- [x] **Step 3.2: BLE Central Manager & Sub-15ms Latency Engine**
  - Built `BleManager` central connection manager using `flutter_blue_plus`.
  - Implemented Android `ConnectionPriority.high` (11.25ms–15.00ms intervals) & `requestMtu(247)` single-packet MTU negotiation.
  - Implemented `sendActionPayload` using `withoutResponse: true` (`WriteWithoutResponse` GATT command mode).
  - Wired telemetry notification listener stream and auth handshake dispatching.
- [x] **Step 3.3: Interactive Touch Canvas & Haptics**
  - Built responsive `DeckGrid` widget supporting $3\times3$, $4\times4$, and customizable $M\times N$ layouts.
  - Attached tactile micro-haptics (`HapticFeedback.lightImpact()` / `selectionClick()`) and scale animation (`AnimatedScale`) to `DeckTileButton`.
  - Built in-app `TileEditorDialog` modal sheet for configuring hotkeys, colors, labels, and icons directly on phone.
- [x] **Step 3.4: Local Storage & Profile Management**
  - Configured embedded Hive NoSQL storage (`ProfileRepository` & `BondedRepository`) under `lib/core/storage/`.
  - Created `DeckProfile` & `BondedDeviceModel` schemas with default starter profile presets (General, Developer).
  - Implemented fast local persistence, profile switching dropdown, and app target auto-switching.

---

### Phase 4: Pairing, Bonding & Auto-Reconnect State Machine
- [x] **Step 4.1: Pairing State Machine**
  - Explicit 5-state machine: `DISCONNECTED` $\rightarrow$ `SCANNING` $\rightarrow$ `CONNECTING` $\rightarrow$ `PAIRING` $\rightarrow$ `READY`.
  - Built dedicated `ScannerScreen` interface filtering discovery strictly for OpenDeck Primary Service UUID (`13370001-...`).
  - Added connection status badge pill indicator in AppBar.
- [ ] **Step 4.2: Out-of-Band PIN Handshake**
  - Generate 4-digit PIN on PC screen tray upon first handshake.
  - Implement phone PIN entry prompt and verification write to Auth Characteristic.
- [ ] **Step 4.3: Background Auto-Reconnect**
  - Store validated desktop BLE UUID on phone local database.
  - Implement automatic direct reconnect routine on mobile app startup when in BLE range.

---

### Phase 5: Telemetry & Third-Party Integrations
- [ ] **Step 5.1: Active Window Listener & Auto Profile Switching**
  - Implement focused-window tracking loop on Desktop Agent (monitoring VS Code, Photoshop, OBS).
  - Broadcast window changes via Telemetry Characteristic `Notify`.
  - Auto-switch button profile on phone matching the active application.
- [ ] **Step 5.2: OBS Studio & Media Integrations**
  - Add native OBS Studio WebSocket (`obs-websocket`) connector inside desktop agent.
  - Query OS system media APIs for track metadata/artwork streaming to phone tiles.

---

### Phase 6: CI/CD & Zero-Cost Open Source Release Pipeline
- [ ] **Step 6.1: Desktop Release Matrix (GitHub Actions)**
  - Build `.github/workflows/desktop-release.yml` using `tauri-apps/tauri-action`.
  - Cross-compile universal macOS `.dmg` and Windows `.msi`/portable `.exe` on git release tags.
- [ ] **Step 6.2: Mobile Release Matrix (GitHub Actions)**
  - Build `.github/workflows/mobile-release.yml` using `subosito/flutter-action`.
  - Compile split-per-ABI Android `.apk` assets attached to GitHub releases.
  - Provide Fastlane configuration and documentation for iOS TestFlight / AltStore sideloading.
- [ ] **Step 6.3: Developer Setup Documentation**
  - Write detailed setup guides in `README.md` and repository docs.

---

## Verification & Testing Strategy

- **Unit Testing:**
  - Verify binary payload MsgPack encoding compatibility between Rust and Dart.
  - Test logical modifier key translation matrices on macOS vs Windows.
- **Latency Testing:**
  - Measure touch-to-execution latency using high-speed camera logging to ensure sub-15ms performance.
- **Security Audit:**
  - Verify unbonded BLE devices cannot execute command triggers without completing PIN verification.
