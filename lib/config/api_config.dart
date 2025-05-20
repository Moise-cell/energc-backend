import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration des API utilisées dans l'application
class ApiConfig {
  /// URL de base de l'API
  /// Charge depuis les variables d'environnement ou utilise une valeur par défaut
  static String get baseUrl =>
      dotenv.env['BASE_URL'] ??
      "http://192.168.x.x:3000"; // Mets ici l'URL de ton backend Node.js

  /// Clé API pour l'authentification
  static String get apiKey => dotenv.env['API_KEY'] ?? '';

  /// Délai d'attente des requêtes en millisecondes
  static const int timeoutDuration = 30000; // 30 secondes
}
