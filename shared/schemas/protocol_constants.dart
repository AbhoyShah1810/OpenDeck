/// OpenDeck Shared Protocol & BLE UUID Constants
abstract class BleUuid {
  /// OpenDeck Primary GATT Service UUID
  static const String service = '13370001-DEAD-BEEF-FEED-CAFE00000001';

  /// Command Characteristic UUID (WriteWithoutResponse: Phone -> Desktop)
  static const String command = '13370002-DEAD-BEEF-FEED-CAFE00000001';

  /// Telemetry Characteristic UUID (Notify / Read: Desktop -> Phone)
  static const String telemetry = '13370003-DEAD-BEEF-FEED-CAFE00000001';

  /// Auth & Pairing Characteristic UUID (Write / Read: Bidirectional PIN Handshake)
  static const String auth = '13370004-DEAD-BEEF-FEED-CAFE00000001';
}
