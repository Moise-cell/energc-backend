import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'providers/energy_provider.dart';
import 'services/database_service.dart';
import 'dart:developer';
import 'package:logger/logger.dart';

final logger = Logger();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env'); // Charge les variables d'environnement

  final dbService = DatabaseService();
  try {
    await dbService.initialize();
    final utilisateurs = await dbService.getUtilisateurs();
    log('Utilisateurs : $utilisateurs');
    logger.d('Utilisateurs : $utilisateurs');
  } catch (e) {
    log(
      'Erreur de connexion à la base de données : $e',
      level: 1000,
    ); // Niveau d'erreur élevé
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => EnergyProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EnergC',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const WelcomePage(),
    );
  }
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Liste des utilisateurs et mots de passe
  final Map<String, String> _users = {
    'proprietaire': '1234',
    'maison1': 'abcd',
    'maison2': 'efgh',
  };

  void _login() async {
    final name = _nameController.text;
    final password = _passwordController.text;

    if (_users.containsKey(name) && _users[name] == password) {
      // Initialiser le provider avant de naviguer
      await Provider.of<EnergyProvider>(context, listen: false).initialize();

      if (!mounted) return; // Vérifiez si le widget est toujours monté

      if (name == 'proprietaire') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const OwnerDashboard()),
        );
      } else if (name == 'maison1') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => const MaisonPage(
                  maisonId: 'maison1',
                  maisonName: 'Maison 1',
                ),
          ),
        );
      } else if (name == 'maison2') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => const MaisonPage(
                  maisonId: 'maison2',
                  maisonName: 'Maison 2',
                ),
          ),
        );
      }
    } else {
      if (!mounted) return; // Vérifiez si le widget est toujours monté
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom ou mot de passe incorrect')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)], // Bleu classique
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo de l'application
                const Icon(Icons.flash_on, size: 100, color: Colors.white),
                const SizedBox(height: 16),

                // Titre de l'application
                const Text(
                  'EnergC',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // Sous-titre
                const Text(
                  'Gestion intelligente de l\'énergie',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.white70),
                ),
                const SizedBox(height: 40),

                // Carte de connexion
                Card(
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        // Champ Nom d'utilisateur
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Nom d\'utilisateur',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Champ Mot de passe
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Bouton Se connecter
                        ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            backgroundColor: const Color(
                              0xFF0D47A1,
                            ), // Bleu foncé
                          ),
                          child: const Text(
                            'Se connecter',
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Texte de bas de page
                const Text(
                  '© 2025 EnergC. Tous droits réservés.',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OwnerDashboard extends StatelessWidget {
  const OwnerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord du propriétaire'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
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
                  _buildHouseCard(
                    context: context,
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
                  _buildHouseCard(
                    context: context,
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
                          _buildStatRow(
                            icon: Icons.bolt,
                            title: 'Énergie totale',
                            value:
                                '${((maison1Data?.energy1 ?? 0.0) + (maison2Data?.energy2 ?? 0.0)).toStringAsFixed(2)} kWh',
                          ),
                          const Divider(),
                          _buildStatRow(
                            icon: Icons.electric_meter,
                            title: 'Tension moyenne',
                            value:
                                '${((maison1Data?.voltage ?? 0.0) + (maison2Data?.voltage ?? 0.0)) / 2} V',
                          ),
                          const Divider(),
                          _buildStatRow(
                            icon: Icons.power,
                            title: 'Courant total',
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

  Widget _buildHouseCard({
    required BuildContext context,
    required String title,
    required double energy,
    required double voltage,
    required double current,
    required bool relayStatus,
    required VoidCallback onRecharge,
    required ValueChanged<bool> onRelayToggle,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: relayStatus,
                  onChanged: onRelayToggle,
                  activeColor: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildEnergyIndicator(
                  icon: Icons.bolt,
                  title: 'Énergie',
                  value: '${energy.toStringAsFixed(2)} kWh',
                ),
                _buildEnergyIndicator(
                  icon: Icons.electric_meter,
                  title: 'Tension',
                  value: '${voltage.toStringAsFixed(1)} V',
                ),
                _buildEnergyIndicator(
                  icon: Icons.power,
                  title: 'Courant',
                  value: '${current.toStringAsFixed(2)} A',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: onRecharge,
                  icon: const Icon(Icons.add),
                  label: const Text('Recharger'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyIndicator({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 30),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
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
}

class MaisonPage extends StatelessWidget {
  final String maisonId;
  final String maisonName;

  const MaisonPage({
    super.key,
    required this.maisonId,
    required this.maisonName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(maisonName),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
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
              maisonId == 'maison1'
                  ? provider.maison1Data
                  : provider.maison2Data;

          if (deviceData == null) {
            return const Center(child: Text('Aucune donnée disponible'));
          }

          final energy =
              maisonId == 'maison1' ? deviceData.energy1 : deviceData.energy2;

          final current =
              maisonId == 'maison1' ? deviceData.current1 : deviceData.current2;

          final relayStatus =
              maisonId == 'maison1'
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
                          _buildStatRow(
                            icon: Icons.electric_meter,
                            title: 'Tension',
                            value: '${deviceData.voltage.toStringAsFixed(1)} V',
                          ),
                          const Divider(),
                          _buildStatRow(
                            icon: Icons.power,
                            title: 'Courant',
                            value: '${current.toStringAsFixed(2)} A',
                          ),
                          const Divider(),
                          _buildStatRow(
                            icon: Icons.power_settings_new,
                            title: 'État du relais',
                            value: relayStatus ? 'Activé' : 'Désactivé',
                            valueColor: relayStatus ? Colors.green : Colors.red,
                          ),
                          const Divider(),
                          _buildStatRow(
                            icon: Icons.update,
                            title: 'Dernière mise à jour',
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

  Widget _buildStatRow({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
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
}
