import 'package:flutter/foundation.dart';
import '../models/device_data.dart';
import '../services/database_service.dart';
import '../models/device_command.dart';

class EnergyProvider extends ChangeNotifier {
  DeviceData? maison1Data;
  DeviceData? maison2Data;
  bool isLoading = true;
  String? errorMessage;

  Future<void> initialize() async {
    try {
      isLoading = true;
      notifyListeners();

      maison1Data = await DatabaseService().getDeviceData('maison1');
      print(
        'Données pour maison1 : $maison1Data',
      ); // Log des données pour maison1

      maison2Data = await DatabaseService().getDeviceData('maison2');
      print(
        'Données pour maison2 : $maison2Data',
      ); // Log des données pour maison2

      isLoading = false;
      notifyListeners();
    } catch (e, stackTrace) {
      errorMessage = 'Erreur lors de la récupération des données : $e';
      print('Erreur : $e\nStackTrace : $stackTrace');
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshData() async {
    await initialize(); // Recharge les données
  }

  Future<void> controlRelay({
    required String maisonId,
    required int relayNumber,
    required bool status,
  }) async {
    try {
      final command = DeviceCommand(
        deviceId: 'esp32_main',
        commandType: 'TOGGLE_RELAY',
        parameters: {'relay': relayNumber, 'status': status},
        timestamp: DateTime.now(),
        executed: false,
      );

      await DatabaseService().insertCommand(command);

      // Mettez à jour l'état local
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
}
