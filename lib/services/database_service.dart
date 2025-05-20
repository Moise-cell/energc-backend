import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/device_data.dart';
import '../models/device_command.dart';
import '../config/api_config.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  // Méthode vide pour compatibilité avec ServiceLocator
  Future<void> initialize() async {}

  // Méthode vide pour compatibilité avec ServiceLocator
  Future<void> close() async {}

  // Récupérer les données d'une maison
  Future<DeviceData?> getDeviceData(String maisonId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/data/$maisonId/latest');
    final response = await http.get(
      url,
      headers: {'x-api-key': ApiConfig.apiKey},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return DeviceData.fromJson(data);
    } else {
      print('Erreur lors de la récupération des données: ${response.body}');
      return null;
    }
  }

  // Envoyer de nouvelles données (insertion)
  Future<bool> insertDeviceData(DeviceData data) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/data');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ApiConfig.apiKey,
      },
      body: jsonEncode(data.toJson()),
    );
    return response.statusCode == 200;
  }

  // Récupérer les commandes en attente pour un device
  Future<List<DeviceCommand>> getPendingCommands(String deviceId) async {
    final url = Uri.parse(
      '${ApiConfig.baseUrl}/api/commands?deviceId=$deviceId',
    );
    final response = await http.get(
      url,
      headers: {'x-api-key': ApiConfig.apiKey},
    );

    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((e) => DeviceCommand.fromJson(e)).toList();
    } else {
      print('Erreur lors de la récupération des commandes: ${response.body}');
      return [];
    }
  }

  // Insérer une commande
  Future<bool> insertCommand(DeviceCommand command) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/commands');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ApiConfig.apiKey,
      },
      body: jsonEncode(command.toJson()),
    );
    return response.statusCode == 200;
  }

  // Marquer une commande comme exécutée
  Future<bool> markCommandAsExecuted(int commandId) async {
    final url = Uri.parse(
      '${ApiConfig.baseUrl}/api/commands/$commandId/execute',
    );
    final response = await http.patch(
      url,
      headers: {'x-api-key': ApiConfig.apiKey},
    );
    return response.statusCode == 200;
  }

  // Authentification utilisateur (exemple)
  Future<Map<String, dynamic>?> getUserByCredentials(
    String username,
    String password,
  ) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/login');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ApiConfig.apiKey,
      },
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  // Récupérer tous les utilisateurs
  Future<List<Map<String, dynamic>>> getUtilisateurs() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/utilisateurs');
    final response = await http.get(
      url,
      headers: {'x-api-key': ApiConfig.apiKey},
    );
    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(list);
    }
    return [];
  }

  // Récupérer les dernières données d'un device
  Future<DeviceData?> getLatestDeviceData(String deviceId) async {
    // On suppose que tu as un endpoint qui retourne la dernière donnée pour un deviceId
    final url = Uri.parse('${ApiConfig.baseUrl}/api/data/$deviceId/latest');
    final response = await http.get(
      url,
      headers: {'x-api-key': ApiConfig.apiKey},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return DeviceData.fromJson(data);
    } else {
      print(
        'Erreur lors de la récupération de la dernière donnée: ${response.body}',
      );
      return null;
    }
  }
}
