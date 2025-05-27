import 'dart:async';
import 'dart:convert';
import 'dart:io'; // Ajout de l'import pour SocketException
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../models/device_data.dart';
import '../models/device_command.dart';
import 'database_service.dart';
import '../config/api_config.dart';
import 'package:flutter/foundation.dart';

class ESP32Service extends ChangeNotifier {
  static final ESP32Service _instance = ESP32Service._internal();
  final _logger = Logger();
  final DatabaseService _databaseService = DatabaseService();
  DeviceData? _deviceData;

  // Identifiants des appareils
  final String _maison1DeviceId = 'esp32_maison1';
  final String _maison2DeviceId = 'esp32_maison2';

  // Timers pour la synchronisation périodique
  Timer? _dataFetchTimer;
  Timer? _commandCheckTimer;

  final String baseUrl = ApiConfig.baseUrl;
  final String apiKey = ApiConfig.apiKey;
  final StreamController<Map<String, dynamic>> _dataController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  factory ESP32Service() {
    return _instance;
  }

  ESP32Service._internal();

  // Getter pour accéder aux données du device
  DeviceData? get deviceData => _deviceData;

  /// Initialise le service et commence à synchroniser les données
  Future<void> initialize() async {
    try {
      _logger.i('Initialisation du service ESP32');

      // Vérifier la connexion avec les ESP32 avant de démarrer les timers
      final maison1Connected = await checkESP32Connection(_maison1DeviceId);
      final maison2Connected = await checkESP32Connection(_maison2DeviceId);

      _logger.i(
        'État de la connexion ESP32',
        error: {'maison1': maison1Connected, 'maison2': maison2Connected},
      );

      // Démarrer les timers même si les ESP32 ne sont pas connectés
      // Ils seront réessayés périodiquement
      await _startDataFetching();
      await _startCommandChecking();

      _logger.i('Service ESP32 initialisé avec succès');
    } catch (e) {
      _logger.e('Erreur lors de l\'initialisation du service ESP32', error: e);
      // Ne pas propager l'erreur pour éviter de bloquer le démarrage de l'application
    }
  }

  Future<void> _startDataFetching() async {
    try {
      _dataFetchTimer?.cancel();
      _dataFetchTimer = Timer.periodic(const Duration(seconds: 5), (
        timer,
      ) async {
        try {
          await _fetchDataFromESP32();
        } catch (e) {
          _logger.e('Erreur lors de la récupération des données', error: e);
        }
      });
    } catch (e) {
      _logger.e(
        'Erreur lors du démarrage du timer de récupération des données',
        error: e,
      );
    }
  }

  Future<void> _startCommandChecking() async {
    try {
      _commandCheckTimer?.cancel();
      _commandCheckTimer = Timer.periodic(const Duration(seconds: 30), (
        _,
      ) async {
        try {
          await _checkPendingCommands();
        } catch (e) {
          _logger.e(
            'Erreur dans le timer de vérification des commandes',
            error: e,
          );
        }
      });
    } catch (e) {
      _logger.e(
        'Erreur lors du démarrage du timer de vérification des commandes',
        error: e,
      );
    }
  }

  Future<void> _fetchDataFromESP32() async {
    try {
      // Récupérer les données pour les deux appareils
      final maison1Data = await getCurrentData(_maison1DeviceId);
      final maison2Data = await getCurrentData(_maison2DeviceId);

      if (maison1Data != null) {
        _logger.i(
          '💡 Données reçues pour maison1',
          error: maison1Data.toJson(),
        );
        _dataController.add(maison1Data.toJson());
        await _databaseService.saveDeviceData(maison1Data);
      }

      if (maison2Data != null) {
        _logger.i(
          '💡 Données reçues pour maison2',
          error: maison2Data.toJson(),
        );
        _dataController.add(maison2Data.toJson());
        await _databaseService.saveDeviceData(maison2Data);
      }
    } catch (e) {
      _logger.e('❌ Erreur de connexion: $e', error: e);
      rethrow;
    }
  }

  Future<void> _checkPendingCommands() async {
    try {
      _logger.i('Vérification des commandes en attente');

      // Récupérer les commandes pour les deux devices
      final commands1 = await _databaseService.getPendingCommands(
        _maison1DeviceId,
      );
      final commands2 = await _databaseService.getPendingCommands(
        _maison2DeviceId,
      );
      final allCommands = [...commands1, ...commands2];

      _logger.i('Commandes trouvées', error: allCommands);

      // Traiter les commandes
      for (final command in allCommands) {
        _logger.i('Traitement de la commande', error: command.toJson());

        try {
          switch (command.commandType) {
            case 'recharge_energy':
              final energyAmount =
                  command.parameters['energy_amount'] as double?;
              if (energyAmount != null) {
                await _executeCommand(command);
              }
              break;
            case 'toggle_relay':
              final relayNumber = command.parameters['relay_number'] as int?;
              if (relayNumber != null) {
                await _toggleRelay(relayNumber);
                if (command.id != null) {
                  await _databaseService.markCommandAsExecuted(command.id!);
                }
              }
              break;
            case 'set_relay':
              final relayNumber = command.parameters['relay_number'] as int?;
              final state = command.parameters['state'] as bool?;
              if (relayNumber != null && state != null) {
                await _setRelay(relayNumber, state);
                if (command.id != null) {
                  await _databaseService.markCommandAsExecuted(command.id!);
                }
              }
              break;
            default:
              _logger.w(
                'Type de commande non supporté: ${command.commandType}',
              );
          }
        } catch (e) {
          _logger.e('Erreur lors du traitement de la commande', error: e);
        }
      }
    } catch (e) {
      _logger.e('Erreur lors de la vérification des commandes', error: e);
    }
  }

  Future<void> _executeCommand(DeviceCommand command) async {
    try {
      // Logique d'exécution de la commande
      _logger.i('Exécution de la commande', error: command);
      if (command.id != null) {
        await _databaseService.markCommandAsExecuted(command.id!);
      }
    } catch (e) {
      _logger.e('Erreur lors de l\'exécution de la commande', error: e);
    }
  }

  Future<void> sendCommandToDevice(DeviceCommand command) async {
    try {
      _logger.i('Envoi de la commande à l\'ESP32', error: command);
      await _databaseService.insertCommand(command);
    } catch (e) {
      _logger.e('Erreur lors de l\'envoi de la commande', error: e);
      rethrow;
    }
  }

  @override
  void dispose() {
    _logger.i('Arrêt du service ESP32');
    _dataFetchTimer?.cancel();
    _commandCheckTimer?.cancel();
    _dataController.close();
    super.dispose(); // Appel de la méthode parent
  }

  // Méthodes pour contrôler les relais
  Future<void> controlRelay({
    required String maisonId,
    required int relayNumber,
    required bool status,
  }) async {
    final deviceId =
        maisonId == 'maison1' ? _maison1DeviceId : _maison2DeviceId;

    final command = DeviceCommand.relayControl(
      deviceId: deviceId,
      relayNumber: relayNumber,
      status: status,
    );

    await _databaseService.insertCommand(command);

    // Tenter d'envoyer la commande immédiatement
    try {
      await sendCommandToDevice(command);
      if (command.id != null) {
        await _databaseService.markCommandAsExecuted(command.id!);
      }
    } catch (e) {
      // Si l'envoi direct échoue, la commande sera envoyée lors de la prochaine synchronisation
      _logger.w(
        'Erreur lors de l\'envoi de la commande, sera réessayé plus tard',
        error: e,
      );
    }
  }

  // Méthode pour recharger l'énergie d'une maison
  Future<void> rechargeEnergy({
    required String maisonId,
    required double energyAmount,
  }) async {
    try {
      _logger.i(
        'Début de la recharge d\'énergie',
        error: {'maisonId': maisonId, 'energyAmount': energyAmount},
      );

      // Vérifications de sécurité
      if (energyAmount <= 0) {
        _logger.w('Montant de recharge invalide', error: energyAmount);
        throw Exception('Le montant de recharge doit être supérieur à 0');
      }

      if (energyAmount > 100) {
        // Limite maximale de recharge
        _logger.w('Montant de recharge trop élevé', error: energyAmount);
        throw Exception('Le montant de recharge ne peut pas dépasser 100 kWh');
      }

      // Construire le deviceId
      final deviceId =
          maisonId == 'maison1' ? _maison1DeviceId : _maison2DeviceId;

      // Vérifier la connexion avant d'envoyer la commande
      final isConnected = await checkESP32Connection(deviceId);
      if (!isConnected) {
        _logger.w('ESP32 non connecté', error: deviceId);
        throw Exception('L\'appareil n\'est pas connecté');
      }

      // Créer la commande de recharge
      final command = DeviceCommand.rechargeEnergy(
        deviceId: deviceId,
        energyAmount: energyAmount,
      );

      _logger.i('Commande de recharge créée', error: command.toJson());

      // Envoyer la commande avec retry
      bool success = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!success && retryCount < maxRetries) {
        try {
          success = await _databaseService.saveCommand(command);
          if (success) {
            _logger.i('Commande de recharge envoyée avec succès');

            // Vérifier que la recharge a bien été effectuée
            final rechargeVerified = await verifyRechargeStatus(
              deviceId,
              energyAmount,
            );

            if (!rechargeVerified) {
              _logger.w('La recharge n\'a pas été confirmée');
              throw Exception('La recharge n\'a pas été confirmée');
            }
          }
        } catch (e) {
          retryCount++;
          if (retryCount < maxRetries) {
            _logger.w(
              'Tentative de recharge échouée, nouvelle tentative',
              error: {'tentative': retryCount, 'erreur': e},
            );
            await Future.delayed(const Duration(seconds: 1));
          } else {
            throw Exception(
              'Échec de la recharge après $maxRetries tentatives: $e',
            );
          }
        }
      }

      if (!success) {
        throw Exception('Échec de l\'envoi de la commande de recharge');
      }
    } catch (e) {
      _logger.e('Erreur lors de la recharge d\'énergie', error: e);
      throw Exception('Erreur lors de la recharge d\'énergie: $e');
    }
  }

  // Méthode pour obtenir les données actuelles d'une maison
  Future<DeviceData?> getCurrentData(String deviceId) async {
    try {
      final url = Uri.parse('$baseUrl/api/data/$deviceId/latest');
      _logger.i('Requête des données pour $deviceId', error: url.toString());

      final response = await http
          .get(url, headers: {'x-api-key': apiKey})
          .timeout(Duration(milliseconds: ApiConfig.timeout));

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

          // Vérifier si les données requises sont présentes et non nulles
          final requiredFields = [
            'voltage',
            'current1',
            'current2',
            'energy1',
            'energy2',
          ];
          final missingFields =
              requiredFields
                  .where(
                    (field) => !data.containsKey(field) || data[field] == null,
                  )
                  .toList();

          if (missingFields.isNotEmpty) {
            _logger.w('Champs manquants ou nuls: ${missingFields.join(", ")}');
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
          final deviceData = DeviceData.fromJson(safeData);
          _logger.i('DeviceData créé', error: deviceData.toJson());
          return deviceData;
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
      _logger.e('Erreur lors de la communication avec l\'ESP32', error: e);
      return _createDefaultDeviceData(deviceId);
    }
  }

  // Méthode utilitaire pour créer des données par défaut
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

  Future<bool> verifyRechargeStatus(
    String deviceId,
    double expectedEnergy,
  ) async {
    try {
      // Faire 5 tentatives avec un délai de 1 seconde
      for (int i = 0; i < 5; i++) {
        final data = await getCurrentData(deviceId);
        if (data != null) {
          final currentEnergy =
              deviceId == _maison1DeviceId ? data.energy1 : data.energy2;
          _logger.i(
            'Vérification de la recharge (tentative ${i + 1})',
            error: {
              'deviceId': deviceId,
              'expectedEnergy': expectedEnergy,
              'currentEnergy': currentEnergy,
            },
          );

          // Accepter une marge d'erreur de 0.1 kWh
          if (currentEnergy >= expectedEnergy - 0.1) {
            _logger.i('Recharge vérifiée avec succès');
            return true;
          }
        }
        // Attendre 1 seconde entre chaque tentative
        await Future.delayed(const Duration(seconds: 1));
      }

      _logger.w(
        'La recharge n\'a pas été confirmée après plusieurs tentatives',
      );
      return false;
    } catch (e) {
      _logger.e('Erreur lors de la vérification de la recharge', error: e);
      return false;
    }
  }

  Future<bool> checkESP32Connection(String deviceId) async {
    try {
      final url = Uri.parse('$baseUrl/api/data/$deviceId/latest');
      _logger.i('Tentative de connexion à:', error: url.toString());

      final client = http.Client();
      try {
        final response = await client
            .get(url, headers: {'x-api-key': apiKey})
            .timeout(Duration(milliseconds: ApiConfig.timeout));

        _logger.i(
          'Réponse du serveur:',
          error: {
            'statusCode': response.statusCode,
            'body': response.body,
            'headers': response.headers,
          },
        );

        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } on TimeoutException {
      _logger.e('Timeout lors de la connexion au serveur');
      return false;
    } on SocketException catch (e) {
      _logger.e('Erreur de connexion au serveur:', error: e.message);
      return false;
    } catch (e) {
      _logger.e(
        'Erreur lors de la vérification de la connexion ESP32',
        error: e,
      );
      return false;
    }
  }

  Future<void> waitForESP32Response(
    String deviceId, {
    int maxAttempts = 3,
  }) async {
    for (int i = 0; i < maxAttempts; i++) {
      if (await checkESP32Connection(deviceId)) {
        return;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    throw Exception('L\'ESP32 ne répond pas après $maxAttempts tentatives');
  }

  // Méthode pour basculer l'état d'un relais
  Future<void> _toggleRelay(int relayNumber) async {
    try {
      final currentState = _deviceData?.relay1Status ?? false;
      await _setRelay(relayNumber, !currentState);
    } catch (e) {
      _logger.e('Erreur lors du basculement du relais', error: e);
      rethrow;
    }
  }

  // Méthode pour définir l'état d'un relais
  Future<void> _setRelay(int relayNumber, bool state) async {
    try {
      final command = DeviceCommand.relayControl(
        deviceId: _maison2DeviceId,
        relayNumber: relayNumber,
        status: state,
      );
      await sendCommandToDevice(command);
    } catch (e) {
      _logger.e('Erreur lors de la définition de l\'état du relais', error: e);
      rethrow;
    }
  }
}
