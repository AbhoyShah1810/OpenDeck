import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_manager.dart';
import '../storage/bonded_repository.dart';

/// Auto-Reconnect Service for OpenDeck
///
/// Manages zero-friction startup and foreground reconnection to a previously
/// bonded desktop peripheral. The service:
///
///  1. On [tryAutoConnect]: looks up the most recently bonded device UUID
///     from persistent storage, then initiates a direct connection bypassing
///     BLE scan entirely (< 500 ms to GATT Ready on cached entries).
///
///  2. On [onAppForegrounded]: called by the UI's WidgetsBindingObserver
///     whenever the app resumes from background. Silently reconnects if the
///     link was dropped while suspended.
///
///  3. Emits [reconnectEvent] stream events so the UI can show toast messages
///     only when reconnection either succeeds or exhausts retries.
class AutoReconnectService {
  final BleManager bleManager;
  final BondedRepository bondedRepo;

  // Event stream for UI-level notifications (success / failure)
  final _eventController =
      StreamController<AutoReconnectEvent>.broadcast();

  Stream<AutoReconnectEvent> get reconnectEvents => _eventController.stream;

  // Prevent parallel auto-connect attempts
  bool _isAttempting = false;

  AutoReconnectService({
    required this.bleManager,
    required this.bondedRepo,
  });

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Call this on app startup (once Bluetooth is ready).
  /// Retrieves the most-recently bonded device UUID and connects directly to it.
  /// Returns true if a bonded device was found and connection succeeded.
  Future<bool> tryAutoConnect() async {
    if (_isAttempting) return false;
    if (bleManager.status == BleConnectionStatus.ready) return true;

    // Wait for Bluetooth to be powered on (up to 3 s)
    final btReady = await _waitForBluetooth(timeout: const Duration(seconds: 3));
    if (!btReady) {
      _emit(AutoReconnectEvent.bluetoothUnavailable);
      return false;
    }

    // Find the most recently bonded device
    final devices = bondedRepo.getBondedDevices();
    if (devices.isEmpty) return false;

    // Sort by most recently paired — last entry wins
    devices.sort((a, b) => b.pairedAt.compareTo(a.pairedAt));
    final target = devices.first;

    debugPrint('[AutoReconnect] Attempting direct connect to ${target.deviceId}');
    _isAttempting = true;
    _emit(AutoReconnectEvent.attempting(target.deviceId, target.name));

    final success = await bleManager.connectByDeviceId(target.deviceId);
    _isAttempting = false;

    if (success) {
      debugPrint('[AutoReconnect] ✅ Connected to ${target.name}');
      _emit(AutoReconnectEvent.connected(target.name));
    } else {
      debugPrint('[AutoReconnect] ❌ Direct connect failed — BLE engine will retry');
      // The BleManager's internal reconnect engine takes over from here
    }

    return success;
  }

  /// Call this when the app is foregrounded (AppLifecycleState.resumed).
  /// Only triggers if the BLE link was dropped; no-ops if already Ready.
  Future<void> onAppForegrounded() async {
    if (_isAttempting) return;
    if (bleManager.status == BleConnectionStatus.ready) return;
    if (bleManager.status == BleConnectionStatus.reconnecting) return;

    // If the BleManager already has a saved device ID (from a prior session
    // in the same process), its internal engine will reconnect automatically.
    // We only need to kick off an explicit attempt if there is no saved ID.
    if (bleManager.savedDeviceId != null) return;

    // Cross-process foreground: look up from DB and start fresh
    await tryAutoConnect();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  /// Polls FlutterBluePlus adapter state until Bluetooth is powered on or
  /// the [timeout] elapses.
  Future<bool> _waitForBluetooth({required Duration timeout}) async {
    // Immediately available
    if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on) {
      return true;
    }

    final completer = Completer<bool>();
    Timer? timer;
    StreamSubscription<BluetoothAdapterState>? sub;

    timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    sub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  void _emit(AutoReconnectEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }

  void dispose() {
    _eventController.close();
  }
}

// ── Event types ──────────────────────────────────────────────────────────────

enum AutoReconnectEventType {
  attempting,
  connected,
  failed,
  bluetoothUnavailable,
}

class AutoReconnectEvent {
  final AutoReconnectEventType type;
  final String? deviceId;
  final String? deviceName;

  const AutoReconnectEvent._({
    required this.type,
    this.deviceId,
    this.deviceName,
  });

  factory AutoReconnectEvent.attempting(String deviceId, String name) =>
      AutoReconnectEvent._(
        type: AutoReconnectEventType.attempting,
        deviceId: deviceId,
        deviceName: name,
      );

  factory AutoReconnectEvent.connected(String name) =>
      AutoReconnectEvent._(
        type: AutoReconnectEventType.connected,
        deviceName: name,
      );

  factory AutoReconnectEvent.failed(String? deviceId) =>
      AutoReconnectEvent._(
        type: AutoReconnectEventType.failed,
        deviceId: deviceId,
      );

  static const AutoReconnectEvent bluetoothUnavailable =
      AutoReconnectEvent._(type: AutoReconnectEventType.bluetoothUnavailable);
}
