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

  /// Récupère les dernières données d'un appareil ESP32 spécifique.
  /// Utilise l'endpoint /api/data/{deviceId}/latest.
  /// Retourne un objet DeviceData ou des données par défaut en cas d'erreur/absence.
  Future<DeviceData?> getLatestDeviceData(String deviceId) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/data/$deviceId/latest');
      _logger.i(
        'Requête des dernières données pour $deviceId',
        error: url.toString(),
      );

      final response = await http.get(
        url,
        headers: {'x-api-key': ApiConfig.apiKey},
      );

      _logger.i(
        'Réponse reçue pour les dernières données',
        error: {'statusCode': response.statusCode, 'body': response.body},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _logger.i('Données décodées', error: data);

        if (data is Map<String, dynamic>) {
          if (data.containsKey('error')) {
            _logger.w(
              'Erreur API lors de la récupération des dernières données: ${data['error']}',
            );
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

          _logger.i('Données sécurisées pour DeviceData', error: safeData);
          try {
            final deviceData = DeviceData.fromJson(safeData);
            _logger.i(
              'DeviceData créé avec succès',
              error: deviceData.toJson(),
            );
            return deviceData;
          } catch (e) {
            _logger.e(
              'Erreur lors de la conversion des données en DeviceData',
              error: e,
            );
            return _createDefaultDeviceData(deviceId);
          }
        }
        _logger.w('Format de données invalide pour les dernières données');
        return _createDefaultDeviceData(deviceId);
      } else if (response.statusCode == 404) {
        _logger.i('Aucune donnée trouvée pour $deviceId (404)');
        return _createDefaultDeviceData(deviceId);
      } else {
        _logger.e(
          'Erreur HTTP lors de la récupération des dernières données',
          error: {'statusCode': response.statusCode, 'body': response.body},
        );
        return _createDefaultDeviceData(deviceId);
      }
    } catch (e) {
      _logger.e(
        'Erreur de communication lors de la récupération des dernières données',
        error: e,
      );
      return _createDefaultDeviceData(deviceId);
    }
  }

  /// Crée un objet DeviceData avec des valeurs par défaut.
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

  /// Sauvegarde (insère) de nouvelles données d'appareil dans la base de données via l'API.
  /// Utilise l'endpoint POST /api/data.
  Future<bool> saveDeviceData(DeviceData data) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/data');
      _logger.i('Envoi des données de l\'appareil', error: data.toJson());

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': ApiConfig.apiKey,
        },
        body: jsonEncode(data.toJson()),
      );

      _logger.i(
        'Réponse reçue pour l\'envoi des données',
        error: {'statusCode': response.statusCode, 'body': response.body},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('Données sauvegardées avec succès');
        return true;
      } else if (response.statusCode == 403) {
        // Ajout du cas pour API key invalide
        _logger.e(
          'Erreur: Clé API invalide lors de la sauvegarde des données',
          error: response.body,
        );
        return false;
      } else {
        _logger.e(
          'Erreur HTTP lors de la sauvegarde des données',
          error: {'statusCode': response.statusCode, 'body': response.body},
        );
        return false;
      }
    } catch (e) {
      _logger.e(
        'Erreur de communication lors de la sauvegarde des données',
        error: e,
      );
      return false;
    }
  }

  /// Récupère les commandes en attente pour un appareil spécifique.
  /// Utilise l'endpoint GET /api/commands?deviceId={deviceId}.
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
        'Réponse reçue pour les commandes',
        error: {'statusCode': response.statusCode, 'body': response.body},
      );

      if (response.statusCode == 404) {
        _logger.i('Aucune commande trouvée pour $deviceId (404)');
        return [];
      }

      if (response.statusCode == 503) {
        _logger.w(
          'Le serveur est temporairement indisponible (503). Réessai dans 30 secondes.',
        );
        await Future.delayed(const Duration(seconds: 30));
        return getPendingCommands(deviceId);
      }

      if (response.statusCode != 200) {
        _logger.e(
          'Erreur HTTP lors de la récupération des commandes',
          error: {'statusCode': response.statusCode, 'body': response.body},
        );
        return [];
      }

      final data = jsonDecode(response.body);
      _logger.i('Données décodées pour les commandes', error: data);

      if (data is! Map<String, dynamic>) {
        _logger.w('Format de données invalide pour les commandes');
        return [];
      }

      if (data.containsKey('error')) {
        _logger.w(
          'Erreur API lors de la récupération des commandes: ${data['error']}',
        );
        return [];
      }

      if (!data.containsKey('commands')) {
        _logger.w('Champ "commands" manquant dans la réponse des commandes');
        return [];
      }

      final commands = data['commands'];
      _logger.i('Commandes trouvées', error: commands);

      if (commands is! List) {
        _logger.w('Le champ "commands" n\'est pas une liste');
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

          // MODIFICATION ICI: Ne plus exiger 'id' dans la validation initiale
          if (!commandData.containsKey('device_id') ||
              !commandData.containsKey('command_type')) {
            _logger.w(
              'Commande invalide: champs manquants (device_id ou command_type)',
              error: commandData,
            );
            continue;
          }

          final safeData = <String, dynamic>{
            'id':
                commandData['id'], // L'ID peut être null si non fourni par le backend
            'deviceId': commandData['device_id'].toString(),
            'commandType': commandData['command_type'].toString(),
            'parameters': commandData['parameters'] ?? {},
            'timestamp':
                commandData['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'executed': commandData['executed'] ?? false,
            'status': commandData['status'], // Ajouter le statut si présent
          };

          _logger.i('Données sécurisées pour DeviceCommand', error: safeData);
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

  /// Sauvegarde (insère) une nouvelle commande dans la base de données via l'API.
  /// Utilise l'endpoint POST /api/commands.
  Future<bool> saveCommand(DeviceCommand command) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/commands');

      _logger.i('Envoi de la commande', error: command.toJson());

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': ApiConfig.apiKey,
        },
        body: jsonEncode(command.toDatabaseJson()),
      );

      _logger.i(
        'Réponse reçue pour la commande',
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
          'Erreur HTTP lors de la sauvegarde de la commande',
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

  /// Marque une commande comme exécutée dans la base de données via l'API.
  /// Utilise l'endpoint PATCH /api/commands/{commandId}/execute.
  Future<bool> markCommandAsExecuted(int commandId) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/commands/$commandId/execute',
      );
      _logger.i('Marquage de la commande $commandId comme exécutée');

      final response = await http.patch(
        url,
        headers: {'x-api-key': ApiConfig.apiKey},
      );

      _logger.i(
        'Réponse reçue pour le marquage de la commande',
        error: {'statusCode': response.statusCode, 'body': response.body},
      );

      if (response.statusCode == 200) {
        _logger.i('Commande $commandId marquée comme exécutée avec succès');
        return true;
      } else {
        _logger.e(
          'Erreur HTTP lors du marquage de la commande comme exécutée',
          error: {'statusCode': response.statusCode, 'body': response.body},
        );
        return false;
      }
    } catch (e) {
      _logger.e(
        'Erreur de communication lors du marquage de la commande',
        error: e,
      );
      return false;
    }
  }

  /// Authentifie un utilisateur via l'API.
  /// Utilise l'endpoint POST /api/login.
  Future<Map<String, dynamic>?> getUserByCredentials(
    String username,
    String password,
  ) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/login');
      _logger.i('Tentative d\'authentification pour l\'utilisateur: $username');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': ApiConfig.apiKey,
        },
        body: jsonEncode({'username': username, 'password': password}),
      );

      _logger.i(
        'Réponse reçue pour l\'authentification',
        error: {'statusCode': response.statusCode, 'body': response.body},
      );

      if (response.statusCode == 200) {
        _logger.i('Authentification réussie pour $username');
        return jsonDecode(response.body);
      } else {
        _logger.w(
          'Échec de l\'authentification pour $username',
          error: response.body,
        );
        return null;
      }
    } catch (e) {
      _logger.e(
        'Erreur de communication lors de l\'authentification',
        error: e,
      );
      return null;
    }
  }

  /// Récupère la liste de tous les utilisateurs via l'API.
  /// Utilise l'endpoint GET /api/utilisateurs.
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

  /// Méthode pour initialiser les données avec des valeurs par défaut.
  /// Envoie des données initiales pour 'esp32_maison1' et 'esp32_maison2'.
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
      await saveDeviceData(maison1Data);
      await saveDeviceData(maison2Data);

      _logger.i('Données par défaut initialisées avec succès');
    } catch (e) {
      _logger.e(
        'Erreur lors de l\'initialisation des données par défaut',
        error: e,
      );
      rethrow;
    }
  }
}
