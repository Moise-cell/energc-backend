class EnergyAlert {
  final String id;
  final String maisonId;
  final String type;
  final String message;
  final DateTime timestamp;
  final bool isRead;

  EnergyAlert({
    required this.id,
    required this.maisonId,
    required this.type,
    required this.message,
    required this.timestamp,
    this.isRead = false,
  });

  factory EnergyAlert.fromJson(Map<String, dynamic> json) {
    return EnergyAlert(
      id: json['id'] as String,
      maisonId: json['maison_id'] as String,
      type: json['type'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['is_read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'maison_id': maisonId,
      'type': type,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
    };
  }

  EnergyAlert copyWith({
    String? id,
    String? maisonId,
    String? type,
    String? message,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return EnergyAlert(
      id: id ?? this.id,
      maisonId: maisonId ?? this.maisonId,
      type: type ?? this.type,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }
} 