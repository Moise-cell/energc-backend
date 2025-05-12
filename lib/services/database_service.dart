import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:postgres/postgres.dart';
import '../models/device_data.dart';
import '../models/device_command.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  late PostgreSQLConnection _connection;
  bool _isConnected = false;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<void> initialize() async {
    final host = dotenv.env['NEON_HOST'] ?? '';
    final port = int.parse(dotenv.env['NEON_PORT'] ?? '5432');
    final database = dotenv.env['NEON_DATABASE'] ?? '';
    final username = dotenv.env['NEON_USER'] ?? '';
    final password = dotenv.env['NEON_PASSWORD'] ?? '';

    _connection = PostgreSQLConnection(
      host,
      port,
      database,
      username: username,
      password: password,
      useSSL: true,
    );

    try {
      await _connection.open();
      _isConnected = true;
      print('Connexion à la base de données réussie');
    } catch (e) {
      print('Erreur de connexion à la base de données: $e');
      _isConnected = false;
      rethrow;
    }
  }

  Future<void> close() async {
    if (_isConnected) {
      await _connection.close();
      _isConnected = false;
    }
  }

  // Méthodes pour les données des appareils
  Future<DeviceData?> getDeviceData(String maisonId) async {
    if (!_isConnected) await initialize();

    final results = await _connection.query(
      '''
      SELECT * FROM device_data 
      WHERE maison_id = @maisonId 
      ORDER BY timestamp DESC 
      LIMIT 1
      ''',
      substitutionValues: {'maisonId': maisonId},
    );

    if (results.isEmpty) {
      print('Aucune donnée trouvée pour $maisonId');
      return null;
    }

    final row = results.first;
    final Map<String, dynamic> data = {};
    for (var i = 0; i < row.columnDescriptions.length; i++) {
      data[row.columnDescriptions[i].columnName] = row[i];
    }

    print(
      'Données récupérées pour $maisonId : $data',
    ); // Log des données récupérées

    return DeviceData.fromJson(data);
  }

  Future<DeviceData> getLatestDeviceData(String deviceId) async {
    final data = await getDeviceData(deviceId); // Supprimez `limit: 1`
    if (data == null) {
      throw Exception('Aucune donnée trouvée pour l\'appareil $deviceId');
    }
    return data;
  }

  Future<void> insertDeviceData(DeviceData data) async {
    if (!_isConnected) await initialize();

    await _connection.execute(
      '''
      INSERT INTO device_data (
        device_id, voltage, current1, current2, energy1, energy2, 
        relay1_status, relay2_status, timestamp
      ) VALUES (
        @deviceId, @voltage, @current1, @current2, @energy1, @energy2, 
        @relay1Status, @relay2Status, @timestamp
      )
      ''',
      substitutionValues: {
        'deviceId': data.deviceId,
        'voltage': data.voltage,
        'current1': data.current1,
        'current2': data.current2,
        'energy1': data.energy1,
        'energy2': data.energy2,
        'relay1Status': data.relay1Status,
        'relay2Status': data.relay2Status,
        'timestamp': data.timestamp.toIso8601String(),
      },
    );
  }

  // Méthodes pour les commandes
  Future<List<DeviceCommand>> getPendingCommands(String deviceId) async {
    if (!_isConnected) await initialize();

    final results = await _connection.query(
      'SELECT * FROM device_commands WHERE device_id = @deviceId AND executed = false ORDER BY timestamp',
      substitutionValues: {'deviceId': deviceId},
    );

    return results.map((row) {
      final Map<String, dynamic> data = {};
      for (var i = 0; i < row.columnDescriptions.length; i++) {
        data[row.columnDescriptions[i].columnName] = row[i];
      }
      return DeviceCommand.fromJson(data);
    }).toList();
  }

  Future<void> insertCommand(DeviceCommand command) async {
    if (!_isConnected) await initialize();

    await _connection.execute(
      '''
      INSERT INTO device_commands (
        device_id, command_type, parameters, timestamp, executed
      ) VALUES (
        @deviceId, @commandType, @parameters, @timestamp, @executed
      )
      ''',
      substitutionValues: {
        'deviceId': command.deviceId,
        'commandType': command.commandType,
        'parameters': command.parameters,
        'timestamp': command.timestamp.toIso8601String(),
        'executed': command.executed,
      },
    );
  }

  Future<void> markCommandAsExecuted(int commandId) async {
    if (!_isConnected) await initialize();

    await _connection.execute(
      'UPDATE device_commands SET executed = true WHERE id = @id',
      substitutionValues: {'id': commandId},
    );
  }

  // Méthodes pour les utilisateurs
  Future<Map<String, dynamic>?> getUserByCredentials(
    String username,
    String password,
  ) async {
    if (!_isConnected) await initialize();

    final results = await _connection.query(
      'SELECT * FROM users WHERE username = @username AND password = @password',
      substitutionValues: {'username': username, 'password': password},
    );

    if (results.isEmpty) return null;

    final row = results.first;
    final Map<String, dynamic> data = {};
    for (var i = 0; i < row.columnDescriptions.length; i++) {
      data[row.columnDescriptions[i].columnName] = row[i];
    }

    return data;
  }

  Future<List<Map<String, dynamic>>> getUtilisateurs() async {
    if (!_isConnected) await initialize();

    final results = await _connection.mappedResultsQuery(
      'SELECT * FROM utilisateurs',
    );
    return results.map((row) => row['utilisateurs']!).toList();
  }
}
