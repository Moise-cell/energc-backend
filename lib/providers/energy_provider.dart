import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:energc/models/device_data.dart';
import '../services/database_service.dart';
import '../config/api_config.dart';

class EnergyProvider extends ChangeNotifier {
  DeviceData? maison1Data;
  DeviceData? maison2Data;
  bool isLoading = true;
  String? errorMessage;

  Future<void> initialize() async {
    try {
      isLoading = true;
      notifyListeners();

      print('Avant getDeviceData maison1');
      maison1Data = await DatabaseService().getDeviceData('maison1');
      print('Après getDeviceData maison1 : $maison1Data');

      print('Avant getDeviceData maison2');
      maison2Data = await DatabaseService().getDeviceData('maison2');
      print('Après getDeviceData maison2 : $maison2Data');

      isLoading = false;
      notifyListeners();
    } catch (e, stack) {
      print('Erreur EnergyProvider.initialize: $e\n$stack');
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshData() async {
    await initialize();
  }

  Future<void> controlRelay({
    required String maisonId,
    required int relayNumber,
    required bool status,
  }) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/commands');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': maisonId,
          'commandType': 'TOGGLE_RELAY',
          'parameters': {'relay': relayNumber, 'status': status},
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }

      // Mettre à jour l'état local
      if (maisonId == 'maison1') {
        if (relayNumber == 1) {
          maison1Data = maison1Data?.copyWith(relay1Status: status);
        } else {
          maison1Data = maison1Data?.copyWith(relay2Status: status);
        }
      } else if (maisonId == 'maison2') {
        if (relayNumber == 1) {
          maison2Data = maison2Data?.copyWith(relay1Status: status);
        } else {
          maison2Data = maison2Data?.copyWith(relay2Status: status);
        }
      }

      notifyListeners();
    } catch (e) {
      errorMessage = 'Erreur lors du contrôle du relais : $e';
      notifyListeners();
    }
  }

  Future<void> rechargeEnergy({
    required String maisonId,
    required double energyAmount,
  }) async {
    if (energyAmount <= 0) {
      errorMessage = 'La quantité d\'énergie doit être supérieure à 0';
      notifyListeners();
      return;
    }

    try {
      if (maisonId == 'maison1') {
        maison1Data = maison1Data?.copyWith(
          energy1: (maison1Data?.energy1 ?? 0) + energyAmount,
        );
      } else if (maisonId == 'maison2') {
        maison2Data = maison2Data?.copyWith(
          energy2: (maison2Data?.energy2 ?? 0) + energyAmount,
        );
      }
      notifyListeners();
    } catch (e) {
      errorMessage = 'Erreur lors de la recharge : $e';
      notifyListeners();
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
        errorMessage =
            'Erreur lors de la récupération des données : ${response.statusCode}';
        notifyListeners();
      }
    } catch (e) {
      errorMessage = 'Erreur réseau : $e';
      notifyListeners();
    }
  }
}
