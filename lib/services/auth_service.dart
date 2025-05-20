import 'dart:convert';
import 'database_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class User {
  final String id;
  final String username;
  final String userType; // 'proprietaire', 'maison1', 'maison2'

  User({required this.id, required this.username, required this.userType});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      userType: json['user_type'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'username': username, 'userType': userType};
  }
}

/// Service d'authentification pour gérer les utilisateurs
class AuthService {
  static final AuthService _instance = AuthService._internal();
  final DatabaseService _databaseService = DatabaseService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  User? _currentUser;

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
    await _tryRestoreSession();
  }

  /// Tente de restaurer la session utilisateur à partir du stockage sécurisé
  Future<bool> _tryRestoreSession() async {
    try {
      final userJson = await _secureStorage.read(key: 'current_user');
      if (userJson != null) {
        _currentUser = User.fromJson(jsonDecode(userJson));
        return true;
      }
    } catch (e) {
      print('Erreur lors de la restauration de la session: $e');
    }
    return false;
  }

  /// Connecte un utilisateur avec ses identifiants
  Future<User?> login(String username, String password) async {
    try {
      // Provisoire: Pour des tests rapides sans base de données
      if (_isHardcodedUser(username, password)) {
        final userType = username;
        final user = User(id: userType, username: username, userType: userType);
        _currentUser = user;

        // Sauvegarder l'utilisateur dans le stockage sécurisé
        await _secureStorage.write(
          key: 'current_user',
          value: jsonEncode(user.toJson()),
        );

        return user;
      }

      // Authentification via base de données
      final userData = await _databaseService.getUserByCredentials(
        username,
        password,
      );

      if (userData != null) {
        final user = User.fromJson(userData);
        _currentUser = user;

        // Sauvegarder l'utilisateur dans le stockage sécurisé
        await _secureStorage.write(
          key: 'current_user',
          value: jsonEncode(user.toJson()),
        );

        return user;
      }
    } catch (e) {
      print('Erreur lors de la connexion: $e');
      throw Exception('Erreur lors de la connexion: $e');
    }

    return null;
  }

  /// Déconnecte l'utilisateur actuel
  Future<void> logout() async {
    _currentUser = null;
    await _secureStorage.delete(key: 'current_user');
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
