import '../core/protocol/schema.dart';
import 'deck_tile.dart';

/// Represents a Macro Profile (e.g., Default, Coding, Streaming, Gaming)
class DeckProfile {
  final String id;
  final String name;
  final String targetApp; // e.g. "default", "com.microsoft.VSCode", "com.obsproject.Studio"
  final int columns;
  final List<DeckTile> tiles;

  DeckProfile({
    required this.id,
    required this.name,
    this.targetApp = 'default',
    this.columns = 3,
    required this.tiles,
  });

  DeckProfile copyWith({
    String? id,
    String? name,
    String? targetApp,
    int? columns,
    List<DeckTile>? tiles,
  }) {
    return DeckProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      targetApp: targetApp ?? this.targetApp,
      columns: columns ?? this.columns,
      tiles: tiles ?? this.tiles,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'targetApp': targetApp,
      'columns': columns,
      'tiles': tiles.map((t) => t.toMap()).toList(),
    };
  }

  factory DeckProfile.fromMap(Map<String, dynamic> map) {
    return DeckProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      targetApp: map['targetApp'] as String? ?? 'default',
      columns: map['columns'] as int? ?? 3,
      tiles: (map['tiles'] as List? ?? [])
          .map((t) => DeckTile.fromMap(Map<String, dynamic>.from(t as Map)))
          .toList(),
    );
  }

  /// Default Starter Profiles
  static List<DeckProfile> get defaultProfiles => [
        DeckProfile(
          id: 'profile_default',
          name: 'General',
          targetApp: 'default',
          columns: 3,
          tiles: [
            DeckTile(id: 't1', label: 'Copy', iconName: 'content_copy', colorHex: '#6366F1', actionType: ActionType.hotkey, modifiers: ['PRIMARY_MOD'], key: 'C'),
            DeckTile(id: 't2', label: 'Paste', iconName: 'content_paste', colorHex: '#8B5CF6', actionType: ActionType.hotkey, modifiers: ['PRIMARY_MOD'], key: 'V'),
            DeckTile(id: 't3', label: 'VS Code', iconName: 'code', colorHex: '#3B82F6', actionType: ActionType.shell, payload: 'open -a "Visual Studio Code"'),
            DeckTile(id: 't4', label: 'Play / Pause', iconName: 'play_arrow', colorHex: '#10B981', actionType: ActionType.media, payload: 'PLAY_PAUSE'),
            DeckTile(id: 't5', label: 'Skip Next', iconName: 'skip_next', colorHex: '#06B6D4', actionType: ActionType.media, payload: 'NEXT'),
            DeckTile(id: 't6', label: 'Mute Audio', iconName: 'volume_off', colorHex: '#EF4444', actionType: ActionType.media, payload: 'MUTE'),
            DeckTile(id: 't7', label: 'Terminal', iconName: 'terminal', colorHex: '#F97316', actionType: ActionType.shell, payload: 'open -a Terminal'),
            DeckTile(id: 't8', label: 'Mute Mic', iconName: 'mic_off', colorHex: '#EC4899', actionType: ActionType.hotkey, modifiers: ['PRIMARY_MOD', 'SHIFT'], key: 'M'),
            DeckTile(id: 't9', label: 'Stream OBS', iconName: 'videocam', colorHex: '#F59E0B', actionType: ActionType.shell, payload: 'obs --startstreaming'),
          ],
        ),
        DeckProfile(
          id: 'profile_dev',
          name: 'Developer',
          targetApp: 'com.microsoft.VSCode',
          columns: 3,
          tiles: [
            DeckTile(id: 'dev_1', label: 'Run Build', iconName: 'terminal', colorHex: '#3B82F6', actionType: ActionType.hotkey, modifiers: ['PRIMARY_MOD', 'SHIFT'], key: 'B'),
            DeckTile(id: 'dev_2', label: 'Toggle Terminal', iconName: 'code', colorHex: '#6366F1', actionType: ActionType.hotkey, modifiers: ['PRIMARY_MOD'], key: '`'),
            DeckTile(id: 'dev_3', label: 'Format Code', iconName: 'settings', colorHex: '#8B5CF6', actionType: ActionType.hotkey, modifiers: ['PRIMARY_MOD', 'ALT'], key: 'L'),
            DeckTile(id: 'dev_4', label: 'Git Status', iconName: 'terminal', colorHex: '#10B981', actionType: ActionType.shell, payload: 'git status'),
            DeckTile(id: 'dev_5', label: 'Git Pull', iconName: 'terminal', colorHex: '#06B6D4', actionType: ActionType.shell, payload: 'git pull'),
            DeckTile(id: 'dev_6', label: 'Git Push', iconName: 'terminal', colorHex: '#F97316', actionType: ActionType.shell, payload: 'git push'),
          ],
        ),
      ];
}
