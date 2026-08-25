import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/bonded_device_model.dart';

/// Repository for persistent local storage of bonded desktop computer credentials
class BondedRepository {
  static const String _boxName = 'opendeck_bonded_devices';
  Box? _box;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  List<BondedDeviceModel> getBondedDevices() {
    if (_box == null) return [];
    final list = <BondedDeviceModel>[];
    for (final key in _box!.keys) {
      final raw = _box!.get(key);
      if (raw != null) {
        try {
          final map = jsonDecode(raw as String);
          list.add(BondedDeviceModel.fromMap(Map<String, dynamic>.from(map)));
        } catch (_) {}
      }
    }
    return list;
  }

  bool isBonded(String deviceId) {
    if (_box == null) return false;
    return _box!.containsKey(deviceId);
  }

  String? getSecret(String deviceId) {
    if (_box == null) return null;
    final raw = _box!.get(deviceId);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw as String);
      return map['secretKey'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBondedDevice(BondedDeviceModel device) async {
    if (_box == null) return;
    final jsonStr = jsonEncode(device.toMap());
    await _box!.put(device.deviceId, jsonStr);
  }

  Future<void> removeBondedDevice(String deviceId) async {
    if (_box == null) return;
    await _box!.delete(deviceId);
  }
}
