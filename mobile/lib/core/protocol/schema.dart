import 'dart:typed_data';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

/// Action Types supported by OpenDeck
enum ActionType {
  hotkey,
  shell,
  media,
  obsAction,
  multiAction,
}

extension ActionTypeExtension on ActionType {
  String toValue() {
    switch (this) {
      case ActionType.hotkey:
        return 'HOTKEY';
      case ActionType.shell:
        return 'SHELL';
      case ActionType.media:
        return 'MEDIA';
      case ActionType.obsAction:
        return 'OBS_ACTION';
      case ActionType.multiAction:
        return 'MULTI_ACTION';
    }
  }

  static ActionType fromValue(String value) {
    switch (value) {
      case 'HOTKEY':
        return ActionType.hotkey;
      case 'SHELL':
        return ActionType.shell;
      case 'MEDIA':
        return ActionType.media;
      case 'OBS_ACTION':
        return ActionType.obsAction;
      case 'MULTI_ACTION':
        return ActionType.multiAction;
      default:
        return ActionType.hotkey;
    }
  }
}

/// Command Action Payload (Phone -> Desktop over Command Characteristic)
class ActionPayload {
  final String id;
  final ActionType actionType;
  final List<String> modifiers;
  final String key;
  final String payload;
  final int sequenceDelayMs;

  ActionPayload({
    required this.id,
    required this.actionType,
    required this.modifiers,
    required this.key,
    required this.payload,
    required this.sequenceDelayMs,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'actionType': actionType.toValue(),
      'modifiers': modifiers,
      'key': key,
      'payload': payload,
      'sequenceDelayMs': sequenceDelayMs,
    };
  }

  factory ActionPayload.fromMap(Map<String, dynamic> map) {
    return ActionPayload(
      id: map['id'] as String,
      actionType: ActionTypeExtension.fromValue(map['actionType'] as String),
      modifiers: List<String>.from(map['modifiers'] ?? []),
      key: map['key'] as String,
      payload: map['payload'] as String,
      sequenceDelayMs: map['sequenceDelayMs'] as int,
    );
  }

  Uint8List serialize() {
    return msgpack.serialize(toMap());
  }

  factory ActionPayload.deserialize(Uint8List bytes) {
    final map = msgpack.deserialize(bytes) as Map<dynamic, dynamic>;
    return ActionPayload.fromMap(Map<String, dynamic>.from(map));
  }
}

/// System Metrics snapshot
class SystemMetrics {
  final double cpu;
  final double ram;
  final bool micMuted;
  final bool audioPlaying;

  SystemMetrics({
    required this.cpu,
    required this.ram,
    required this.micMuted,
    required this.audioPlaying,
  });

  Map<String, dynamic> toMap() {
    return {
      'cpu': cpu,
      'ram': ram,
      'micMuted': micMuted,
      'audioPlaying': audioPlaying,
    };
  }

  factory SystemMetrics.fromMap(Map<String, dynamic> map) {
    return SystemMetrics(
      cpu: (map['cpu'] as num).toDouble(),
      ram: (map['ram'] as num).toDouble(),
      micMuted: map['micMuted'] as bool,
      audioPlaying: map['audioPlaying'] as bool,
    );
  }
}

/// Telemetry Payload (Desktop -> Phone over Telemetry Characteristic)
class TelemetryPayload {
  final String status;
  final String activeApp;
  final SystemMetrics metrics;

  TelemetryPayload({
    required this.status,
    required this.activeApp,
    required this.metrics,
  });

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'activeApp': activeApp,
      'metrics': metrics.toMap(),
    };
  }

  factory TelemetryPayload.fromMap(Map<String, dynamic> map) {
    return TelemetryPayload(
      status: map['status'] as String,
      activeApp: map['activeApp'] as String,
      metrics: SystemMetrics.fromMap(Map<String, dynamic>.from(map['metrics'] as Map)),
    );
  }

  Uint8List serialize() {
    return msgpack.serialize(toMap());
  }

  factory TelemetryPayload.deserialize(Uint8List bytes) {
    final map = msgpack.deserialize(bytes) as Map<dynamic, dynamic>;
    return TelemetryPayload.fromMap(Map<String, dynamic>.from(map));
  }
}

/// Handshake & Pairing Payload (Bidirectional over Auth Characteristic)
class HandshakePayload {
  final String clientId;
  final String clientPublicKey;
  final String authCode;

  HandshakePayload({
    required this.clientId,
    required this.clientPublicKey,
    required this.authCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'clientId': clientId,
      'clientPublicKey': clientPublicKey,
      'authCode': authCode,
    };
  }

  factory HandshakePayload.fromMap(Map<String, dynamic> map) {
    return HandshakePayload(
      clientId: map['clientId'] as String,
      clientPublicKey: map['clientPublicKey'] as String,
      authCode: map['authCode'] as String,
    );
  }

  Uint8List serialize() {
    return msgpack.serialize(toMap());
  }

  factory HandshakePayload.deserialize(Uint8List bytes) {
    final map = msgpack.deserialize(bytes) as Map<dynamic, dynamic>;
    return HandshakePayload.fromMap(Map<String, dynamic>.from(map));
  }
}
