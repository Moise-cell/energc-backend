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
    // Planifie l'appel de refreshData après le premier rendu du frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<EnergyProvider>(context, listen: false).refreshData();
    });
  }

  Future<void> _logout() async {
    try {
      await _authService.logout();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/welcome');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la déconnexion: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showRechargeDialog(BuildContext context, String maisonId) {
    final TextEditingController controller = TextEditingController();
    final provider = Provider.of<EnergyProvider>(context, listen: false);
    final currentEnergy = maisonId == 'maison1' 
        ? provider.maison1Data?.energy1 ?? 0.0 
        : provider.maison2Data?.energy2 ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Recharger ${maisonId == 'maison1' ? 'Maison 1' : 'Maison 2'}',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Énergie actuelle: ${currentEnergy.toStringAsFixed(2)} kWh',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Quantité d\'énergie à ajouter (kWh)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.add_circle_outline),
                ),
              ),
            ],
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${amount.toStringAsFixed(2)} kWh ajoutés à ${maisonId == 'maison1' ? 'Maison 1' : 'Maison 2'}'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Veuillez entrer une valeur valide supérieure à 0'),
                    backgroundColor: Colors.red,
                  ),
                );
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
        title: const Text('Tableau de bord'),
        actions: [
          Consumer<EnergyProvider>(
            builder: (context, provider, child) {
              return IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: provider.isLoadingData ? null : () {
                  provider.refreshData();
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Consumer<EnergyProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingData) {
            return const Center(child: CircularProgressIndicator());
          } else if (provider.dataErrorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    provider.dataErrorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      provider.refreshData();
                    },
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          } else {
            return RefreshIndicator(
              onRefresh: () => provider.refreshData(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
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
                              energy: provider.maison1Data?.energy1 ?? 0.0,
                              voltage: provider.maison1Data?.voltage ?? 0.0,
                              current: provider.maison1Data?.current1 ?? 0.0,
                              relayStatus: provider.maison1Data?.relay1Status ?? false,
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
                              energy: provider.maison2Data?.energy2 ?? 0.0,
                              voltage: provider.maison2Data?.voltage ?? 0.0,
                              current: provider.maison2Data?.current2 ?? 0.0,
                              relayStatus: provider.maison2Data?.relay2Status ?? false,
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
                                          '${((provider.maison1Data?.energy1 ?? 0.0) + (provider.maison2Data?.energy2 ?? 0.0)).toStringAsFixed(2)} kWh',
                                      icon: Icons.battery_charging_full,
                                    ),
                                    const Divider(),
                                    StatRow(
                                      label: 'Tension moyenne',
                                      value:
                                          '${(((provider.maison1Data?.voltage ?? 0.0) + (provider.maison2Data?.voltage ?? 0.0)) / 2).toStringAsFixed(2)} V',
                                      icon: Icons.electric_bolt,
                                    ),
                                    const Divider(),
                                    StatRow(
                                      label: 'Courant total',
                                      value:
                                          '${((provider.maison1Data?.current1 ?? 0.0) + (provider.maison2Data?.current2 ?? 0.0)).toStringAsFixed(2)} A',
                                      icon: Icons.power,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          }
        },
      ),
    );
  }
}
