class DeviceData {
  final String deviceId;
  final String maisonId;
  final double voltage;
  final double current1;
  final double current2;
  final double energy1;
  final double energy2;
  final bool relay1Status;
  final bool relay2Status;
  final DateTime timestamp;

  DeviceData({
    required this.deviceId,
    required this.maisonId,
    required this.voltage,
    required this.current1,
    required this.current2,
    required this.energy1,
    required this.energy2,
    required this.relay1Status,
    required this.relay2Status,
    required this.timestamp,
  });

  DeviceData copyWith({
    String? deviceId,
    String? maisonId,
    double? voltage,
    double? current1,
    double? current2,
    double? energy1,
    double? energy2,
    bool? relay1Status,
    bool? relay2Status,
    DateTime? timestamp,
  }) {
    return DeviceData(
      deviceId: deviceId ?? this.deviceId,
      maisonId: maisonId ?? this.maisonId,
      voltage: voltage ?? this.voltage,
      current1: current1 ?? this.current1,
      current2: current2 ?? this.current2,
      energy1: energy1 ?? this.energy1,
      energy2: energy2 ?? this.energy2,
      relay1Status: relay1Status ?? this.relay1Status,
      relay2Status: relay2Status ?? this.relay2Status,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  factory DeviceData.fromJson(Map<String, dynamic> json) {
    return DeviceData(
      deviceId: json['device_id'] as String,
      maisonId: json['maison_id'] as String,
      voltage: (json['voltage'] as num).toDouble(),
      current1: (json['current1'] as num).toDouble(),
      current2: (json['current2'] as num).toDouble(),
      energy1: (json['energy1'] as num).toDouble(),
      energy2: (json['energy2'] as num).toDouble(),
      relay1Status: json['relay1_status'] as bool,
      relay2Status: json['relay2_status'] as bool,
      timestamp:
          json['timestamp'] is String
              ? DateTime.parse(json['timestamp'] as String)
              : json['timestamp'] as DateTime, // Gère les deux formats
    );
  }
}
