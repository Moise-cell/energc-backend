import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:energc/models/device_data.dart';
import '../services/database_service.dart';
import '../services/esp32_service.dart';
import '../config/api_config.dart';
import 'package:logger/logger.dart';

class EnergyProvider extends ChangeNotifier {
  DeviceData? maison1Data;
  DeviceData? maison2Data;
  bool _isLoadingData = false;
  String? _dataErrorMessage;
  Timer? _updateTimer;
  final ESP32Service _esp32Service = ESP32Service();
  final DatabaseService _databaseService = DatabaseService();
  final _logger = Logger();
  bool _isInitialized = false;

  // Getters pour l'état
  bool get isLoadingData => _isLoadingData;
  String? get dataErrorMessage => _dataErrorMessage;

  // IDs des appareils
  static const String _maison1DeviceId = 'esp32_maison1';
  static const String _maison2DeviceId = 'esp32_maison2';

  EnergyProvider() {
    // Initialiser les données par défaut immédiatement
    _initializeDefaultData();
    // Utiliser Future.microtask pour l'initialisation asynchrone
    Future.microtask(() => _initializeAsync());
  }

  void _initializeDefaultData() {
    // Initialiser les données par défaut pour les deux maisons
    maison1Data = DeviceData(
      deviceId: _maison1DeviceId,
      voltage: 0.0,
      current1: 0.0,
      current2: 0.0,
      energy1: 0.0,
      energy2: 0.0,
      relay1Status: false,
      relay2Status: false,
      timestamp: DateTime.now(),
    );

    maison2Data = DeviceData(
      deviceId: _maison2DeviceId,
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

  Future<void> _initializeAsync() async {
    if (_isInitialized) return;

    try {
      _isLoadingData = true;
      _dataErrorMessage = null;
      notifyListeners();

      // Initialiser le service ESP32
      await _esp32Service.initialize();

      // Récupérer les données initiales
      await refreshData();

      // Mise à jour toutes les 3 minutes
      _updateTimer?.cancel();
      _updateTimer = Timer.periodic(const Duration(seconds: 180), (_) {
        if (_isInitialized) {
          refreshData();
        }
      });

      _isInitialized = true;
      _isLoadingData = false;
      notifyListeners();
    } catch (e, stack) {
      _logger.e(
        'Erreur lors de l\'initialisation des données',
        error: e,
        stackTrace: stack,
      );
      _dataErrorMessage = 'Erreur lors de l\'initialisation: $e';
      _isLoadingData = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshData() async {
    if (!_isInitialized) return;

    try {
      _isLoadingData = true;
      _dataErrorMessage = null;
      notifyListeners();

      _logger.i('Début de la mise à jour des données');

      // Mettre à jour les données des deux maisons
      try {
        final newMaison1Data = await _esp32Service.getCurrentData(
          _maison1DeviceId,
        );
        if (newMaison1Data != null) {
          _logger.i(
            'Données mises à jour pour maison1',
            error: newMaison1Data.toJson(),
          );
          maison1Data = newMaison1Data;
          await _databaseService.saveDeviceData(newMaison1Data);
        } else {
          _logger.w('Aucune donnée reçue pour maison1');
        }
      } catch (e) {
        _logger.e(
          'Erreur lors de la mise à jour des données de maison1',
          error: e,
        );
        _dataErrorMessage =
            'Erreur lors de la mise à jour des données de maison1: $e';
      }

      try {
        final newMaison2Data = await _esp32Service.getCurrentData(
          _maison2DeviceId,
        );
        if (newMaison2Data != null) {
          _logger.i(
            'Données mises à jour pour maison2',
            error: newMaison2Data.toJson(),
          );
          maison2Data = newMaison2Data;
          await _databaseService.saveDeviceData(newMaison2Data);
        } else {
          _logger.w('Aucune donnée reçue pour maison2');
        }
      } catch (e) {
        _logger.e(
          'Erreur lors de la mise à jour des données de maison2',
          error: e,
        );
        _dataErrorMessage =
            'Erreur lors de la mise à jour des données de maison2: $e';
      }

      // Vérifier les commandes en attente de manière sécurisée
      await _processPendingCommandsSafely();

      _logger.i('Mise à jour des données terminée');
      _isLoadingData = false;
      notifyListeners();
    } catch (e, stack) {
      _logger.e(
        'Erreur lors de la mise à jour des données',
        error: e,
        stackTrace: stack,
      );
      _dataErrorMessage = 'Erreur lors de la mise à jour: $e';
      _isLoadingData = false;
      notifyListeners();
    }
  }

  Future<void> _processPendingCommandsSafely() async {
    try {
      final commands = await _databaseService.getPendingCommands(
        'esp32_maison1',
      );
      for (final command in commands) {
        _logger.i('Traitement de la commande', error: command.toJson());
        await _esp32Service.sendCommandToDevice(command);
      }
    } catch (e) {
      _logger.e('Erreur lors du traitement des commandes', error: e);
    }
  }

  // Méthodes pour contrôler les relais
  Future<void> controlRelay({
    required String maisonId,
    required int relayNumber,
    required bool status,
  }) async {
    try {
      await _esp32Service.controlRelay(
        maisonId: maisonId,
        relayNumber: relayNumber,
        status: status,
      );
      await refreshData();
    } catch (e) {
      _logger.e('Erreur lors du contrôle du relais', error: e);
      _dataErrorMessage = 'Erreur lors du contrôle du relais: $e';
      notifyListeners();
      rethrow;
    }
  }

  // Méthode pour recharger l'énergie
  Future<void> rechargeEnergy({
    required String maisonId,
    required double energyAmount,
  }) async {
    try {
      _isLoadingData = true;
      _dataErrorMessage = null;
      notifyListeners();

      await _esp32Service.rechargeEnergy(
        maisonId: maisonId,
        energyAmount: energyAmount,
      );

      // Rafraîchir les données après la recharge
      await refreshData();

      _isLoadingData = false;
      notifyListeners();
    } catch (e) {
      _logger.e('Erreur lors de la recharge d\'énergie', error: e);
      _dataErrorMessage = 'Erreur lors de la recharge: $e';
      _isLoadingData = false;
      notifyListeners();
      // Ne pas propager l'erreur pour éviter le crash
    }
  }

  Future<void> fetchSensorData(String maisonId) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/data/$maisonId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (maisonId == 'maison1') {
          maison1Data = DeviceData.fromJson(data);
        } else if (maisonId == 'maison2') {
          maison2Data = DeviceData.fromJson(data);
        }

        notifyListeners();
      } else {
        _logger.e(
          'Erreur lors de la récupération des données',
          error: response.statusCode,
        );
        _dataErrorMessage =
            'Erreur lors de la récupération des données : ${response.statusCode}';
        notifyListeners();
      }
    } catch (e) {
      _logger.e('Erreur réseau', error: e);
      _dataErrorMessage = 'Erreur réseau : $e';
      notifyListeners();
    }
  }
}
