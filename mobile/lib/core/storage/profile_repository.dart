import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/deck_profile.dart';

/// Repository for persistent Hive NoSQL CRUD operations on macro profiles
class ProfileRepository {
  static const String _boxName = 'opendeck_profiles';
  static const String _activeProfileKey = '_active_profile_id_';

  Box? _box;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);

    // Seed initial default profiles if box is empty
    if (_box!.isEmpty) {
      for (final profile in DeckProfile.defaultProfiles) {
        await saveProfile(profile);
      }
      await setActiveProfileId(DeckProfile.defaultProfiles.first.id);
    }
  }

  List<DeckProfile> getAllProfiles() {
    if (_box == null) return DeckProfile.defaultProfiles;
    final list = <DeckProfile>[];
    for (final key in _box!.keys) {
      if (key == _activeProfileKey) continue;
      final raw = _box!.get(key);
      if (raw != null) {
        try {
          final map = jsonDecode(raw as String);
          list.add(DeckProfile.fromMap(Map<String, dynamic>.from(map)));
        } catch (_) {}
      }
    }
    return list.isEmpty ? DeckProfile.defaultProfiles : list;
  }

  DeckProfile? getProfileById(String id) {
    if (_box == null) return null;
    final raw = _box!.get(id);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw as String);
      return DeckProfile.fromMap(Map<String, dynamic>.from(map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(DeckProfile profile) async {
    if (_box == null) return;
    final jsonStr = jsonEncode(profile.toMap());
    await _box!.put(profile.id, jsonStr);
  }

  Future<void> deleteProfile(String id) async {
    if (_box == null) return;
    await _box!.delete(id);
  }

  String getActiveProfileId() {
    if (_box == null) return 'profile_default';
    return _box!.get(_activeProfileKey, defaultValue: 'profile_default') as String;
  }

  Future<void> setActiveProfileId(String id) async {
    if (_box == null) return;
    await _box!.put(_activeProfileKey, id);
  }

  /// Matches target application bundle ID / window title for auto profile switching
  DeckProfile? getProfileForApp(String activeApp) {
    if (activeApp.isEmpty) return null;
    final cleanApp = activeApp.toLowerCase();
    final profiles = getAllProfiles();

    for (final p in profiles) {
      if (p.targetApp.isEmpty || p.targetApp == 'default') continue;
      final target = p.targetApp.toLowerCase();
      if (cleanApp.contains(target) || target.contains(cleanApp)) {
        return p;
      }
    }
    return null;
  }
}
