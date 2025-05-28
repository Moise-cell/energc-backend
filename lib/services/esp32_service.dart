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
  DeviceData?
  _deviceData; // Peut être utilisé pour stocker les dernières données globales, mais attention à l'obsolescence

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

  // Getter pour accéder aux données du device (attention: peut être obsolète si non mis à jour régulièrement)
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

  /// Démarre le timer de récupération périodique des données des ESP32.
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

  /// Démarre le timer de vérification périodique des commandes en attente.
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

  /// Récupère les dernières données de chaque ESP32 et les sauvegarde.
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
        // await _databaseService.saveDeviceData(maaison1Data); // <-- LIGNE COMMENTÉE
      }

      if (maison2Data != null) {
        _logger.i(
          '💡 Données reçues pour maison2',
          error: maison2Data.toJson(),
        );
        _dataController.add(maison2Data.toJson());
        // await _databaseService.saveDeviceData(maison2Data); // <-- LIGNE COMMENTÉE
      }
    } catch (e) {
      _logger.e(
        '❌ Erreur de connexion lors du fetch des données: $e',
        error: e,
      );
      rethrow;
    }
  }

  /// Vérifie et traite les commandes en attente pour les appareils.
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
              _logger.i(
                'Commande de recharge d\'énergie traitée (marquage exécuté)',
                error: command.toJson(),
              );
              await _executeCommand(command);
              break;

            case 'relay_control': // Gérer le type de commande 'relay_control'
              final relayNumber = command.parameters['relay_number'] as int?;
              final status = command.parameters['status'] as bool?;

              if (relayNumber != null && status != null) {
                _logger.i(
                  'Commande relay_control traitée: Relais $relayNumber de ${command.deviceId} mis à ${status ? "ON" : "OFF"}',
                  error: command.toJson(),
                );
                // L'application Flutter ne contrôle pas directement le relais physique.
                // Elle marque juste la commande comme exécutée après que l'ESP32 est censé l'avoir traitée.
                await _executeCommand(command); // Marquer comme exécutée
              } else {
                _logger.w(
                  'Commande relay_control invalide: champs manquants (relay_number ou status)',
                  error: command.toJson(),
                );
                await _executeCommand(
                  command,
                ); // Marquer comme exécutée pour éviter de la re-traiter
              }
              break;

            // Les cas 'toggle_relay' et 'set_relay' sont supprimés/commentés car 'relay_control' est le type canonique reçu.
            // Si votre backend renvoie toujours 'relay_control' pour les actions de relais, ces cas sont redondants.
            /*
            case 'toggle_relay':
              final relayNumber = command.parameters['relay_number'] as int?;
              if (relayNumber != null) {
                _logger.i('Commande toggle_relay traitée pour ${command.deviceId} relais $relayNumber');
                await _executeCommand(command);
              } else {
                _logger.w('Commande toggle_relay invalide: relay_number manquant', error: command.toJson());
                await _executeCommand(command);
              }
              break;

            case 'set_relay':
              final relayNumber = command.parameters['relay_number'] as int?;
              final state = command.parameters['state'] as bool?;
              if (relayNumber != null && state != null) {
                _logger.i('Commande set_relay traitée pour ${command.deviceId} relais $relayNumber à $state');
                await _executeCommand(command);
              } else {
                _logger.w('Commande set_relay invalide: champs manquants (relay_number ou state)', error: command.toJson());
                await _executeCommand(command);
              }
              break;
            */

            case 'display_message':
              final message = command.parameters['message'] as String?;
              final line = command.parameters['line'] as int? ?? 0;
              if (message != null) {
                _logger.i(
                  'Traitement commande display_message: "$message" sur ligne $line pour ${command.deviceId}',
                  error: command.toJson(),
                );
                // TODO: Implémenter la logique pour envoyer ce message à l'ESP32 via le backend
                // Exemple: await _databaseService.sendMessageToESP32(command.deviceId, message, line);
                await _executeCommand(
                  command,
                ); // Marque la commande comme exécutée
              } else {
                _logger.w(
                  'Commande display_message invalide: message manquant',
                  error: command.toJson(),
                );
                await _executeCommand(command); // Marquer comme exécutée
              }
              break;

            case 'request_data':
              _logger.i(
                'Traitement commande request_data pour ${command.deviceId}',
                error: command.toJson(),
              );
              await getCurrentData(
                command.deviceId,
              ); // Ceci est une requête GET, donc c'est correct.
              await _executeCommand(
                command,
              ); // Marque la commande comme exécutée
              break;

            default:
              _logger.w(
                'Type de commande non supporté ou traitement manquant: ${command.commandType}',
                error: command.toJson(),
              );
              await _executeCommand(command);
          }
        } catch (e) {
          _logger.e('Erreur lors du traitement de la commande', error: e);
          await _executeCommand(command);
        }
      }
    } catch (e) {
      _logger.e('Erreur lors de la vérification des commandes', error: e);
    }
  }

  /// Marque une commande comme exécutée dans la base de données.
  /// Cette méthode est appelée après que la commande a été traitée par l'application.
  Future<void> _executeCommand(DeviceCommand command) async {
    try {
      _logger.i(
        'Marquage de la commande comme exécutée',
        error: command.toJson(),
      );
      if (command.id != null) {
        await _databaseService.markCommandAsExecuted(command.id!);
      } else {
        _logger.w(
          'Impossible de marquer la commande comme exécutée: ID de commande est null',
          error: command.toJson(),
        );
        // Pour la robustesse, si l'ID est null, vous pourriez envisager
        // de marquer la commande comme exécutée d'une autre manière (si votre backend le permet),
        // par exemple en utilisant device_id et timestamp comme identifiants.
        // Cependant, markCommandAsExecuted attend un int.
        // La vraie solution est que le backend fournisse un ID.
      }
    } catch (e) {
      _logger.e(
        'Erreur lors du marquage de la commande comme exécutée',
        error: e,
      );
    }
  }

  /// Envoie une commande au backend pour qu'elle soit relayée à l'ESP32.
  /// Cette méthode est un wrapper pour `_databaseService.saveCommand`.
  /// Elle est utilisée par les méthodes de contrôle direct (comme `controlRelay`).
  Future<void> sendCommandToDevice(DeviceCommand command) async {
    try {
      _logger.i(
        'Envoi de la commande à l\'API (via DatabaseService)',
        error: command.toJson(),
      );
      // saveCommand va insérer la commande dans la DB et l'envoyer au backend.
      // Si le backend répond 200/201, la commande est considérée comme "envoyée".
      final success = await _databaseService.saveCommand(command);
      if (!success) {
        throw Exception('Échec de l\'envoi de la commande au backend');
      }
    } catch (e) {
      _logger.e('Erreur lors de l\'envoi de la commande à l\'API', error: e);
      rethrow;
    }
  }

  @override
  void dispose() {
    _logger.i('Arrêt du service ESP32');
    _dataFetchTimer?.cancel();
    _commandCheckTimer?.cancel();
    _dataController.close();
    super.dispose();
  }

  /// Méthode publique pour contrôler les relais d'une maison.
  /// Crée une commande et l'envoie au backend.
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

    _logger.i('Commande de contrôle de relais créée', error: command.toJson());

    // Envoyer la commande au backend. saveCommand gère l'insertion et l'envoi HTTP.
    try {
      final success = await _databaseService.saveCommand(command);
      if (success) {
        _logger.i(
          'Commande de relais envoyée avec succès au backend',
          error: command.toJson(),
        );
        // La commande sera marquée comme exécutée par _checkPendingCommands une fois qu'elle est récupérée avec un ID valide.
      } else {
        _logger.w(
          'Échec de l\'envoi immédiat de la commande de relais. Sera réessayé par _checkPendingCommands.',
          error: command.toJson(),
        );
      }
    } catch (e) {
      _logger.e(
        'Erreur lors de l\'envoi immédiat de la commande de relais. Sera réessayé par _checkPendingCommands.',
        error: e,
      );
    }
  }

  /// Méthode publique pour recharger l'énergie d'une maison.
  /// Crée une commande de recharge et l'envoie au backend.
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
        // On ne lève pas d'exception ici si on veut que la commande soit sauvegardée
        // et potentiellement réessayée par le backend ou par le timer.
        // Si vous voulez bloquer l'action utilisateur, vous pouvez throw ici.
      }

      // Créer la commande de recharge
      final command = DeviceCommand.rechargeEnergy(
        deviceId: deviceId,
        energyAmount: energyAmount,
      );

      _logger.i('Commande de recharge créée', error: command.toJson());

      bool success = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!success && retryCount < maxRetries) {
        try {
          // saveCommand va insérer la commande dans la DB et l'envoyer au backend.
          // Si le backend répond 200/201, la commande est considérée comme "envoyée".
          success = await _databaseService.saveCommand(command);
          if (success) {
            _logger.i('Commande de recharge envoyée avec succès au backend');

            // La commande sera marquée comme exécutée par `_checkPendingCommands` une fois qu'elle est récupérée avec un ID valide.

            final rechargeVerified = await verifyRechargeStatus(
              deviceId,
              energyAmount,
            );

            if (!rechargeVerified) {
              _logger.w('La recharge n\'a pas été confirmée par l\'ESP32');
              throw Exception('La recharge n\'a pas été confirmée');
            } else {
              _logger.i('Recharge d\'énergie vérifiée avec succès');
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

  /// Récupère les données actuelles d'un appareil ESP32.
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

  /// Méthode utilitaire pour créer des données par défaut.
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

  /// Vérifie si la recharge d'énergie a été confirmée par l'appareil.
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

  /// Vérifie la connectivité d'un ESP32 en interrogeant son endpoint de dernières données.
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

  /// Attend une réponse d'un ESP32 avec un nombre maximal de tentatives.
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

  /// Bascule l'état d'un relais pour un appareil donné.
  Future<void> _toggleRelay(String deviceId, int relayNumber) async {
    try {
      // Récupérer l'état actuel du relais pour l'appareil spécifique
      final currentData = await getCurrentData(deviceId);
      bool currentState = false;
      if (currentData != null) {
        currentState =
            (relayNumber == 1)
                ? currentData.relay1Status
                : currentData.relay2Status;
      } else {
        _logger.w(
          'Impossible de récupérer l\'état actuel du relais pour $deviceId. Assumons OFF.',
          error: {'deviceId': deviceId, 'relayNumber': relayNumber},
        );
      }

      // Définir le nouvel état du relais
      await _setRelay(deviceId, relayNumber, !currentState);
      _logger.i(
        'Relais $relayNumber de $deviceId basculé avec succès.',
        error: {'newState': !currentState},
      );
    } catch (e) {
      _logger.e('Erreur lors du basculement du relais', error: e);
      rethrow;
    }
  }

  /// Définit l'état d'un relais spécifique pour un appareil donné.
  Future<void> _setRelay(String deviceId, int relayNumber, bool state) async {
    try {
      final command = DeviceCommand.relayControl(
        deviceId: deviceId, // Utilise le deviceId dynamique
        relayNumber: relayNumber,
        status: state,
      );
      _logger.i(
        'Envoi de la commande set_relay pour $deviceId relais $relayNumber à $state',
        error: command.toJson(),
      );
      // Cette méthode appelle sendCommandToDevice, qui à son tour appelle _databaseService.saveCommand.
      await sendCommandToDevice(command);
    } catch (e) {
      _logger.e('Erreur lors de la définition de l\'état du relais', error: e);
      rethrow;
    }
  }
}
