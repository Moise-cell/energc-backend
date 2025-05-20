import 'dart:convert';

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
    // Gérer les deux formats possibles (snake_case et camelCase)
    int? getId() {
      if (json.containsKey('id')) return json['id'] as int?;
      return null;
    }

    String getDeviceId() {
      if (json.containsKey('device_id')) return json['device_id'] as String;
      if (json.containsKey('deviceId')) return json['deviceId'] as String;
      throw FormatException('deviceId n\'a pas été trouvé dans JSON');
    }

    String getCommandType() {
      if (json.containsKey('command_type'))
        return json['command_type'] as String;
      if (json.containsKey('commandType')) return json['commandType'] as String;
      throw FormatException('commandType n\'a pas été trouvé dans JSON');
    }

    Map<String, dynamic> getParameters() {
      if (json.containsKey('parameters')) {
        final params = json['parameters'];
        if (params is String) {
          try {
            return jsonDecode(params) as Map<String, dynamic>;
          } catch (_) {
            // Si jsonDecode échoue, retourner un Map vide
            return {};
          }
        } else if (params is Map) {
          return Map<String, dynamic>.from(params);
        }
      }
      return {};
    }

    DateTime getTimestamp() {
      if (json.containsKey('timestamp')) {
        final timestamp = json['timestamp'];
        if (timestamp is String) {
          return DateTime.parse(timestamp);
        } else if (timestamp is DateTime) {
          return timestamp;
        }
      }
      return DateTime.now();
    }

    bool getExecuted() {
      if (json.containsKey('executed')) return json['executed'] as bool;
      return false;
    }

    return DeviceCommand(
      id: getId(),
      deviceId: getDeviceId(),
      commandType: getCommandType(),
      parameters: getParameters(),
      timestamp: getTimestamp(),
      executed: getExecuted(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'deviceId': deviceId,
      'commandType': commandType,
      'parameters': parameters,
      'timestamp': timestamp.toIso8601String(),
      'executed': executed,
    };
  }

  Map<String, dynamic> toDatabaseJson() {
    return {
      if (id != null) 'id': id,
      'device_id': deviceId,
      'command_type': commandType,
      'parameters': jsonEncode(parameters),
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
      parameters: {'relay_number': relayNumber, 'status': status},
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
      parameters: {'message': message, 'line': line},
      timestamp: DateTime.now(),
    );
  }

  static DeviceCommand requestData({required String deviceId}) {
    return DeviceCommand(
      deviceId: deviceId,
      commandType: 'request_data',
      parameters: {},
      timestamp: DateTime.now(),
    );
  }
}
