import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../models/device_data.dart';
import '../models/device_command.dart';
import '../config/api_config.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  final _logger = Logger();

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  // Méthode vide pour compatibilité avec ServiceLocator
  Future<void> initialize() async {}

  // Méthode vide pour compatibilité avec ServiceLocator
  Future<void> close() async {}

  // Récupérer les données d'une maison
  Future<DeviceData?> getDeviceData(String maisonId) async {
    try {
      // Construire le deviceId correct
      final deviceId = 'esp32_$maisonId';
      final url = Uri.parse('${ApiConfig.baseUrl}/api/data/$deviceId/latest');
      _logger.i('Requête des données pour $deviceId', error: url.toString());

      final response = await http.get(
        url,
        headers: {'x-api-key': ApiConfig.apiKey},
      );

      _logger.i(
        'Réponse reçue',
        error: {'statusCode': response.statusCode, 'body': response.body},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _logger.i('Données décodées', error: data);

        if (data is Map<String, dynamic>) {
          if (data.containsKey('error')) {
            _logger.w('Erreur API: ${data['error']}');
            return _createDefaultDeviceData(deviceId);
          }

          // Convertir les données au format attendu par DeviceData
          final safeData = <String, dynamic>{
            'deviceId': data['device_id']?.toString() ?? deviceId,
            'voltage':
                data['voltage'] is num
                    ? (data['voltage'] as num).toDouble()
                    : 0.0,
            'current1':
                data['current1'] is num
                    ? (data['current1'] as num).toDouble()
                    : 0.0,
            'current2':
                data['current2'] is num
                    ? (data['current2'] as num).toDouble()
                    : 0.0,
            'energy1':
                data['energy1'] is num
                    ? (data['energy1'] as num).toDouble()
                    : 0.0,
            'energy2':
                data['energy2'] is num
                    ? (data['energy2'] as num).toDouble()
                    : 0.0,
            'relay1Status':
                data['relay1_status'] is bool
                    ? data['relay1_status'] as bool
                    : false,
            'relay2Status':
                data['relay2_status'] is bool
                    ? data['relay2_status'] as bool
                    : false,
            'timestamp':
                data['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          };

          _logger.i('Données sécurisées', error: safeData);
          try {
            final deviceData = DeviceData.fromJson(safeData);
            _logger.i('DeviceData créé', error: deviceData.toJson());
            return deviceData;
          } catch (e) {
            _logger.e('Erreur lors de la conversion des données', error: e);
            return _createDefaultDeviceData(deviceId);
          }
        }
        _logger.w('Format de données invalide');
        return _createDefaultDeviceData(deviceId);
      } else if (response.statusCode == 404) {
        _logger.i('Aucune donnée trouvée pour $deviceId');
        return _createDefaultDeviceData(deviceId);
      } else {
        _logger.e(
          'Erreur lors de la récupération des données',
          error: response.body,
        );
        return _createDefaultDeviceData(deviceId);
      }
    } catch (e) {
      _logger.e(
        'Erreur lors de la communication avec la base de données',
        error: e,
      );
      return _createDefaultDeviceData('esp32_$maisonId');
    }
  }

  DeviceData _createDefaultDeviceData(String deviceId) {
    return DeviceData(
      deviceId: deviceId,
      voltage: 0.0,
      current1: 0.0,
      current2: 0.0,
      energy1: 0.0,
      energy2: 0.0,
      relay1Status: false,
      relay2Status: false,
      timestamp: DateTime.now(),
    );
  }

  // Envoyer de nouvelles données (insertion)
  Future<bool> insertDeviceData(DeviceData data) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/data');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ApiConfig.apiKey,
      },
      body: jsonEncode(data.toJson()),
    );
    return response.statusCode == 200;
  }

  // Récupérer les commandes en attente pour un device
  Future<List<DeviceCommand>> getPendingCommands(String deviceId) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/commands?deviceId=$deviceId',
      );
      _logger.i('Requête des commandes pour $deviceId', error: url.toString());

      final response = await http.get(
        url,
        headers: {'x-api-key': ApiConfig.apiKey},
      );

      _logger.i(
        'Réponse reçue',
        error: {'statusCode': response.statusCode, 'body': response.body},
      );

      if (response.statusCode == 404) {
        _logger.i('Aucune commande trouvée pour $deviceId');
        return [];
      }

      if (response.statusCode == 503) {
        _logger.w(
          'Le serveur est temporairement indisponible (503). Réessai dans 30 secondes.',
        );
        // Attendre 30 secondes avant de réessayer
        await Future.delayed(const Duration(seconds: 30));
        return getPendingCommands(deviceId);
      }

      if (response.statusCode != 200) {
        _logger.e(
          'Erreur lors de la récupération des commandes',
          error: response.body,
        );
        return [];
      }

      final data = jsonDecode(response.body);
      _logger.i('Données décodées', error: data);

      if (data is! Map<String, dynamic>) {
        _logger.w('Format de données invalide');
        return [];
      }

      if (data.containsKey('error')) {
        _logger.w('Erreur API: ${data['error']}');
        return [];
      }

      if (!data.containsKey('commands')) {
        _logger.w('Champ commands manquant dans la réponse');
        return [];
      }

      final commands = data['commands'];
      _logger.i('Commandes trouvées', error: commands);

      if (commands is! List) {
        _logger.w('Le champ commands n\'est pas une liste');
        return [];
      }

      final deviceCommands = <DeviceCommand>[];
      for (final commandData in commands) {
        try {
          if (commandData is! Map<String, dynamic>) {
            _logger.w('Format de commande invalide', error: commandData);
            continue;
          }

          _logger.i('Traitement de la commande', error: commandData);

          if (!commandData.containsKey('id') ||
              !commandData.containsKey('device_id') ||
              !commandData.containsKey('command_type')) {
            _logger.w(
              'Commande invalide: champs manquants',
              error: commandData,
            );
            continue;
          }

          final safeData = <String, dynamic>{
            'id': commandData['id'],
            'deviceId': commandData['device_id'].toString(),
            'commandType': commandData['command_type'].toString(),
            'parameters': commandData['parameters'] ?? {},
            'timestamp':
                commandData['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'executed': commandData['executed'] ?? false,
          };

          _logger.i('Données sécurisées', error: safeData);
          deviceCommands.add(DeviceCommand.fromJson(safeData));
        } catch (e) {
          _logger.e('Erreur lors de la conversion d\'une commande', error: e);
        }
      }

      _logger.i(
        'Nombre de commandes valides trouvées: ${deviceCommands.length}',
      );
      return deviceCommands;
    } catch (e) {
      _logger.e(
        'Erreur lors de la communication avec la base de données',
        error: e,
      );
      return [];
    }
  }

  // Insérer une commande
  Future<bool> insertCommand(DeviceCommand command) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/commands');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ApiConfig.apiKey,
      },
      body: jsonEncode(command.toJson()),
    );
    return response.statusCode == 200;
  }

  // Marquer une commande comme exécutée
  Future<bool> markCommandAsExecuted(int commandId) async {
    final url = Uri.parse(
      '${ApiConfig.baseUrl}/api/commands/$commandId/execute',
    );
    final response = await http.patch(
      url,
      headers: {'x-api-key': ApiConfig.apiKey},
    );
    return response.statusCode == 200;
  }

  // Authentification utilisateur (exemple)
  Future<Map<String, dynamic>?> getUserByCredentials(
    String username,
    String password,
  ) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/login');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ApiConfig.apiKey,
      },
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  // Récupérer tous les utilisateurs
  Future<List<Map<String, dynamic>>> getUtilisateurs() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/utilisateurs');
    final response = await http.get(
      url,
      headers: {'x-api-key': ApiConfig.apiKey},
    );
    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(list);
    }
    return [];
  }

  // Récupérer les dernières données d'un device
  Future<DeviceData?> getLatestDeviceData(String deviceId) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/data/$deviceId/latest');
      final response = await http.get(
        url,
        headers: {'x-api-key': ApiConfig.apiKey},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          if (data.containsKey('error')) {
            _logger.w('Aucune donnée trouvée pour $deviceId');
            // Retourner des données par défaut au lieu de null
            return DeviceData(
              deviceId: deviceId,
              voltage: 0.0,
              current1: 0.0,
              current2: 0.0,
              energy1: 0.0,
              energy2: 0.0,
              relay1Status: false,
              relay2Status: false,
              timestamp: DateTime.now(),
            );
          }

          // Convertir les données au format attendu par DeviceData
          final safeData = <String, dynamic>{
            'deviceId': data['device_id']?.toString() ?? deviceId,
            'voltage':
                data['voltage'] is num
                    ? (data['voltage'] as num).toDouble()
                    : 0.0,
            'current1':
                data['current1'] is num
                    ? (data['current1'] as num).toDouble()
                    : 0.0,
            'current2':
                data['current2'] is num
                    ? (data['current2'] as num).toDouble()
                    : 0.0,
            'energy1':
                data['energy1'] is num
                    ? (data['energy1'] as num).toDouble()
                    : 0.0,
            'energy2':
                data['energy2'] is num
                    ? (data['energy2'] as num).toDouble()
                    : 0.0,
            'relay1Status':
                data['relay1_status'] is bool
                    ? data['relay1_status'] as bool
                    : false,
            'relay2Status':
                data['relay2_status'] is bool
                    ? data['relay2_status'] as bool
                    : false,
            'timestamp':
                data['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          };

          try {
            return DeviceData.fromJson(safeData);
          } catch (e) {
            _logger.e('Erreur lors de la conversion des données', error: e);
            // Retourner des données par défaut en cas d'erreur de conversion
            return DeviceData(
              deviceId: deviceId,
              voltage: 0.0,
              current1: 0.0,
              current2: 0.0,
              energy1: 0.0,
              energy2: 0.0,
              relay1Status: false,
              relay2Status: false,
              timestamp: DateTime.now(),
            );
          }
        }
        // Retourner des données par défaut si le format n'est pas correct
        return DeviceData(
          deviceId: deviceId,
          voltage: 0.0,
          current1: 0.0,
          current2: 0.0,
          energy1: 0.0,
          energy2: 0.0,
          relay1Status: false,
          relay2Status: false,
          timestamp: DateTime.now(),
        );
      } else {
        _logger.e(
          'Erreur lors de la récupération de la dernière donnée',
          error: response.body,
        );
        // Retourner des données par défaut en cas d'erreur HTTP
        return DeviceData(
          deviceId: deviceId,
          voltage: 0.0,
          current1: 0.0,
          current2: 0.0,
          energy1: 0.0,
          energy2: 0.0,
          relay1Status: false,
          relay2Status: false,
          timestamp: DateTime.now(),
        );
      }
    } catch (e) {
      _logger.e(
        'Erreur lors de la récupération de la dernière donnée',
        error: e,
      );
      // Retourner des données par défaut en cas d'erreur de communication
      return DeviceData(
        deviceId: deviceId,
        voltage: 0.0,
        current1: 0.0,
        current2: 0.0,
        energy1: 0.0,
        energy2: 0.0,
        relay1Status: false,
        relay2Status: false,
        timestamp: DateTime.now(),
      );
    }
  }

  // Sauvegarder les données d'un appareil
  Future<bool> saveDeviceData(DeviceData data) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/data');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': ApiConfig.apiKey,
        },
        body: jsonEncode(data.toJson()),
      );

      if (response.statusCode == 200) {
        _logger.i('Données sauvegardées avec succès');
        return true;
      } else {
        _logger.e(
          'Erreur lors de la sauvegarde des données',
          error: response.body,
        );
        return false;
      }
    } catch (e) {
      _logger.e('Erreur lors de la communication avec l\'API', error: e);
      return false;
    }
  }

  // Méthode pour initialiser les données avec des valeurs par défaut
  Future<void> initializeDefaultData() async {
    try {
      _logger.i('Initialisation des données par défaut');

      // Données pour la maison 1
      final maison1Data = DeviceData(
        deviceId: 'esp32_maison1',
        voltage: 220.0,
        current1: 0.0,
        current2: 0.0,
        energy1: 2.0, // 2 kWh pour la maison 1
        energy2: 0.0,
        relay1Status: false,
        relay2Status: false,
        timestamp: DateTime.now(),
      );

      // Données pour la maison 2
      final maison2Data = DeviceData(
        deviceId: 'esp32_maison2',
        voltage: 220.0,
        current1: 0.0,
        current2: 0.0,
        energy1: 0.0,
        energy2: 5.0, // 5 kWh pour la maison 2
        relay1Status: false,
        relay2Status: false,
        timestamp: DateTime.now(),
      );

      // Envoyer les données au serveur
      await insertDeviceData(maison1Data);
      await insertDeviceData(maison2Data);

      _logger.i('Données par défaut initialisées avec succès');
    } catch (e) {
      _logger.e(
        'Erreur lors de l\'initialisation des données par défaut',
        error: e,
      );
      rethrow;
    }
  }

  // Sauvegarder une commande
  Future<bool> saveCommand(DeviceCommand command) async {
    try {
      // S'assurer que l'URL de base se termine par /api
      final baseUrl =
          ApiConfig.baseUrl.endsWith('/api')
              ? ApiConfig.baseUrl
              : '${ApiConfig.baseUrl}/api';
      final url = Uri.parse('$baseUrl/commands');

      // Log de la commande avant conversion
      _logger.i(
        'Commande avant conversion',
        error: {
          'id': command.id,
          'deviceId': command.deviceId,
          'commandType': command.commandType,
          'parameters': command.parameters,
          'timestamp': command.timestamp.toIso8601String(),
          'executed': command.executed,
        },
      );

      // Log de la commande après conversion
      final commandJson = command.toDatabaseJson();
      _logger.i('Commande après conversion', error: commandJson);

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': ApiConfig.apiKey,
        },
        body: jsonEncode(commandJson),
      );

      _logger.i(
        'Réponse reçue',
        error: {'statusCode': response.statusCode, 'body': response.body},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('Commande sauvegardée avec succès');
        return true;
      } else if (response.statusCode == 503) {
        _logger.w(
          'Le serveur est temporairement indisponible (503). Réessai dans 30 secondes.',
        );
        await Future.delayed(const Duration(seconds: 30));
        return saveCommand(command);
      } else {
        _logger.e(
          'Erreur lors de la sauvegarde de la commande',
          error: {
            'statusCode': response.statusCode,
            'body': response.body,
            'url': url.toString(),
          },
        );
        return false;
      }
    } catch (e) {
      _logger.e(
        'Erreur lors de la sauvegarde de la commande',
        error: {'error': e.toString(), 'type': e.runtimeType.toString()},
      );
      return false;
    }
  }
}
