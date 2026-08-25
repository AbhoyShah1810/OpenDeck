import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/ble/ble_manager.dart';
import 'core/storage/bonded_repository.dart';
import 'core/storage/profile_repository.dart';
import 'models/deck_profile.dart';
import 'models/deck_tile.dart';
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

class _OpenDeckHomePageState extends State<OpenDeckHomePage> {
  final BleManager _bleManager = BleManager();
  late List<DeckProfile> _profiles;
  late DeckProfile _activeProfile;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _listenToTelemetry();
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
    // Auto profile switching based on active desktop app telemetry
    _bleManager.telemetryStream.listen((telemetry) {
      if (telemetry.activeApp.isNotEmpty) {
        final matchedProfile = widget.profileRepo.getProfileForApp(telemetry.activeApp);
        if (matchedProfile != null && matchedProfile.id != _activeProfile.id) {
          setState(() {
            _activeProfile = matchedProfile;
          });
          widget.profileRepo.setActiveProfileId(matchedProfile.id);
        }
      }
    });
  }

  @override
  void dispose() {
    _bleManager.dispose();
    super.dispose();
  }

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
    if (device != null) {
      final success = await _bleManager.connect(device);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device.platformName}'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to target device'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildStatusBadge() {
    return StreamBuilder<BleConnectionStatus>(
      stream: _bleManager.statusStream,
      initialData: _bleManager.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? BleConnectionStatus.disconnected;
        final color = status == BleConnectionStatus.ready
            ? const Color(0xFF10B981)
            : status == BleConnectionStatus.disconnected
                ? const Color(0xFFEF4444)
                : const Color(0xFFF59E0B);

        return GestureDetector(
          onTap: _openScanner,
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
              _activeProfile.columns == 3 ? Icons.grid_on_rounded : Icons.grid_view_rounded,
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
