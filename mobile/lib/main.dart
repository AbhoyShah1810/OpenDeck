import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/ble/auto_reconnect_service.dart';
import 'core/ble/ble_manager.dart';
import 'core/storage/bonded_repository.dart';
import 'core/storage/profile_repository.dart';
import 'models/bonded_device_model.dart';
import 'models/deck_profile.dart';
import 'models/deck_tile.dart';
import 'ui/screens/pin_entry_screen.dart';
import 'ui/screens/scanner_screen.dart';
import 'ui/widgets/deck_grid.dart';
import 'ui/widgets/tile_editor_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final profileRepo = ProfileRepository();
  final bondedRepo = BondedRepository();
  await profileRepo.init();
  await bondedRepo.init();

  runApp(OpenDeckApp(
    profileRepo: profileRepo,
    bondedRepo: bondedRepo,
  ));
}

class OpenDeckApp extends StatelessWidget {
  final ProfileRepository profileRepo;
  final BondedRepository bondedRepo;

  const OpenDeckApp({
    super.key,
    required this.profileRepo,
    required this.bondedRepo,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenDeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          surface: Color(0xFF1A1A24),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: OpenDeckHomePage(
        profileRepo: profileRepo,
        bondedRepo: bondedRepo,
      ),
    );
  }
}

class OpenDeckHomePage extends StatefulWidget {
  final ProfileRepository profileRepo;
  final BondedRepository bondedRepo;

  const OpenDeckHomePage({
    super.key,
    required this.profileRepo,
    required this.bondedRepo,
  });

  @override
  State<OpenDeckHomePage> createState() => _OpenDeckHomePageState();
}

class _OpenDeckHomePageState extends State<OpenDeckHomePage>
    with WidgetsBindingObserver {
  final BleManager _bleManager = BleManager();
  late final AutoReconnectService _autoReconnect;

  late List<DeckProfile> _profiles;
  late DeckProfile _activeProfile;

  @override
  void initState() {
    super.initState();

    _autoReconnect = AutoReconnectService(
      bleManager: _bleManager,
      bondedRepo: widget.bondedRepo,
    );

    WidgetsBinding.instance.addObserver(this);

    _loadProfiles();
    _listenToTelemetry();
    _listenToReconnectEvents();

    // Attempt silent auto-connect on startup after first frame is drawn
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoReconnect.tryAutoConnect();
    });
  }

  void _loadProfiles() {
    _profiles = widget.profileRepo.getAllProfiles();
    final activeId = widget.profileRepo.getActiveProfileId();
    _activeProfile = _profiles.firstWhere(
      (p) => p.id == activeId,
      orElse: () => _profiles.first,
    );
  }

  void _listenToTelemetry() {
    _bleManager.telemetryStream.listen((telemetry) {
      if (telemetry.activeApp.isNotEmpty) {
        final matchedProfile =
            widget.profileRepo.getProfileForApp(telemetry.activeApp);
        if (matchedProfile != null &&
            matchedProfile.id != _activeProfile.id) {
          setState(() => _activeProfile = matchedProfile);
          widget.profileRepo.setActiveProfileId(matchedProfile.id);
        }
      }
    });
  }

  void _listenToReconnectEvents() {
    _autoReconnect.reconnectEvents.listen((event) {
      if (!mounted) return;
      switch (event.type) {
        case AutoReconnectEventType.connected:
          // Show a brief quiet snackbar — don't interrupt the user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '🔗 Reconnected to ${event.deviceName ?? "OpenDeck Desktop"}',
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        case AutoReconnectEventType.bluetoothUnavailable:
          // Silent — Bluetooth off is an expected state on startup
          break;
        default:
          break;
      }
    });
  }

  // ── App Lifecycle Observer ───────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground — attempt silent reconnect if link is down
      _autoReconnect.onAppForegrounded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoReconnect.dispose();
    _bleManager.dispose();
    super.dispose();
  }

  // ── Action handlers ──────────────────────────────────────────────────────────

  void _handleTileTap(DeckTile tile) async {
    final payload = tile.toActionPayload();
    try {
      if (_bleManager.status == BleConnectionStatus.ready) {
        await _bleManager.sendActionPayload(payload);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Offline simulation: ${tile.label} triggered'),
            duration: const Duration(milliseconds: 600),
            backgroundColor: const Color(0xFF1A1A24),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dispatch failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _handleTileEdit(DeckTile tile) {
    TileEditorDialog.show(
      context,
      tile: tile,
      onSave: (updatedTile) async {
        final updatedTiles = _activeProfile.tiles.map((t) {
          return t.id == updatedTile.id ? updatedTile : t;
        }).toList();

        final updatedProfile = _activeProfile.copyWith(tiles: updatedTiles);
        await widget.profileRepo.saveProfile(updatedProfile);

        setState(() {
          _activeProfile = updatedProfile;
          _loadProfiles();
        });
      },
    );
  }

  void _openScanner() async {
    final device = await ScannerScreen.show(context, bleManager: _bleManager);
    if (device == null) return;

    final success = await _bleManager.connect(device);
    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to connect to target device'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // ── Check if this device is already bonded ────────────────────────────────
    final deviceId = device.remoteId.str;
    final alreadyBonded = widget.bondedRepo.isBonded(deviceId);

    if (alreadyBonded) {
      // Known device — transition to Ready immediately
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reconnected to ${device.platformName}'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      return;
    }

    // ── Unknown device — require PIN handshake ────────────────────────────────
    final deviceName = device.platformName.isNotEmpty
        ? device.platformName
        : 'OpenDeck Desktop';

    final authed = await PinEntryScreen.show(
      context,
      bleManager: _bleManager,
      deviceName: deviceName,
    );

    if (!mounted) return;

    if (authed) {
      // Persist the bonded device UUID so future connections skip PIN
      await widget.bondedRepo.saveBondedDevice(BondedDeviceModel(
        deviceId: deviceId,
        name: deviceName,
        secretKey: 'handshake-verified',
        pairedAt: DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Paired with $deviceName — ready!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else {
      // Auth failed or user cancelled — disconnect
      await _bleManager.disconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pairing cancelled or failed'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ── Widgets ──────────────────────────────────────────────────────────────────

  Widget _buildStatusBadge() {
    return StreamBuilder<BleConnectionStatus>(
      stream: _bleManager.statusStream,
      initialData: _bleManager.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? BleConnectionStatus.disconnected;

        final Color color;
        final bool showSpinner;

        switch (status) {
          case BleConnectionStatus.ready:
            color = const Color(0xFF10B981);
            showSpinner = false;
          case BleConnectionStatus.disconnected:
            color = const Color(0xFFEF4444);
            showSpinner = false;
          case BleConnectionStatus.reconnecting:
            color = const Color(0xFF6366F1);
            showSpinner = true;
          default:
            color = const Color(0xFFF59E0B);
            showSpinner = true;
        }

        return GestureDetector(
          onTap: status == BleConnectionStatus.ready ? null : _openScanner,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSpinner)
                  SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  )
                else
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                const SizedBox(width: 6),
                Text(
                  status.label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _activeProfile.id,
                dropdownColor: const Color(0xFF1A1A24),
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                items: _profiles.map((p) {
                  return DropdownMenuItem<String>(
                    value: p.id,
                    child: Text(p.name),
                  );
                }).toList(),
                onChanged: (newId) {
                  if (newId != null) {
                    final selected = _profiles.firstWhere((p) => p.id == newId);
                    setState(() => _activeProfile = selected);
                    widget.profileRepo.setActiveProfileId(newId);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildStatusBadge(),
          ],
        ),
        backgroundColor: const Color(0xFF1A1A24),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _activeProfile.columns == 3
                  ? Icons.grid_on_rounded
                  : Icons.grid_view_rounded,
              color: const Color(0xFF6366F1),
            ),
            tooltip: 'Toggle 3x3 / 4x4 Grid',
            onPressed: () async {
              final newCols = _activeProfile.columns == 3 ? 4 : 3;
              final updated = _activeProfile.copyWith(columns: newCols);
              await widget.profileRepo.saveProfile(updated);
              setState(() => _activeProfile = updated);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: DeckGrid(
          tiles: _activeProfile.tiles,
          columns: _activeProfile.columns,
          onTileTap: _handleTileTap,
          onTileEdit: _handleTileEdit,
        ),
      ),
    );
  }
}
