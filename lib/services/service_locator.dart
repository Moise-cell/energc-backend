import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'database_service.dart';
import 'esp32_service.dart';

/// Classe singleton pour gérer l'initialisation et l'accès à tous les services de l'application
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();

  factory ServiceLocator() {
    return _instance;
  }

  ServiceLocator._internal();

  final DatabaseService _databaseService = DatabaseService();
  final ESP32Service _esp32Service = ESP32Service();

  bool _isInitialized = false;

  /// Initialise tous les services requis par l'application
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Vérifier que les variables d'environnement sont chargées
      if (dotenv.env['BASE_URL'] == null) {
        throw StateError('Les variables d\'environnement ne sont pas chargées. Vérifiez que le fichier .env existe et contient BASE_URL.');
      }

      // Initialisation des services
      await _databaseService.initialize();
      await _esp32Service.initialize();

      _isInitialized = true;
      debugPrint(
        'ServiceLocator: Tous les services ont été initialisés avec succès',
      );
    } catch (e) {
      debugPrint(
        'ServiceLocator: Erreur lors de l\'initialisation des services: $e',
      );
      rethrow;
    }
  }

  /// Accès au service de base de données
  DatabaseService get databaseService {
    _ensureInitialized();
    return _databaseService;
  }

  /// Accès au service ESP32
  ESP32Service get esp32Service {
    _ensureInitialized();
    return _esp32Service;
  }

  /// Vérifie que les services sont initialisés
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'ServiceLocator n\'a pas été initialisé. Appelez initialize() d\'abord.',
      );
    }
  }

  /// Ferme proprement tous les services
  Future<void> dispose() async {
    if (!_isInitialized) return;

    await _databaseService.close();
    _esp32Service.dispose();

    _isInitialized = false;
    debugPrint('ServiceLocator: Tous les services ont été fermés');
  }
}
