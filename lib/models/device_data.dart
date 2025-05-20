class DeviceData {
  final String deviceId;
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
    required this.voltage,
    required this.current1,
    required this.current2,
    required this.energy1,
    required this.energy2,
    required this.relay1Status,
    required this.relay2Status,
    required this.timestamp,
  });

  factory DeviceData.fromJson(Map<String, dynamic> json) {
    return DeviceData(
      deviceId: json['deviceId'] as String,
      voltage: (json['voltage'] as num).toDouble(),
      current1: (json['current1'] as num).toDouble(),
      current2: (json['current2'] as num).toDouble(),
      energy1: (json['energy1'] as num).toDouble(),
      energy2: (json['energy2'] as num).toDouble(),
      relay1Status: json['relay1Status'] as bool,
      relay2Status: json['relay2Status'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  DeviceData copyWith({
    String? deviceId,
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

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'voltage': voltage,
      'current1': current1,
      'current2': current2,
      'energy1': energy1,
      'energy2': energy2,
      'relay1Status': relay1Status,
      'relay2Status': relay2Status,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
