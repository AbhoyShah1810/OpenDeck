import 'package:flutter/material.dart';
import '../core/protocol/schema.dart';

/// Preset Tile Color Palette
class TileColors {
  static const List<Color> palette = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFFEF4444), // Red
    Color(0xFFF97316), // Orange
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Emerald
    Color(0xFF06B6D4), // Cyan
    Color(0xFF3B82F6), // Blue
    Color(0xFF64748B), // Slate
  ];

  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  static String toHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }
}

/// Represents an individual macro tile on the OpenDeck grid
class DeckTile {
  final String id;
  final String label;
  final String iconName;
  final String colorHex;
  final ActionType actionType;
  final List<String> modifiers;
  final String key;
  final String payload;
  final int sequenceDelayMs;

  DeckTile({
    required this.id,
    required this.label,
    this.iconName = 'sports_esports',
    this.colorHex = '#6366F1',
    this.actionType = ActionType.hotkey,
    this.modifiers = const ['PRIMARY_MOD'],
    this.key = 'C',
    this.payload = '',
    this.sequenceDelayMs = 0,
  });

  Color get color => TileColors.fromHex(colorHex);

  DeckTile copyWith({
    String? id,
    String? label,
    String? iconName,
    String? colorHex,
    ActionType? actionType,
    List<String>? modifiers,
    String? key,
    String? payload,
    int? sequenceDelayMs,
  }) {
    return DeckTile(
      id: id ?? this.id,
      label: label ?? this.label,
      iconName: iconName ?? this.iconName,
      colorHex: colorHex ?? this.colorHex,
      actionType: actionType ?? this.actionType,
      modifiers: modifiers ?? this.modifiers,
      key: key ?? this.key,
      payload: payload ?? this.payload,
      sequenceDelayMs: sequenceDelayMs ?? this.sequenceDelayMs,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'iconName': iconName,
      'colorHex': colorHex,
      'actionType': actionType.toValue(),
      'modifiers': modifiers,
      'key': key,
      'payload': payload,
      'sequenceDelayMs': sequenceDelayMs,
    };
  }

  factory DeckTile.fromMap(Map<String, dynamic> map) {
    return DeckTile(
      id: map['id'] as String,
      label: map['label'] as String,
      iconName: map['iconName'] as String? ?? 'sports_esports',
      colorHex: map['colorHex'] as String? ?? '#6366F1',
      actionType: ActionTypeExtension.fromValue(map['actionType'] as String? ?? 'HOTKEY'),
      modifiers: List<String>.from(map['modifiers'] ?? []),
      key: map['key'] as String? ?? '',
      payload: map['payload'] as String? ?? '',
      sequenceDelayMs: map['sequenceDelayMs'] as int? ?? 0,
    );
  }

  ActionPayload toActionPayload() {
    return ActionPayload(
      id: id,
      actionType: actionType,
      modifiers: modifiers,
      key: key,
      payload: payload,
      sequenceDelayMs: sequenceDelayMs,
    );
  }
}
