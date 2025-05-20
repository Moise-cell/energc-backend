import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/device_data.dart';
import '../models/device_command.dart';
import 'database_service.dart';
import '../config/api_config.dart';

class ESP32Service {
  static final ESP32Service _instance = ESP32Service._internal();
  final DatabaseService _databaseService = DatabaseService();

  // Identifiants des appareils
  final String _maison1DeviceId = 'esp32_maison1';
  final String _maison2DeviceId = 'esp32_maison2';

  // Timers pour la synchronisation périodique
  Timer? _syncTimer;

  factory ESP32Service() {
    return _instance;
  }

  ESP32Service._internal();

  /// Initialise le service et commence à synchroniser les données
  Future<void> initialize() async {
    // Plus besoin d'initialiser la base de données côté Flutter
    // await _databaseService.initialize();

    // Commencer la synchronisation périodique
    startPeriodicSync();
  }

  void startPeriodicSync({int intervalSeconds = 30}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      syncWithDevices();
    });
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> syncWithDevices() async {
    try {
      // Récupérer les dernières données des deux maisons
      await _fetchLatestDataForMaison1();
      await _fetchLatestDataForMaison2();

      // Envoyer les commandes en attente
      await _sendPendingCommandsToMaison1();
      await _sendPendingCommandsToMaison2();
    } catch (e) {
      print('Erreur lors de la synchronisation avec les ESP32: $e');
    }
  }

  Future<DeviceData?> _fetchLatestDataForMaison1() async {
    try {
      final data = await _databaseService.getLatestDeviceData(_maison1DeviceId);
      return data;
    } catch (e) {
      print('Erreur lors de la récupération des données de Maison 1: $e');
      return null;
    }
  }

  Future<DeviceData?> _fetchLatestDataForMaison2() async {
    try {
      final data = await _databaseService.getLatestDeviceData(_maison2DeviceId);
      return data;
    } catch (e) {
      print('Erreur lors de la récupération des données de Maison 2: $e');
      return null;
    }
  }

  Future<void> _sendPendingCommandsToMaison1() async {
    try {
      final commands = await _databaseService.getPendingCommands(
        _maison1DeviceId,
      );
      for (var command in commands) {
        // Envoyer la commande à l'ESP32 via l'API
        final success = await _sendCommandToDevice(_maison1DeviceId, command);

        if (success) {
          // Marquer la commande comme exécutée
          await _databaseService.markCommandAsExecuted(command.id as int);
        }
      }
    } catch (e) {
      print('Erreur lors de l\'envoi des commandes à Maison 1: $e');
    }
  }

  Future<void> _sendPendingCommandsToMaison2() async {
    try {
      final commands = await _databaseService.getPendingCommands(
        _maison2DeviceId,
      );
      for (var command in commands) {
        // Envoyer la commande à l'ESP32 via l'API
        final success = await _sendCommandToDevice(_maison2DeviceId, command);

        if (success) {
          // Marquer la commande comme exécutée
          await _databaseService.markCommandAsExecuted(command.id as int);
        }
      }
    } catch (e) {
      print('Erreur lors de l\'envoi des commandes à Maison 2: $e');
    }
  }

  /// Envoie une commande à un appareil spécifique via l'API
  Future<bool> _sendCommandToDevice(
    String deviceId,
    DeviceCommand command,
  ) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/commands');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(command.toJson()),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erreur lors de l\'envoi de la commande à l\'ESP32 $deviceId: $e');
      return false;
    }
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
      final success = await _sendCommandToDevice(deviceId, command);
      if (success) {
        await _databaseService.markCommandAsExecuted(command.id as int);
      }
    } catch (e) {
      // Si l'envoi direct échoue, la commande sera envoyée lors de la prochaine synchronisation
      print(
        'Erreur lors de l\'envoi de la commande, sera réessayé plus tard: $e',
      );
    }
  }

  // Méthode pour recharger l'énergie d'une maison
  Future<void> rechargeEnergy({
    required String maisonId,
    required double energyAmount,
  }) async {
    if (energyAmount <= 0) {
      throw ArgumentError('La quantité d\'énergie doit être supérieure à 0');
    }

    final deviceId =
        maisonId == 'maison1' ? _maison1DeviceId : _maison2DeviceId;

    final command = DeviceCommand(
      deviceId: deviceId,
      commandType: 'recharge_energy',
      parameters: {'energy_amount': energyAmount},
      timestamp: DateTime.now(),
    );

    await _databaseService.insertCommand(command);

    // Tenter d'envoyer la commande immédiatement
    try {
      final success = await _sendCommandToDevice(deviceId, command);
      if (success) {
        await _databaseService.markCommandAsExecuted(command.id as int);
      }
    } catch (e) {
      // Si l'envoi direct échoue, la commande sera envoyée lors de la prochaine synchronisation
      print(
        'Erreur lors de l\'envoi de la commande, sera réessayé plus tard: $e',
      );
    }
  }

  // Méthode pour obtenir les données actuelles d'une maison
  Future<DeviceData?> getCurrentData(String maisonId) async {
    final deviceId =
        maisonId == 'maison1' ? _maison1DeviceId : _maison2DeviceId;

    try {
      return await _databaseService.getLatestDeviceData(deviceId);
    } catch (e) {
      print('Erreur lors de la récupération des données pour $maisonId: $e');
      return null;
    }
  }
}
