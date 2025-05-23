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
    String getDeviceId() {
      final deviceId = json['deviceId'] ?? json['device_id'];
      if (deviceId == null) return 'esp32_maison1';
      return deviceId.toString();
    }

    return DeviceData(
      deviceId: getDeviceId(),
      voltage: _parseDouble(json['voltage']),
      current1: _parseDouble(json['current1']),
      current2: _parseDouble(json['current2']),
      energy1: _parseDouble(json['energy1']),
      energy2: _parseDouble(json['energy2']),
      relay1Status: json['relay1Status'] as bool? ?? json['relay1_status'] as bool? ?? false,
      relay2Status: json['relay2Status'] as bool? ?? json['relay2_status'] as bool? ?? false,
      timestamp: _parseDateTime(json['timestamp'] ?? json['created_at']),
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        return 0.0;
      }
    }
    return 0.0;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
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
