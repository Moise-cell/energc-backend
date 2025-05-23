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
      if (json.containsKey('id')) {
        final id = json['id'];
        if (id is int) return id;
        if (id is String) return int.tryParse(id);
      }
      return null;
    }

    String getDeviceId() {
      if (json.containsKey('device_id')) {
        final deviceId = json['device_id'];
        if (deviceId is String) return deviceId;
      }
      if (json.containsKey('deviceId')) {
        final deviceId = json['deviceId'];
        if (deviceId is String) return deviceId;
      }
      return 'unknown_device';
    }

    String getCommandType() {
      if (json.containsKey('command_type')) {
        final commandType = json['command_type'];
        if (commandType is String) return commandType;
      }
      if (json.containsKey('commandType')) {
        final commandType = json['commandType'];
        if (commandType is String) return commandType;
      }
      return 'unknown';
    }

    Map<String, dynamic> getParameters() {
      if (json.containsKey('parameters')) {
        final params = json['parameters'];
        if (params is String) {
          try {
            return jsonDecode(params) as Map<String, dynamic>;
          } catch (_) {
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
          try {
            return DateTime.parse(timestamp);
          } catch (_) {
            return DateTime.now();
          }
        } else if (timestamp is DateTime) {
          return timestamp;
        }
      }
      if (json.containsKey('created_at')) {
        final timestamp = json['created_at'];
        if (timestamp is String) {
          try {
            return DateTime.parse(timestamp);
          } catch (_) {
            return DateTime.now();
          }
        }
      }
      return DateTime.now();
    }

    bool getExecuted() {
      if (json.containsKey('executed')) {
        final executed = json['executed'];
        if (executed is bool) return executed;
        if (executed is String) {
          return executed.toLowerCase() == 'true';
        }
      }
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

  static DeviceCommand rechargeEnergy({
    required String deviceId,
    required double energyAmount,
  }) {
    return DeviceCommand(
      deviceId: deviceId,
      commandType: 'recharge_energy',
      parameters: {'energy_amount': energyAmount},
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
