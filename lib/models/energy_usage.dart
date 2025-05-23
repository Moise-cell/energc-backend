class EnergyUsage {
  final String id;
  final String maisonId;
  final double energyConsumed;
  final DateTime timestamp;
  final String? deviceId;
  final String? deviceType;

  EnergyUsage({
    required this.id,
    required this.maisonId,
    required this.energyConsumed,
    required this.timestamp,
    this.deviceId,
    this.deviceType,
  });

  factory EnergyUsage.fromJson(Map<String, dynamic> json) {
    return EnergyUsage(
      id: json['id'] as String,
      maisonId: json['maison_id'] as String,
      energyConsumed: (json['energy_consumed'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      deviceId: json['device_id'] as String?,
      deviceType: json['device_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'maison_id': maisonId,
      'energy_consumed': energyConsumed,
      'timestamp': timestamp.toIso8601String(),
      'device_id': deviceId,
      'device_type': deviceType,
    };
  }

  EnergyUsage copyWith({
    String? id,
    String? maisonId,
    double? energyConsumed,
    DateTime? timestamp,
    String? deviceId,
    String? deviceType,
  }) {
    return EnergyUsage(
      id: id ?? this.id,
      maisonId: maisonId ?? this.maisonId,
      energyConsumed: energyConsumed ?? this.energyConsumed,
      timestamp: timestamp ?? this.timestamp,
      deviceId: deviceId ?? this.deviceId,
      deviceType: deviceType ?? this.deviceType,
    );
  }
} 