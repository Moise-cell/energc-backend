import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration des API utilisées dans l'application
class ApiConfig {
  /// URL de base de l'API
  /// Charge depuis les variables d'environnement ou utilise une valeur par défaut
  static String get baseUrl {
    final envUrl = dotenv.env['BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      // Pour Render.com, on utilise toujours HTTPS
      return envUrl.startsWith('https://') ? envUrl : 'https://$envUrl';
    }
    return 'https://energc-backend.onrender.com';  // URL par défaut pour Render
  }

  /// Clé API pour l'authentification
  static String get apiKey {
    return dotenv.env['API_KEY'] ?? 'esp32_secret_key';
  }

  /// Délai d'attente des requêtes en millisecondes
  static const Duration timeout = Duration(seconds: 10);
}
