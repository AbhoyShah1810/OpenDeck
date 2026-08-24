import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/schema.dart';

void main() {
  group('MessagePack Protocol Tests', () {
    test('ActionPayload serialization and deserialization', () {
      final action = ActionPayload(
        id: 'btn_test_1',
        actionType: ActionType.hotkey,
        modifiers: ['PRIMARY_MOD', 'ALT'],
        key: '2',
        payload: '',
        sequenceDelayMs: 0,
      );

      final bytes = action.serialize();
      expect(bytes.length, lessThan(100));

      final deserialized = ActionPayload.deserialize(bytes);
      expect(deserialized.id, equals(action.id));
      expect(deserialized.actionType, equals(action.actionType));
      expect(deserialized.modifiers, equals(action.modifiers));
      expect(deserialized.key, equals(action.key));
      expect(deserialized.payload, equals(action.payload));
      expect(deserialized.sequenceDelayMs, equals(action.sequenceDelayMs));
    });

    test('TelemetryPayload serialization and deserialization', () {
      final telemetry = TelemetryPayload(
        status: 'READY',
        activeApp: 'com.microsoft.VSCode',
        metrics: SystemMetrics(
          cpu: 14.2,
          ram: 58.6,
          micMuted: false,
          audioPlaying: true,
        ),
      );

      final bytes = telemetry.serialize();
      final deserialized = TelemetryPayload.deserialize(bytes);

      expect(deserialized.status, equals(telemetry.status));
      expect(deserialized.activeApp, equals(telemetry.activeApp));
      expect(deserialized.metrics.cpu, equals(telemetry.metrics.cpu));
      expect(deserialized.metrics.ram, equals(telemetry.metrics.ram));
      expect(deserialized.metrics.micMuted, equals(telemetry.metrics.micMuted));
      expect(deserialized.metrics.audioPlaying, equals(telemetry.metrics.audioPlaying));
    });
  });
}
