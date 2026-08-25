import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../protocol/schema.dart';

/// BLE UUID Constants matching desktop peripheral
class BleUuids {
  static const String service = '13370001-dead-beef-feed-cafe00000001';
  static const String command = '13370002-dead-beef-feed-cafe00000001';
  static const String telemetry = '13370003-dead-beef-feed-cafe00000001';
  static const String auth = '13370004-dead-beef-feed-cafe00000001';

  static Guid get serviceGuid => Guid(service);
  static Guid get commandGuid => Guid(command);
  static Guid get telemetryGuid => Guid(telemetry);
  static Guid get authGuid => Guid(auth);
}

/// Connection Status State Machine for Mobile Client (5 explicit states)
enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,
  pairing,
  ready,
  // Transient state shown during silent background reconnect attempts
  reconnecting,
}

extension BleConnectionStatusExtension on BleConnectionStatus {
  String get label {
    switch (this) {
      case BleConnectionStatus.disconnected:
        return 'Disconnected';
      case BleConnectionStatus.scanning:
        return 'Scanning...';
      case BleConnectionStatus.connecting:
        return 'Connecting...';
      case BleConnectionStatus.pairing:
        return 'Pairing...';
      case BleConnectionStatus.ready:
        return 'Ready';
      case BleConnectionStatus.reconnecting:
        return 'Reconnecting...';
    }
  }
}

/// Low-Latency BLE Central Connection Manager for OpenDeck
///
/// Lifecycle:
///   DISCONNECTED → CONNECTING → PAIRING → READY
///   READY → [link drop] → RECONNECTING → CONNECTING → READY
class BleManager {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _telemetryCharacteristic;
  BluetoothCharacteristic? _authCharacteristic;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _telemetryNotificationSubscription;

  // ── Heartbeat state ─────────────────────────────────────────────────────────
  Timer? _heartbeatTimer;
  int _heartbeatFailures = 0;
  static const int _maxHeartbeatFailures = 3;

  // ── Reconnect state ─────────────────────────────────────────────────────────
  // Saved after every successful connection so drops can reconnect directly.
  String? _savedDeviceId;
  bool _reconnectEnabled = false;
  bool _isReconnecting = false;
  Timer? _reconnectBackoffTimer;
  static const Duration _reconnectInitialDelay = Duration(seconds: 2);
  static const Duration _reconnectMaxDelay = Duration(seconds: 30);
  Duration _reconnectDelay = _reconnectInitialDelay;

  // ── Stream controllers ──────────────────────────────────────────────────────
  final _statusController = StreamController<BleConnectionStatus>.broadcast();
  final _telemetryController = StreamController<TelemetryPayload>.broadcast();

  BleConnectionStatus _currentStatus = BleConnectionStatus.disconnected;

  BleConnectionStatus get status => _currentStatus;
  Stream<BleConnectionStatus> get statusStream => _statusController.stream;
  Stream<TelemetryPayload> get telemetryStream => _telemetryController.stream;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// The remote device ID of the most recently connected peripheral.
  String? get savedDeviceId => _savedDeviceId;

  void _updateStatus(BleConnectionStatus newStatus) {
    _currentStatus = newStatus;
    _statusController.add(newStatus);
  }

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Scan for OpenDeck peripheral servers in physical range
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
    required Function(BluetoothDevice device, String name) onDeviceDiscovered,
  }) async {
    _updateStatus(BleConnectionStatus.scanning);

    // Stop any active scan
    await FlutterBluePlus.stopScan();

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : (r.device.platformName.isNotEmpty ? r.device.platformName : 'OpenDeck Host');

        if (r.advertisementData.serviceUuids.contains(BleUuids.serviceGuid) ||
            name.toLowerCase().contains('opendeck')) {
          onDeviceDiscovered(r.device, name);
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [BleUuids.serviceGuid],
      timeout: timeout,
    );
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    if (_currentStatus == BleConnectionStatus.scanning) {
      _updateStatus(BleConnectionStatus.disconnected);
    }
  }

  /// Connect to OpenDeck peripheral with sub-15ms latency optimizations.
  /// Saves [device.remoteId] for future direct reconnects.
  Future<bool> connect(BluetoothDevice device, {bool enableReconnect = true}) async {
    try {
      _updateStatus(BleConnectionStatus.connecting);
      _connectedDevice = device;
      _reconnectEnabled = enableReconnect;
      if (enableReconnect) _savedDeviceId = device.remoteId.str;

      // Listen for connection state changes
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnected();
        }
      });

      // Connect with autoConnect false for immediate connection
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _updateStatus(BleConnectionStatus.pairing);

      // ── Optimization 1: High Priority Connection Interval (Android) ─────
      if (Platform.isAndroid) {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      }

      // ── Optimization 2: Negotiate MTU >= 185 bytes for single packet tx ─
      if (Platform.isAndroid) {
        await device.requestMtu(247);
      }

      // ── Optimization 3: Service & Characteristic Discovery ──────────────
      final services = await device.discoverServices();
      final targetService = services.firstWhere(
        (s) => s.uuid == BleUuids.serviceGuid,
        orElse: () => throw Exception('OpenDeck Primary Service not found on target device'),
      );

      for (final c in targetService.characteristics) {
        if (c.uuid == BleUuids.commandGuid) {
          _commandCharacteristic = c;
        } else if (c.uuid == BleUuids.telemetryGuid) {
          _telemetryCharacteristic = c;
        } else if (c.uuid == BleUuids.authGuid) {
          _authCharacteristic = c;
        }
      }

      if (_commandCharacteristic == null) {
        throw Exception('Command Characteristic missing from OpenDeck service');
      }

      // ── Setup Telemetry Notifications if available ──────────────────────
      if (_telemetryCharacteristic != null) {
        await _telemetryCharacteristic!.setNotifyValue(true);
        _telemetryNotificationSubscription?.cancel();
        _telemetryNotificationSubscription =
            _telemetryCharacteristic!.onValueReceived.listen((value) {
          if (value.isNotEmpty) {
            try {
              final payload = TelemetryPayload.deserialize(Uint8List.fromList(value));
              _telemetryController.add(payload);
            } catch (_) {
              // Soft error on parse
            }
          }
        });
      }

      _updateStatus(BleConnectionStatus.ready);

      // Reset reconnect backoff on successful connect
      _reconnectDelay = _reconnectInitialDelay;
      _heartbeatFailures = 0;
      _isReconnecting = false;

      // Start the keep-alive heartbeat
      _startHeartbeat();

      return true;
    } catch (e) {
      _handleDisconnected();
      return false;
    }
  }

  /// Directly connect to a known peripheral by its Bluetooth MAC / UUID string.
  /// Bypasses BLE scanning entirely — used for startup auto-reconnect.
  Future<bool> connectByDeviceId(String deviceId) async {
    try {
      final device = BluetoothDevice.fromId(deviceId);
      return await connect(device, enableReconnect: true);
    } catch (e) {
      _updateStatus(BleConnectionStatus.disconnected);
      return false;
    }
  }

  /// Dispatch macro trigger with WriteWithoutResponse for sub-15ms latency
  Future<void> sendActionPayload(ActionPayload payload) async {
    if (_commandCharacteristic == null || _currentStatus != BleConnectionStatus.ready) {
      throw Exception('BLE Not connected to OpenDeck host');
    }

    final bytes = payload.serialize();

    // WriteWithoutResponse eliminates GATT network ACK round-trip delay
    await _commandCharacteristic!.write(
      bytes,
      withoutResponse: true,
    );
  }

  /// Dispatch pairing handshake over Auth characteristic
  Future<void> sendAuthPayload(HandshakePayload payload) async {
    if (_authCharacteristic == null) {
      throw Exception('Auth characteristic not available');
    }

    final bytes = payload.serialize();
    await _authCharacteristic!.write(
      bytes,
      withoutResponse: false, // Auth handshake requires acknowledgment
    );
  }

  /// Clean manual disconnect — suppresses auto-reconnect
  Future<void> disconnect() async {
    _reconnectEnabled = false;
    _stopHeartbeat();
    _reconnectBackoffTimer?.cancel();
    _isReconnecting = false;
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    _handleDisconnectedClean();
  }

  // ── Heartbeat engine ─────────────────────────────────────────────────────────

  /// Starts a 5-second periodic keep-alive ping written to the command
  /// characteristic. Three consecutive failures triggers a silent reconnect.
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_currentStatus != BleConnectionStatus.ready) return;
      if (_commandCharacteristic == null) return;

      try {
        // Zero-byte WriteWithoutResponse — negligible overhead, sub-1ms
        await _commandCharacteristic!.write(
          Uint8List(0),
          withoutResponse: true,
        );
        _heartbeatFailures = 0; // reset on success
      } catch (_) {
        _heartbeatFailures++;
        if (_heartbeatFailures >= _maxHeartbeatFailures) {
          // Link is dead — kick off reconnect
          _handleDisconnected();
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatFailures = 0;
  }

  // ── Reconnect engine ─────────────────────────────────────────────────────────

  /// Called on every unexpected disconnect. If [_reconnectEnabled] and
  /// [_savedDeviceId] are set, schedules a direct reconnect attempt using
  /// exponential backoff capped at 30 seconds.
  void _handleDisconnected() {
    _stopHeartbeat();
    _clearCharacteristics();

    if (_reconnectEnabled && _savedDeviceId != null && !_isReconnecting) {
      _isReconnecting = true;
      _updateStatus(BleConnectionStatus.reconnecting);
      _scheduleReconnect();
    } else {
      _connectedDevice = null;
      _updateStatus(BleConnectionStatus.disconnected);
    }
  }

  void _scheduleReconnect() {
    _reconnectBackoffTimer?.cancel();
    _reconnectBackoffTimer = Timer(_reconnectDelay, () async {
      if (!_reconnectEnabled || _savedDeviceId == null) {
        _isReconnecting = false;
        _connectedDevice = null;
        _updateStatus(BleConnectionStatus.disconnected);
        return;
      }

      final success = await connectByDeviceId(_savedDeviceId!);
      if (!success) {
        // Exponential backoff: double the delay up to max
        _reconnectDelay = Duration(
          seconds: (_reconnectDelay.inSeconds * 2).clamp(
            _reconnectInitialDelay.inSeconds,
            _reconnectMaxDelay.inSeconds,
          ),
        );
        _scheduleReconnect(); // retry again after new delay
      }
      // On success, connect() clears _isReconnecting and resets _reconnectDelay
    });
  }

  /// Called only on clean manual disconnect — does not trigger reconnect
  void _handleDisconnectedClean() {
    _clearCharacteristics();
    _connectedDevice = null;
    _updateStatus(BleConnectionStatus.disconnected);
  }

  void _clearCharacteristics() {
    _telemetryNotificationSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _commandCharacteristic = null;
    _telemetryCharacteristic = null;
    _authCharacteristic = null;
  }

  void dispose() {
    _stopHeartbeat();
    _reconnectBackoffTimer?.cancel();
    _reconnectEnabled = false;
    disconnect();
    _statusController.close();
    _telemetryController.close();
  }
}
