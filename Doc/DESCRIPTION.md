# OpenDeck: Ultra-Low Latency Cross-Platform Mobile Macro Controller

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Rust](https://img.shields.io/badge/Desktop-Tauri%20%2F%20Rust-orange.svg)](https://tauri.app/)
[![Flutter](https://img.shields.io/badge/Mobile-Flutter%20%2F%20Dart-02569B.svg)](https://flutter.dev/)
[![Bluetooth](https://img.shields.io/badge/Protocol-Custom%20BLE%20GATT-0082FC.svg)](https://www.bluetooth.com/)

**OpenDeck** is a 100% free, zero-cost, open-source Stream Deck alternative that transforms any **iOS** or **Android** smartphone or tablet into a high-performance macro controller for **macOS** and **Windows**.

By utilizing a custom **Bluetooth Low Energy (BLE) GATT** service, OpenDeck achieves sub-15ms input trigger latency with zero Wi-Fi dependencies, zero paid developer programs, zero cloud accounts, and zero proprietary hardware costs.

---

## Table of Contents
- [1. Executive Summary & Zero-Cost Open Source Vision](#1-executive-summary--zero-cost-open-source-vision)
- [2. System Architecture & Communication Model](#2-system-architecture--communication-model)
  - [Why Custom BLE GATT over Bluetooth HID?](#why-custom-ble-gatt-over-bluetooth-hid)
  - [GATT Roles & Communication Flow](#gatt-roles--communication-flow)
  - [BLE GATT Services & Characteristics](#ble-gatt-services--characteristics)
  - [Binary Payload Serialization (MessagePack)](#binary-payload-serialization-messagepack)
  - [One-Time Pairing & Auto-Reconnect Sequence](#one-time-pairing--auto-reconnect-sequence)
- [3. Complete Technology Stack & Alternatives Evaluation](#3-complete-technology-stack--alternatives-evaluation)
- [4. Monorepo Repository Structure](#4-monorepo-repository-structure)
- [5. Step-by-Step Implementation Blueprint](#5-step-by-step-implementation-blueprint)
- [6. Critical Technical Considerations](#6-critical-technical-considerations)
  - [BLE Latency Optimization (Sub-15ms)](#ble-latency-optimization-sub-15ms)
  - [Cross-Platform Shortcut Mapping](#cross-platform-shortcut-mapping)
  - [Mobile Screen Wakelock & Background Behavior](#mobile-screen-wakelock--background-behavior)
- [7. Security & Local Authorization](#7-security--local-authorization)
- [8. Operating System Permissions & Setup](#8-operating-system-permissions--setup)
- [9. Zero-Cost Distribution & Open Source Release Pipeline](#9-zero-cost-distribution--open-source-release-pipeline)
- [10. Quick Start Guide for Developers](#10-quick-start-guide-for-developers)
- [11. Summary of Enhancements & Key Architectural Decisions](#11-summary-of-enhancements--key-architectural-decisions)
- [12. License](#12-license)

---

## 1. Executive Summary & Zero-Cost Open Source Vision

Commercial macro decks (like Elgato Stream Deck) require expensive dedicated hardware, while existing mobile solutions often require monthly subscriptions, cloud accounts, or Apple MFi hardware licensing.

**OpenDeck** eliminates all financial barriers for both users and developers:
- **Zero Monetization / 100% Open Source:** Licensed under MIT; anyone can build, fork, host, or adapt the software.
- **Zero MFi Licensing Required:** Avoids Bluetooth HID restrictions on iOS by operating via custom BLE GATT.
- **Zero Cloud Infrastructure Costs:** Direct peer-to-peer 2.4 GHz Bluetooth Low Energy connection; no remote server hosting or API tokens needed.
- **Zero Paid Developer Account Barriers:** Android APKs and desktop binaries are distributed free via GitHub Releases. iOS support is accessible via local Sideloading (AltStore/SideStore) or TestFlight configuration.

---

## 2. System Architecture & Communication Model

### Why Custom BLE GATT over Bluetooth HID?
Standard Bluetooth HID (Human Interface Device) emulation enables microcontrollers to act as physical keyboards. However, **iOS strictly restricts third-party non-MFi apps from emulating Bluetooth HID peripherals without Apple hardware licensing**.

To guarantee universal, zero-cost compatibility across standard consumer hardware (iOS, Android, macOS, Windows) without Apple MFi licensing or jailbreaking, OpenDeck uses a **Custom BLE GATT (Generic Attribute Profile) Client-Server Model**:

```
+-------------------------------------------------+                   +-------------------------------------------------+
|          Mobile Client App (Central)            |     BLE GATT      |          Desktop Companion Agent (Peripheral)    |
|               [iOS / Android]                   |    Connection     |                [macOS / Windows]                |
|                                                 |  (Sub-15ms MTU)   |                                                 |
|  • Flutter UI Canvas & 60-120 FPS Render Loop   | <===============> |  • Rust / Tauri System Daemon & Tray UI         |
|  • BLE Central Role & Auto-Reconnect Engine     |   Custom 128-bit  |  • BLE Peripheral Role (GATT Server)            |
|  • Dynamic Touch Grid & Micro-Haptic Engine     |    Service UUID   |  • Native Keystroke & OS Automation Engine      |
|  • Local Storage (Hive / Isar - Device Keys)    |                   |  • Active Window Focus Listener (Auto-Profile)  |
+-------------------------------------------------+                   +-------------------------------------------------+
```

---

### GATT Roles & Communication Flow

- **Desktop Role (GATT Server / Peripheral):** Advertises a dedicated custom 128-bit Service UUID. It hosts GATT characteristics for processing incoming triggers, serving auth pairing challenges, and notifying the phone of desktop status updates.
- **Mobile Role (GATT Client / Central):** Scans for the custom Service UUID, initiates connection, negotiates high-priority BLE parameters (11.25ms–15ms connection interval), and transmits low-footprint serialized action payloads.

---

### BLE GATT Services & Characteristics

| Attribute Name | UUID | Type | Properties | Description |
| :--- | :--- | :--- | :--- | :--- |
| **OpenDeck Primary Service** | `13370001-DEAD-BEEF-FEED-CAFE00000001` | Service | N/A | Core container for all OpenDeck BLE communication. |
| **Command Characteristic** | `13370002-DEAD-BEEF-FEED-CAFE00000001` | Characteristic | `WriteWithoutResponse` | Sub-15ms channel for macro triggers sent from phone to PC. |
| **Telemetry Characteristic** | `13370003-DEAD-BEEF-FEED-CAFE00000001` | Characteristic | `Notify`, `Read` | Real-time broadcast channel pushing PC state (CPU, RAM, Mute status) to phone. |
| **Auth & Pairing Characteristic** | `13370004-DEAD-BEEF-FEED-CAFE00000001` | Characteristic | `Write`, `Read` | Handshake verification channel for initial device bonding. |

---

### Binary Payload Serialization (MessagePack)

OpenDeck uses **MessagePack (MsgPack)** binary serialization to reduce payload sizes to `<32 bytes`. This fits within standard BLE MTU parameters and eliminates packet fragmentation.

#### Action Payload Schema (Phone → Desktop)
```json
{
  "id": "btn_workspace_switch",
  "type": "HOTKEY",
  "modifiers": ["PRIMARY_MOD", "ALT"],
  "key": "2",
  "payload": "",
  "sequenceDelayMs": 0
}
```
* **Supported `type` values:** `HOTKEY` | `SHELL` | `MEDIA` | `OBS_ACTION` | `MULTI_ACTION`
* **Supported `modifiers` values:** `PRIMARY_MOD` (Auto-maps to `Cmd` on macOS, `Ctrl` on Windows), `SHIFT`, `ALT`, `CONTROL`

#### Telemetry Payload Schema (Desktop → Phone)
```json
{
  "status": "READY",
  "activeApp": "com.microsoft.VSCode",
  "metrics": {
    "cpu": 14.2,
    "ram": 58.6,
    "micMuted": false,
    "audioPlaying": true
  }
}
```

#### Handshake / Pairing Payload Schema (Bidirectional)
```json
{
  "clientId": "User-Phone-Device",
  "clientPublicKey": "a1b2c3d4...",
  "authCode": "8492"
}
```

---

### One-Time Pairing & Auto-Reconnect Sequence

```
Mobile App (Central)                                Desktop Agent (Peripheral)
        |                                                       |
        | ----- 1. Scan for OpenDeck Service UUID ------------> | (Broadcasting)
        | <---- 2. BLE Service Advertised -------------------- |
        |                                                       |
        | ----- 3. Connect & Request Auth Characteristic -----> |
        | <---- 4. Send 4-Digit Challenge Displayed on Tray --- | [Displays "8492" on PC Screen]
        |                                                       |
        | ----- 5. User Inputs PIN -> Write Auth Response ----> |
        | <---- 6. Verification OK & Whitelist Identity ------- | [Saves Mobile ID to Config]
        |                                                       |
 [Stores Computer UUID]                                         |
        |                                                       |
========================== AUTO-RECONNECT (SUBSEQUENT LAUNCHES) ==========================
        |                                                       |
        | ----- 1. Direct Background Scan / Connection -------> |
        | <---- 2. Whitelist Check Passed (Auto-Bonded) ------- |
        | ===== 3. Sub-15ms Action Loop Active ================ |
```

---

## 3. Complete Technology Stack & Alternatives Evaluation

Below is the architectural matrix evaluating candidates for every layer, detailing why the selected choices best fulfill our criteria: **Zero Cost**, **High Performance (Sub-15ms Latency)**, **Cross-Platform Compatibility**, and **Open-Source Maintainability**.

| Layer | Selected Technology | Alternatives Evaluated | Section Evaluation & Rationale |
| :--- | :--- | :--- | :--- |
| **Mobile App Frontend** | **Flutter (Dart)** | **React Native (Expo)**<br>**SwiftUI + Kotlin Native** | **Selected: Flutter.**<br>• *Vs React Native:* Flutter compiles directly to native machine code without JS bridge overhead, guaranteeing smooth 60–120 FPS render loops for custom icon grids and instant touch haptics.<br>• *Vs Native iOS/Android:* Dual native apps double maintainability costs. Flutter offers a true single codebase for both iOS and Android. |
| **Mobile BLE Interface** | **`flutter_blue_plus`** | **`react-native-ble-plx`**<br>**CoreBluetooth / Android Native BLE APIs** | **Selected: `flutter_blue_plus`.**<br>• *Rationale:* Actively maintained, robust cross-platform wrapper handling low-level MTU negotiation, Android connection priority requests (`ConnectionPriority.high`), and background auto-reconnection out of the box. |
| **Mobile Embedded Storage** | **Hive / Isar** | **SQLite**<br>**MMKV / WatermelonDB** | **Selected: Hive / Isar.**<br>• *Rationale:* Lightweight, pure-Dart key-value / NoSQL embedded databases. Zero native C/C++ compilation glue, extreme read speeds for button layouts and base64 icon assets, and zero runtime cost. |
| **Desktop Companion Core** | **Tauri (Rust)** | **Electron**<br>**Python (PyQt/Tkinter)**<br>**Go (Wails)** | **Selected: Tauri (Rust).**<br>• *Vs Electron:* Electron consumes 150MB+ RAM and 80MB+ disk space. Tauri produces `<15MB` binaries with `<25MB` RAM usage.<br>• *Vs Python:* Python requires bundling a heavy runtime and struggles with low-level BLE GATT server threading.<br>• *Vs Go:* Rust offers tighter C-FFI bindings to WinRT and macOS CoreBluetooth. |
| **Desktop BLE GATT Server** | **`windows` crate (WinRT) & `objc` CoreBluetooth** | **`btleplug`**<br>**Python `bless`** | **Selected: Native OS Crates.**<br>• *Rationale:* `btleplug` primarily supports GATT Central (Client) role on desktop. Operating as a GATT Server (Peripheral) requires direct native WinRT GATT Server APIs on Windows and CoreBluetooth FFI on macOS. |
| **Desktop Input Automation** | **`enigo` / `rdev` (Rust)** | **`pyautogui`**<br>**`robotjs`** | **Selected: `enigo` / `rdev`.**<br>• *Rationale:* Native Rust hardware-level input simulation without external dependencies (Node.js or Python runtime), allowing direct key press and hotkey dispatching in sub-1ms. |
| **Desktop System Tray UI** | **Tauri System Tray API** | **`tray-item`**<br>**`pystray`** | **Selected: Tauri Native Tray.**<br>• *Rationale:* Built directly into Tauri framework. Renders native macOS Menu Bar items and Windows System Tray menus with zero overhead. |
| **Data Serialization** | **MessagePack (MsgPack)** | **JSON**<br>**Protocol Buffers (Protobuf)**<br>**FlatBuffers** | **Selected: MessagePack.**<br>• *Vs JSON:* JSON text strings add 300%+ overhead and parsing latency.<br>• *Vs Protobuf/FlatBuffers:* MsgPack provides binary compactness (`<32 bytes`) without needing complex `.proto` build toolchains. |
| **CI/CD & Distribution** | **GitHub Actions Matrix** | **GitLab CI**<br>**Bitbucket Pipelines** | **Selected: GitHub Actions.**<br>• *Rationale:* 100% free for open-source repositories. Automates compilation of macOS `.dmg`, Windows `.msi`/`.exe`, and Android `.apk` builds on every tag release. |

---

## 4. Monorepo Repository Structure

```
opendeck/
├── .github/
│   └── workflows/
│       ├── desktop-release.yml    # Tauri cross-compilation (macOS DMG + Windows MSI)
│       └── mobile-release.yml     # Flutter multi-build (Android APK + iOS release check)
├── shared/
│   ├── schemas/                   # MsgPack protocol specifications
│   └── assets/                    # Default open-source macro SVG icons
├── desktop/
│   ├── src-tauri/
│   │   ├── Cargo.toml
│   │   ├── tauri.conf.json
│   │   ├── src/
│   │   │   ├── main.rs            # Application entry & system tray lifecycle
│   │   │   ├── ble/
│   │   │   │   ├── mod.rs         # GATT peripheral setup & event loop
│   │   │   │   ├── macos.rs       # macOS CoreBluetooth GATT server
│   │   │   │   └── windows.rs     # Windows WinRT GATT server
│   │   │   ├── engine/
│   │   │   │   ├── mod.rs         # Macro action execution engine
│   │   │   │   ├── keyboard.rs    # OS key mapping & hotkey simulator
│   │   │   │   └── window.rs      # Active foreground window tracking
│   │   │   └── integrations/
│   │   │       ├── obs.rs         # OBS Studio WebSocket connector
│   │   │       └── media.rs       # OS media metadata & playback control
│   │   └── entitlements.plist     # macOS TCC accessibility & BLE permissions
│   └── ui/                        # Settings & pairing UI (Tauri webview)
└── mobile/
    ├── pubspec.yaml
    ├── lib/
    │   ├── main.dart
    │   ├── core/
    │   │   ├── ble/               # Connection manager & latency optimizer
    │   │   ├── storage/           # Local Hive / Isar storage drivers
    │   │   └── haptics/           # Micro-haptic tactile feedback engine
    │   ├── models/                # Macro action, profile, & telemetry models
    │   ├── presentation/
    │   │   ├── screens/           # BLE Scanner, Main Grid Canvas, Button Configurator
    │   │   └── widgets/           # Macro Tile Widget, Live Metrics Bar
    │   └── services/              # Auto-reconnect worker & wakelock service
    └── android/ & ios/            # Mobile platform manifests & BLE entitlements
```

---

## 5. Step-by-Step Implementation Blueprint

### Phase 1: BLE Protocol & Serialization Specification
1. Freeze standard 128-bit UUIDs for `OpenDeckService`, `CommandCharacteristic`, `TelemetryCharacteristic`, and `AuthCharacteristic`.
2. Implement and test MessagePack binary encoders/decoders in both Rust (`rmp_serde`) and Dart (`msgpack_dart`).
3. Define the challenge-response authentication PIN handshake schema.

### Phase 2: Desktop Companion Agent (macOS & Windows)
1. Initialize the Tauri background service configured to launch on system startup and minimize to the system tray.
2. Implement platform GATT Server implementations:
   - **macOS:** Objective-C / CoreBluetooth bridge via native Rust crates.
   - **Windows:** WinRT GATT Server via official `windows` crate.
3. Build macro execution handlers using `enigo`:
   - Keystrokes & hotkeys (mapping logical `PRIMARY_MOD` transparently to `Cmd` on macOS and `Ctrl` on Windows).
   - System media keys (Play, Pause, Mute, Track Next/Prev).
   - Direct command line / terminal script triggers.
4. Add macOS TCC Accessibility and Bluetooth permission configurations.

### Phase 3: Cross-Platform Mobile Application (Flutter)
1. Build the responsive Touch Canvas supporting customizable $3\times3$, $4\times4$, or $M\times N$ dynamic button grids.
2. Integrate micro-haptics on touch-down to simulate tactile mechanical switch responses.
3. Build an in-app drag-and-drop editor allowing users to create custom macro tiles, assign colors, and attach SVG icons on the phone.
4. Implement profile management saved in local NoSQL storage (Hive/Isar).

### Phase 4: Connection Management & Auto-Bonding Engine
1. Build a BLE scanning interface filtering specifically for OpenDeck Service UUID.
2. Implement state machine logic: `DISCONNECTED` → `SCANNING` → `CONNECTING` → `PAIRING` → `READY`.
3. Handle initial 4-digit PIN verification, saving bonded computer UUIDs to encrypted local storage.
4. Implement automatic background reconnection upon opening the app within BLE range.

### Phase 5: Telemetry Engine & Dynamic Profile Switching
1. Add host active-window tracking on the desktop agent (monitoring whether VS Code, Photoshop, or OBS is active).
2. Transmit window switch notifications over the Telemetry characteristic to automatically update the mobile layout.
3. Add native OBS Studio WebSocket (`obs-websocket`) and OS media metadata connectors.

### Phase 6: Open-Source Distribution & Automated CI/CD
1. Configure GitHub Actions workflows for automated cross-compilation:
   - **macOS:** Universal Apple Silicon / Intel `.dmg`.
   - **Windows:** Lightweight `.msi` and standalone portable `.exe`.
   - **Android:** Signed `.apk` assets attached to GitHub releases.
   - **iOS:** Open Fastlane pipeline and setup docs for AltStore/SideStore sideloading.

---

## 6. Critical Technical Considerations

### BLE Latency Optimization (Sub-15ms)
- **High Connection Priority:** Mobile operating systems default to battery-saving BLE intervals (30–100ms). OpenDeck explicitly requests `ConnectionPriority.high` (Android) and low connection intervals (iOS) upon handshake, locking latency down to **11.25ms – 15.00ms**.
- **GATT Write Without Response:** Macro actions write directly using `WriteWithoutResponse` commands, bypassing round-trip network ACKs and cutting command overhead in half.
- **MTU Negotiation:** Request MTU negotiation to $\ge 185$ bytes during initial handshake to ensure macro payloads fit in a single packet.

### Cross-Platform Shortcut Mapping
To ensure macro profiles are portable between macOS and Windows host machines, OpenDeck uses logical modifiers resolved by the desktop companion at runtime:

| Abstract Modifier | macOS Translation | Windows Translation |
| :--- | :--- | :--- |
| `PRIMARY_MOD` | `Command` ($\mathscr{⌘}$) | `Control` (`Ctrl`) |
| `SECONDARY_MOD` | `Control` ($\text{⌃}$) | `Windows Key` ($\text{⊞}$) |
| `ALT` | `Option` ($\text{⌥}$) | `Alt` |
| `SHIFT` | `Shift` ($\text{⇧}$) | `Shift` |

### Mobile Screen Wakelock & Background Behavior
- **Screen Wakelock:** Includes an in-app toggle using `wakelock_plus` to keep the mobile display powered with dimmed screen brightness during stream/coding sessions.
- **Direct Reconnection:** When launched, the mobile app skips generic scan cycles and directly connects to the saved Desktop Peripheral UUID.

---

## 7. Security & Local Authorization

- **Local Whitelist:** Desktop Agent enforces a whitelist of bonded mobile client UUIDs; unauthorized BLE devices cannot send macro commands.
- **Out-of-Band PIN Display:** Initial connection requires entering a 4-digit PIN generated and displayed on the PC screen.
- **100% Air-Gapped Local Operation:** Communicates purely over direct 2.4GHz BLE. No external servers, internet access, or open TCP ports required.

---

## 8. Operating System Permissions & Setup

### macOS Configuration
- **Accessibility (TCC):** Required for synthetic input injection. Grant permission via **System Settings** → **Privacy & Security** → **Accessibility** → **OpenDeck Agent**.
- **Bluetooth:** `NSBluetoothAlwaysUsageDescription` added to application plist.

### Windows Configuration
- Requires standard Bluetooth 4.0+ hardware and running `Bluetooth Support Service` (`bthserv`). Uses native WinRT APIs without extra driver installation.

---

## 9. Zero-Cost Distribution & Open Source Release Pipeline

```yaml
name: OpenDeck Release Matrix

on:
  push:
    tags:
      - 'v*'

jobs:
  build-desktop:
    strategy:
      matrix:
        include:
          - os: macos-latest
            target: universal-apple-darwin
            artifact: opendeck-macos-universal.dmg
          - os: windows-latest
            target: x86_64-pc-windows-msvc
            artifact: opendeck-windows-x64.msi
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: tauri-apps/tauri-action@v0
        with:
          tagName: ${{ github.ref_name }}
          releaseName: 'OpenDeck ${{ github.ref_name }}'

  build-mobile-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
      - run: flutter build apk --release --split-per-abi
      - uses: softprops/action-gh-release@v1
        with:
          files: mobile/build/app/outputs/flutter-apk/*.apk
```

---

## 10. Quick Start Guide for Developers

### Prerequisites
- **Rust Toolchain:** `1.75+` (`cargo`)
- **Flutter SDK:** `3.19+` (`flutter`)
- **Node.js:** `18+` (for Tauri scaffolding)

### 1. Launch Desktop Companion Agent
```bash
# Clone the repository
git clone https://github.com/your-username/opendeck.git
cd opendeck/desktop

# Install frontend dependencies and run Tauri daemon
npm install
cargo tauri dev
```

### 2. Launch Mobile Client Application
```bash
cd ../mobile

# Get Flutter dependencies
flutter pub get

# Run on physical mobile device (BLE requires real hardware)
flutter run -d <DEVICE_ID>
```

---

## 11. Summary of Enhancements & Key Architectural Decisions

1. **Flutter for Mobile Frontend:** Fully integrated Flutter (Dart) as the chosen mobile framework. Evaluated against React Native and Native Swift/Kotlin, highlighting its direct compilation to native code (no JS bridge overhead) for smooth 60–120 FPS grid rendering and micro-haptic feedback.
2. **Comprehensive Stack & Alternatives Evaluation:** Added Section 3 evaluating every stack layer (Mobile UI, Mobile BLE, Desktop Core, Desktop BLE, Serialization, Storage, CI/CD) with explicit cost, performance, and maintenance rationales.
3. **Zero-Cost & Open-Source Guarantee:** Re-architected all workflows and distribution pipelines around 100% free open-source tools (GitHub Actions, MIT License, Sideloading/APK releases, direct BLE communication) with zero cloud infrastructure overhead or paid developer licenses required.
4. **Enhanced System Architecture & Technical Depth:** Standardized GATT server/client roles, MessagePack binary schemas, PIN pairing security, sub-15ms BLE latency tuning, cross-platform modifier mapping, and clear monorepo structural blueprints.

---

## 12. License

OpenDeck is released under the **[MIT License](LICENSE)**. Free to use, modify, redistribute, and host without restrictions.

