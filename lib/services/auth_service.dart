import 'dart:convert';
import 'database_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

class User {
  final String id;
  final String username;
  final String userType; // 'proprietaire', 'maison1', 'maison2'

  User({required this.id, required this.username, required this.userType});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? json['username']?.toString() ?? 'unknown',
      username: json['username']?.toString() ?? 'unknown',
      userType: json['user_type']?.toString() ?? json['userType']?.toString() ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'userType': userType,
      'user_type': userType, // Pour la compatibilité avec l'API
    };
  }
}

/// Service d'authentification pour gérer les utilisateurs
class AuthService {
  static final AuthService _instance = AuthService._internal();
  final DatabaseService _databaseService = DatabaseService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final _logger = Logger();

  User? _currentUser;
  bool _isInitialized = false;

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  /// Utilisateur actuellement connecté
  User? get currentUser => _currentUser;

  /// Vérifie si un utilisateur est connecté
  bool get isLoggedIn => _currentUser != null;

  /// Initialise le service et essaie de restaurer la session
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _tryRestoreSession();
      _isInitialized = true;
    } catch (e) {
      _logger.e('Erreur lors de l\'initialisation du service d\'authentification', error: e);
      rethrow;
    }
  }

  /// Tente de restaurer la session utilisateur à partir du stockage sécurisé
  Future<bool> _tryRestoreSession() async {
    try {
      final userJson = await _secureStorage.read(key: 'current_user');
      if (userJson == null) {
        _logger.i('Aucune session utilisateur trouvée');
        return false;
      }

      final userData = jsonDecode(userJson);
      if (userData is! Map<String, dynamic>) {
        _logger.w('Format de données utilisateur invalide');
        await _secureStorage.delete(key: 'current_user');
        return false;
      }

      // Vérifier que tous les champs requis sont présents et non nuls
      if (!userData.containsKey('id') || 
          !userData.containsKey('username') || 
          !userData.containsKey('userType') ||
          userData['id'] == null ||
          userData['username'] == null ||
          userData['userType'] == null) {
        _logger.w('Données utilisateur incomplètes ou nulles');
        await _secureStorage.delete(key: 'current_user');
        return false;
      }

      _currentUser = User.fromJson(userData);
      _logger.i('Session restaurée pour l\'utilisateur: ${_currentUser?.username}');
      return true;
    } catch (e) {
      _logger.e('Erreur lors de la restauration de la session', error: e);
      await _secureStorage.delete(key: 'current_user');
      return false;
    }
  }

  /// Connecte un utilisateur avec ses identifiants
  Future<User?> login(String username, String password) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      User? user;
      
      // Vérifier d'abord les utilisateurs codés en dur
      if (_isHardcodedUser(username, password)) {
        user = User(
          id: username,
          username: username,
          userType: username,
        );
      } else {
        // Authentification via base de données
        final userData = await _databaseService.getUserByCredentials(
          username,
          password,
        );

        if (userData != null) {
          user = User.fromJson(userData);
        }
      }

      if (user != null) {
        _currentUser = user;
        await _secureStorage.write(
          key: 'current_user',
          value: jsonEncode(user.toJson()),
        );
        _logger.i('Utilisateur connecté: ${user.username}');
        return user;
      }

      _logger.w('Échec de la connexion pour l\'utilisateur: $username');
      return null;
    } catch (e) {
      _logger.e('Erreur lors de la connexion', error: e);
      rethrow;
    }
  }

  /// Déconnecte l'utilisateur actuel
  Future<void> logout() async {
    try {
      if (_currentUser != null) {
        _logger.i('Déconnexion de l\'utilisateur: ${_currentUser?.username}');
      }
      _currentUser = null;
      await _secureStorage.delete(key: 'current_user');
    } catch (e) {
      _logger.e('Erreur lors de la déconnexion', error: e);
      rethrow;
    }
  }

  /// Vérifie si les identifiants correspondent à un utilisateur codé en dur
  /// À utiliser uniquement temporairement ou pour le développement
  bool _isHardcodedUser(String username, String password) {
    final Map<String, String> hardcodedUsers = {
      'proprietaire': '1234',
      'maison1': 'abcd',
      'maison2': 'efgh',
    };

    return hardcodedUsers.containsKey(username) &&
        hardcodedUsers[username] == password;
  }
}
