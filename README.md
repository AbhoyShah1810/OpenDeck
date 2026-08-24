# OpenDeck Architecture & Monorepo Overview

Welcome to the **OpenDeck** monorepo workspace!

## Directory Structure

```
opendeck/
├── .github/
│   └── workflows/         # Automated release pipelines (macOS DMG, Windows MSI, Android APK)
├── desktop/               # Desktop Companion Agent (Tauri / Rust backend + system tray UI)
├── mobile/                # Mobile Macro Controller App (Flutter / Dart UI canvas)
├── shared/
│   ├── schemas/           # MessagePack protocol payload definitions & JSON specs
│   └── assets/            # Bundled open-source SVG icon assets
├── Doc/                   # System design specifications & implementation blueprints
├── LICENSE                # Open-source MIT License
├── requirements.txt       # Environment toolchain checklist
└── README.md              # Root repository documentation
```

## Quick Development Reference

- **Mobile App:** See [mobile/README.md](file:///Users/jellyfish/DeveloperLocal/OpenDeck/mobile/README.md) for Flutter instructions.
- **Desktop Agent:** See [desktop/README.md](file:///Users/jellyfish/DeveloperLocal/OpenDeck/desktop/README.md) for Tauri setup.
- **Protocol Specs:** See [shared/schemas](file:///Users/jellyfish/DeveloperLocal/OpenDeck/shared/schemas) for MsgPack schemas.
