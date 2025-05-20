import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/energy_provider.dart';
import '../../services/auth_service.dart';
import '../widgets/house_card.dart';
import '../widgets/stat_row.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    // Charger les données au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<EnergyProvider>(context, listen: false).refreshData();
    });
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/welcome');
  }

  void _showRechargeDialog(BuildContext context, String maisonId) {
    final TextEditingController controller = TextEditingController();
    final provider = Provider.of<EnergyProvider>(context, listen: false);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Recharger ${maisonId == 'maison1' ? 'Maison 1' : 'Maison 2'}',
            ),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantité d\'énergie (kWh)',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(controller.text);
                  if (amount != null && amount > 0) {
                    provider.rechargeEnergy(
                      maisonId: maisonId,
                      energyAmount: amount,
                    );
                    Navigator.pop(context);
                  }
                },
                child: const Text('Recharger'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord du propriétaire'),
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

          final maison1Data = provider.maison1Data;
          final maison2Data = provider.maison2Data;

          return RefreshIndicator(
            onRefresh: () => provider.refreshData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'État des maisons',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Maison 1
                  HouseCard(
                    title: 'Maison 1',
                    energy: maison1Data?.energy1 ?? 0.0,
                    voltage: maison1Data?.voltage ?? 0.0,
                    current: maison1Data?.current1 ?? 0.0,
                    relayStatus: maison1Data?.relay1Status ?? false,
                    onRecharge: () => _showRechargeDialog(context, 'maison1'),
                    onRelayToggle: (value) {
                      provider.controlRelay(
                        maisonId: 'maison1',
                        relayNumber: 1,
                        status: value,
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Maison 2
                  HouseCard(
                    title: 'Maison 2',
                    energy: maison2Data?.energy2 ?? 0.0,
                    voltage: maison2Data?.voltage ?? 0.0,
                    current: maison2Data?.current2 ?? 0.0,
                    relayStatus: maison2Data?.relay2Status ?? false,
                    onRecharge: () => _showRechargeDialog(context, 'maison2'),
                    onRelayToggle: (value) {
                      provider.controlRelay(
                        maisonId: 'maison2',
                        relayNumber: 2,
                        status: value,
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Statistiques globales
                  const Text(
                    'Statistiques globales',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                            label: 'Énergie totale',
                            value:
                                '${((maison1Data?.energy1 ?? 0.0) + (maison2Data?.energy2 ?? 0.0)).toStringAsFixed(2)} kWh',
                          ),
                          const Divider(),
                          StatRow(
                            label: 'Tension moyenne',
                            value:
                                '${(((maison1Data?.voltage ?? 0.0) + (maison2Data?.voltage ?? 0.0)) / 2).toStringAsFixed(2)} V',
                          ),
                          const Divider(),
                          StatRow(
                            label: 'Courant total',
                            value:
                                '${((maison1Data?.current1 ?? 0.0) + (maison2Data?.current2 ?? 0.0)).toStringAsFixed(2)} A',
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
