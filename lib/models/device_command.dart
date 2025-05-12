class DeviceCommand {
  final int? id;
  final String deviceId;
  final String commandType;
  final Map<String, dynamic> parameters;
  final DateTime timestamp;
  final bool executed;

  DeviceCommand({
    this.id,
    required this.deviceId,
    required this.commandType,
    required this.parameters,
    required this.timestamp,
    this.executed = false,
  });

  factory DeviceCommand.fromJson(Map<String, dynamic> json) {
    return DeviceCommand(
      id: json['id'],
      deviceId: json['device_id'],
      commandType: json['command_type'],
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
      timestamp: DateTime.parse(json['timestamp']),
      executed: json['executed'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'command_type': commandType,
      'parameters': parameters,
      'timestamp': timestamp.toIso8601String(),
      'executed': executed,
    };
  }

  // Commandes spécifiques
  static DeviceCommand relayControl({
    required String deviceId,
    required int relayNumber,
    required bool status,
  }) {
    return DeviceCommand(
      deviceId: deviceId,
      commandType: 'relay_control',
      parameters: {
        'relay_number': relayNumber,
        'status': status,
      },
      timestamp: DateTime.now(),
    );
  }

  static DeviceCommand displayMessage({
    required String deviceId,
    required String message,
    int line = 0,
  }) {
    return DeviceCommand(
      deviceId: deviceId,
      commandType: 'display_message',
      parameters: {
        'message': message,
        'line': line,
      },
      timestamp: DateTime.now(),
    );
  }

  static DeviceCommand requestData({
    required String deviceId,
  }) {
    return DeviceCommand(
      deviceId: deviceId,
      commandType: 'request_data',
      parameters: {},
      timestamp: DateTime.now(),
    );
  }
}
