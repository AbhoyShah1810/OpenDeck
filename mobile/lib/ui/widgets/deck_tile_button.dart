import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/deck_tile.dart';

/// Single interactive macro tile button with scale animation and tactile haptics
class DeckTileButton extends StatefulWidget {
  final DeckTile tile;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const DeckTileButton({
    super.key,
    required this.tile,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<DeckTileButton> createState() => _DeckTileButtonState();
}

class _DeckTileButtonState extends State<DeckTileButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    // Tactile micro-haptic actuation feedback on touch-down
    HapticFeedback.lightImpact();
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    HapticFeedback.selectionClick();
    setState(() => _isPressed = false);
    widget.onTap();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  IconData _getIconData(String name) {
    switch (name.toLowerCase()) {
      case 'play_arrow':
        return Icons.play_arrow_rounded;
      case 'pause':
        return Icons.pause_rounded;
      case 'skip_next':
        return Icons.skip_next_rounded;
      case 'skip_previous':
        return Icons.skip_previous_rounded;
      case 'volume_off':
        return Icons.volume_off_rounded;
      case 'volume_up':
        return Icons.volume_up_rounded;
      case 'code':
        return Icons.code_rounded;
      case 'terminal':
        return Icons.terminal_rounded;
      case 'videocam':
        return Icons.videocam_rounded;
      case 'mic':
        return Icons.mic_rounded;
      case 'mic_off':
        return Icons.mic_off_rounded;
      case 'content_copy':
        return Icons.content_copy_rounded;
      case 'content_paste':
        return Icons.content_paste_rounded;
      case 'settings':
        return Icons.settings_rounded;
      default:
        return Icons.sports_esports_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.tile.color;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onLongPress();
      },
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 60),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: _isPressed ? baseColor.withValues(alpha: 0.8) : baseColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isPressed
                ? []
                : [
                    BoxShadow(
                      color: baseColor.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
            border: Border.all(
              color: Colors.white.withValues(alpha: _isPressed ? 0.4 : 0.15),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getIconData(widget.tile.iconName),
                size: 30,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  widget.tile.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
