import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/schema.dart';
import 'package:mobile/models/bonded_device_model.dart';
import 'package:mobile/models/deck_profile.dart';
import 'package:mobile/models/deck_tile.dart';

void main() {
  group('DeckProfile & BondedDeviceModel Tests', () {
    test('DeckProfile roundtrip serialization to Map and back', () {
      final profile = DeckProfile(
        id: 'prof_test_1',
        name: 'Streaming',
        targetApp: 'com.obsproject.Studio',
        columns: 4,
        tiles: [
          DeckTile(
            id: 't_stream_1',
            label: 'Start Stream',
            actionType: ActionType.shell,
            payload: 'obs --startstreaming',
          ),
        ],
      );

      final map = profile.toMap();
      final restored = DeckProfile.fromMap(map);

      expect(restored.id, 'prof_test_1');
      expect(restored.name, 'Streaming');
      expect(restored.targetApp, 'com.obsproject.Studio');
      expect(restored.columns, 4);
      expect(restored.tiles.length, 1);
      expect(restored.tiles.first.label, 'Start Stream');
    });

    test('BondedDeviceModel serialization roundtrip', () {
      final device = BondedDeviceModel(
        deviceId: 'mac_m2_pro_01',
        name: 'Studio Mac Pro',
        secretKey: 'secret_pin_9876',
        pairedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final map = device.toMap();
      final restored = BondedDeviceModel.fromMap(map);

      expect(restored.deviceId, 'mac_m2_pro_01');
      expect(restored.name, 'Studio Mac Pro');
      expect(restored.secretKey, 'secret_pin_9876');
    });

    test('Default starter profiles loading', () {
      final presets = DeckProfile.defaultProfiles;
      expect(presets.length, greaterThanOrEqualTo(2));
      expect(presets.first.name, 'General');
      expect(presets.first.tiles.length, 9);
    });
  });
}
