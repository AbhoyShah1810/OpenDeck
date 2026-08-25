# OpenDeck iOS Sideloading Guide

Because Apple requires a $99/year Apple Developer account to distribute applications on the App Store or via TestFlight, OpenDeck provides a zero-cost alternative for iPhone and iPad users: **Sideloading via AltStore or SideStore**.

## Generating the `.ipa`

The OpenDeck mobile app can be compiled into an unsigned `.ipa` directly from the source using Fastlane.

### Prerequisites

1. macOS with Xcode installed.
2. Flutter SDK installed.
3. Fastlane installed (`brew install fastlane`).

### Building the App

Run the following command from the `mobile/ios` directory:

```bash
cd mobile/ios
fastlane sideload
```

This will automatically compile the Flutter app in release mode and package it into `mobile/build/OpenDeck-Sideload.ipa`.

## Installing via AltStore

[AltStore](https://altstore.io/) allows you to sideload up to 3 active apps onto your iOS device using your standard (free) Apple ID.

1. **Install AltServer** on your Mac or Windows PC.
2. Connect your iPhone to your computer via USB and install AltStore to your phone.
3. Transfer the generated `OpenDeck-Sideload.ipa` to your iPhone (via AirDrop, iCloud Drive, or Email).
4. Open the **AltStore app** on your iPhone.
5. Navigate to the **My Apps** tab.
6. Tap the **+** icon in the top left corner.
7. Select the `OpenDeck-Sideload.ipa` file.
8. AltStore will sign and install the app using your Apple ID.

> [!IMPORTANT]  
> Apps sideloaded with a free Apple ID expire every 7 days. AltStore will automatically refresh the app in the background as long as your phone is on the same Wi-Fi network as the computer running AltServer.

## Installing via SideStore

[SideStore](https://sidestore.io/) is an untethered fork of AltStore that does not require a computer running AltServer in the background to refresh your apps. It signs apps directly on-device using a personal WireGuard VPN.

1. Follow the [SideStore Installation Guide](https://sidestore.io/#getting-started) to set up SideStore on your device.
2. Transfer `OpenDeck-Sideload.ipa` to your iPhone.
3. Open SideStore and navigate to **My Apps**.
4. Tap the **+** button and select the `.ipa`.
5. SideStore will install the app and automatically refresh it in the background using your WireGuard VPN.
