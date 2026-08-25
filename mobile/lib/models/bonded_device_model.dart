/// Bonded Desktop Computer model stored locally on mobile device
class BondedDeviceModel {
  final String deviceId;
  final String name;
  final String secretKey;
  final DateTime pairedAt;

  BondedDeviceModel({
    required this.deviceId,
    required this.name,
    required this.secretKey,
    required this.pairedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'name': name,
      'secretKey': secretKey,
      'pairedAt': pairedAt.millisecondsSinceEpoch,
    };
  }

  factory BondedDeviceModel.fromMap(Map<String, dynamic> map) {
    return BondedDeviceModel(
      deviceId: map['deviceId'] as String,
      name: map['name'] as String,
      secretKey: map['secretKey'] as String,
      pairedAt: DateTime.fromMillisecondsSinceEpoch(map['pairedAt'] as int),
    );
  }
}
