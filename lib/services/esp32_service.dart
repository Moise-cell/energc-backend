import 'dart:async';
import '../models/device_data.dart';
import '../models/device_command.dart';
import 'database_service.dart';

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
      final commands = await _databaseService.getPendingCommands(_maison1DeviceId);
      for (var command in commands) {
        // Dans une application réelle, ici vous pourriez avoir une logique pour
        // vérifier si la commande a été exécutée par l'ESP32
        
        // Pour l'instant, on marque simplement la commande comme exécutée
        await _databaseService.markCommandAsExecuted(command.id as int);
      }
    } catch (e) {
      print('Erreur lors de l\'envoi des commandes à Maison 1: $e');
    }
  }
  
  Future<void> _sendPendingCommandsToMaison2() async {
    try {
      final commands = await _databaseService.getPendingCommands(_maison2DeviceId);
      for (var command in commands) {
        // Même logique que pour Maison 1
        await _databaseService.markCommandAsExecuted(command.id as int);
      }
    } catch (e) {
      print('Erreur lors de l\'envoi des commandes à Maison 2: $e');
    }
  }
  
  // Méthodes pour contrôler les relais
  Future<void> controlRelay({
    required String maisonId,
    required int relayNumber,
    required bool status,
  }) async {
    final deviceId = maisonId == 'maison1' ? _maison1DeviceId : _maison2DeviceId;
    
    final command = DeviceCommand.relayControl(
      deviceId: deviceId,
      relayNumber: relayNumber,
      status: status,
    );
    
    await _databaseService.insertCommand(command);
  }
  
  // Méthode pour recharger l'énergie d'une maison
  Future<void> rechargeEnergy({
    required String maisonId,
    required double energyAmount,
  }) async {
    final deviceId = maisonId == 'maison1' ? _maison1DeviceId : _maison2DeviceId;
    
    final command = DeviceCommand(
      deviceId: deviceId,
      commandType: 'recharge_energy',
      parameters: {
        'energy_amount': energyAmount,
      },
      timestamp: DateTime.now(),
    );
    
    await _databaseService.insertCommand(command);
  }
  
  // Méthode pour obtenir les données actuelles d'une maison
  Future<DeviceData?> getCurrentData(String maisonId) async {
    final deviceId = maisonId == 'maison1' ? _maison1DeviceId : _maison2DeviceId;
    
    try {
      return await _databaseService.getLatestDeviceData(deviceId);
    } catch (e) {
      print('Erreur lors de la récupération des données pour $maisonId: $e');
      return null;
    }
  }
}
