import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/energy_provider.dart';
import '../../services/auth_service.dart';
import '../widgets/stat_row.dart';

class MaisonScreen extends StatefulWidget {
  final String maisonId;
  final String maisonName;

  const MaisonScreen({
    super.key,
    required this.maisonId,
    required this.maisonName,
  });

  @override
  State<MaisonScreen> createState() => _MaisonScreenState();
}

class _MaisonScreenState extends State<MaisonScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<EnergyProvider>(context, listen: false).refreshData();
    });
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/welcome');
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Il y a ${difference.inSeconds} secondes';
    } else if (difference.inMinutes < 60) {
      return 'Il y a ${difference.inMinutes} minutes';
    } else if (difference.inHours < 24) {
      return 'Il y a ${difference.inHours} heures';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.maisonName),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Déconnexion',
          ),
        ],
      ),
      body: Consumer<EnergyProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Erreur: ${provider.errorMessage}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.refreshData(),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }

          final deviceData =
              widget.maisonId == 'maison1'
                  ? provider.maison1Data
                  : provider.maison2Data;

          if (deviceData == null) {
            return const Center(child: Text('Aucune donnée disponible'));
          }

          final energy =
              widget.maisonId == 'maison1'
                  ? deviceData.energy1
                  : deviceData.energy2;

          final current =
              widget.maisonId == 'maison1'
                  ? deviceData.current1
                  : deviceData.current2;

          final relayStatus =
              widget.maisonId == 'maison1'
                  ? deviceData.relay1Status
                  : deviceData.relay2Status;

          return RefreshIndicator(
            onRefresh: () => provider.refreshData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Carte d'énergie
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Text(
                            'Énergie disponible',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${energy.toStringAsFixed(2)} kWh',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value:
                                energy /
                                100, // Supposons que 100 kWh est le maximum
                            minHeight: 10,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              energy > 20 ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Statistiques détaillées
                  const Text(
                    'Statistiques détaillées',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          StatRow(
                            label: 'Tension',
                            value: '${deviceData.voltage.toStringAsFixed(1)} V',
                          ),
                          const Divider(),
                          StatRow(
                            label: 'Courant',
                            value: '${current.toStringAsFixed(2)} A',
                          ),
                          const Divider(),
                          StatRow(
                            label: 'État du relais',
                            value: relayStatus ? 'Activé' : 'Désactivé',
                          ),
                          const Divider(),
                          StatRow(
                            label: 'Dernière mise à jour',
                            value: _formatDateTime(deviceData.timestamp),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
