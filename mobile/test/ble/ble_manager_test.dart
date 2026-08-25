import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/ble/ble_manager.dart';
import 'package:mobile/core/protocol/schema.dart';

void main() {
  group('BleManager Protocol & UUID Tests', () {
    test('Verify BLE Service and Characteristic UUID Guids', () {
      expect(BleUuids.serviceGuid.toString(), BleUuids.service);
      expect(BleUuids.commandGuid.toString(), BleUuids.command);
      expect(BleUuids.telemetryGuid.toString(), BleUuids.telemetry);
      expect(BleUuids.authGuid.toString(), BleUuids.auth);
    });

    test('BleManager initial status is disconnected', () {
      final ble = BleManager();
      expect(ble.status, BleConnectionStatus.disconnected);
      expect(ble.connectedDevice, isNull);
    });

    test('Verify ActionPayload WriteWithoutResponse serialization length fits within MTU', () {
      final payload = ActionPayload(
        id: 'btn_grid_0_0',
        actionType: ActionType.hotkey,
        modifiers: ['PRIMARY_MOD', 'ALT'],
        key: 'c',
        payload: '',
        sequenceDelayMs: 0,
      );

      final bytes = payload.serialize();
      // Single BLE packet MTU constraint check (< 185 bytes)
      expect(bytes.length, lessThan(185));
    });
  });
}
