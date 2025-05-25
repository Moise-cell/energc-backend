import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration des API utilisées dans l'application
class ApiConfig {
  /// URL de base de l'API
  /// Charge depuis les variables d'environnement ou utilise une valeur par défaut
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://energc-backend.onrender.com',
  );

  /// Clé API pour l'authentification
  static String get apiKey {
    return dotenv.env['API_KEY'] ?? 'esp32_secret_key';
  }

  /// Délai d'attente des requêtes en millisecondes
  static const int timeout = 30000; // 30 seconds

  static const Map<String, String> headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
}
