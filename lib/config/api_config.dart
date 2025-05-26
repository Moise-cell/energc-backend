import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration des API utilisées dans l'application
class ApiConfig {
  /// URL de base de l'API
  /// Charge depuis les variables d'environnement ou utilise une valeur par défaut
  static const String baseUrl = 'https://energc-server.onrender.com';

  /// Clé API pour l'authentification
  static const String apiKey = 'esp32_secret_key';

  /// Délai d'attente des requêtes en millisecondes
  static const int timeout = 5000; // 5 secondes

  static const Map<String, String> headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
}
