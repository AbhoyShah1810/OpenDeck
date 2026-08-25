import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/protocol/schema.dart';
import '../../models/deck_tile.dart';

/// Modal Bottom Sheet for configuring tile properties, hotkeys, colors, and actions directly on phone
class TileEditorDialog extends StatefulWidget {
  final DeckTile tile;
  final Function(DeckTile updatedTile) onSave;

  const TileEditorDialog({
    super.key,
    required this.tile,
    required this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    required DeckTile tile,
    required Function(DeckTile updatedTile) onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => TileEditorDialog(tile: tile, onSave: onSave),
    );
  }

  @override
  State<TileEditorDialog> createState() => _TileEditorDialogState();
}

class _TileEditorDialogState extends State<TileEditorDialog> {
  late TextEditingController _labelController;
  late TextEditingController _keyController;
  late TextEditingController _payloadController;

  late String _selectedColorHex;
  late String _selectedIcon;
  late ActionType _selectedActionType;
  late List<String> _selectedModifiers;

  final List<String> _availableIcons = [
    'sports_esports',
    'play_arrow',
    'pause',
    'skip_next',
    'skip_previous',
    'volume_off',
    'volume_up',
    'code',
    'terminal',
    'videocam',
    'mic',
    'mic_off',
    'content_copy',
    'content_paste',
    'settings',
  ];

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.tile.label);
    _keyController = TextEditingController(text: widget.tile.key);
    _payloadController = TextEditingController(text: widget.tile.payload);
    _selectedColorHex = widget.tile.colorHex;
    _selectedIcon = widget.tile.iconName;
    _selectedActionType = widget.tile.actionType;
    _selectedModifiers = List<String>.from(widget.tile.modifiers);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _keyController.dispose();
    _payloadController.dispose();
    super.dispose();
  }

  void _toggleModifier(String mod) {
    setState(() {
      if (_selectedModifiers.contains(mod)) {
        _selectedModifiers.remove(mod);
      } else {
        _selectedModifiers.add(mod);
      }
    });
  }

  IconData _getIconData(String name) {
    switch (name.toLowerCase()) {
      case 'play_arrow': return Icons.play_arrow_rounded;
      case 'pause': return Icons.pause_rounded;
      case 'skip_next': return Icons.skip_next_rounded;
      case 'skip_previous': return Icons.skip_previous_rounded;
      case 'volume_off': return Icons.volume_off_rounded;
      case 'volume_up': return Icons.volume_up_rounded;
      case 'code': return Icons.code_rounded;
      case 'terminal': return Icons.terminal_rounded;
      case 'videocam': return Icons.videocam_rounded;
      case 'mic': return Icons.mic_rounded;
      case 'mic_off': return Icons.mic_off_rounded;
      case 'content_copy': return Icons.content_copy_rounded;
      case 'content_paste': return Icons.content_paste_rounded;
      case 'settings': return Icons.settings_rounded;
      default: return Icons.sports_esports_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Edit Macro Tile',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Label Field ────────────────────────────────────────────────
            TextField(
              controller: _labelController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Button Label',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFF0F0F13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // ── Action Type ────────────────────────────────────────────────
            Text(
              'ACTION TYPE',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ActionType.values.map((type) {
                final isSelected = _selectedActionType == type;
                return ChoiceChip(
                  label: Text(type.toValue()),
                  selected: isSelected,
                  selectedColor: const Color(0xFF6366F1),
                  backgroundColor: const Color(0xFF0F0F13),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedActionType = type);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Modifiers (for Hotkey type) ────────────────────────────────
            if (_selectedActionType == ActionType.hotkey) ...[
              Text(
                'MODIFIERS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['PRIMARY_MOD', 'ALT', 'CTRL', 'SHIFT'].map((mod) {
                  final isSelected = _selectedModifiers.contains(mod);
                  return FilterChip(
                    label: Text(mod == 'PRIMARY_MOD' ? 'Cmd/Ctrl' : mod),
                    selected: isSelected,
                    selectedColor: const Color(0xFF6366F1),
                    backgroundColor: const Color(0xFF0F0F13),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                    onSelected: (_) => _toggleModifier(mod),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _keyController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Key (e.g. C, V, Enter, Tab, F1)',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFF0F0F13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              TextField(
                controller: _payloadController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: _selectedActionType == ActionType.media
                      ? 'Media Action (e.g. PLAY_PAUSE, NEXT, MUTE)'
                      : 'Shell Command (e.g. open -a "Visual Studio Code")',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFF0F0F13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Background Color Palette ───────────────────────────────────
            Text(
              'BACKGROUND COLOR',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: TileColors.palette.length,
                itemBuilder: (context, i) {
                  final color = TileColors.palette[i];
                  final hex = TileColors.toHex(color);
                  final isSelected = _selectedColorHex.toLowerCase() == hex.toLowerCase();
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColorHex = hex),
                    child: Container(
                      width: 38,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Icon Selector ──────────────────────────────────────────────
            Text(
              'TILE ICON',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _availableIcons.length,
                itemBuilder: (context, i) {
                  final iconName = _availableIcons[i];
                  final isSelected = _selectedIcon == iconName;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = iconName),
                    child: Container(
                      width: 48,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF0F0F13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getIconData(iconName),
                        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // ── Save Button ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final updated = widget.tile.copyWith(
                    label: _labelController.text,
                    colorHex: _selectedColorHex,
                    iconName: _selectedIcon,
                    actionType: _selectedActionType,
                    modifiers: _selectedModifiers,
                    key: _keyController.text,
                    payload: _payloadController.text,
                  );
                  widget.onSave(updated);
                  Navigator.pop(context);
                },
                child: Text(
                  'Save Macro Tile',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
