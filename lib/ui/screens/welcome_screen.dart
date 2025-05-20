import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/energy_provider.dart';
import '../../services/auth_service.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<EnergyProvider>(context, listen: false).refreshData();
    });
  }

  void _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final name = _nameController.text.trim();
      final password = _passwordController.text;

      if (name.isEmpty || password.isEmpty) {
        setState(() {
          _errorMessage = 'Veuillez remplir tous les champs';
          _isLoading = false;
        });
        return;
      }

      final user = await _authService.login(name, password);

      if (!mounted) return; // Vérifiez si le widget est toujours monté

      if (user != null) {
        // Initialiser le provider avant de naviguer
        await Provider.of<EnergyProvider>(context, listen: false).initialize();

        if (!mounted) return; // Vérifier à nouveau

        switch (user.userType) {
          case 'proprietaire':
            Navigator.pushReplacementNamed(context, '/owner');
            break;
          case 'maison1':
            Navigator.pushReplacementNamed(context, '/maison1');
            break;
          case 'maison2':
            Navigator.pushReplacementNamed(context, '/maison2');
            break;
          default:
            setState(() {
              _errorMessage = 'Type d\'utilisateur non reconnu';
              _isLoading = false;
            });
        }
      } else {
        setState(() {
          _errorMessage = 'Nom d\'utilisateur ou mot de passe incorrect';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors de la connexion: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
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
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

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
                          textInputAction: TextInputAction.next,
                          enabled: !_isLoading,
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
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 24),

                        // Bouton Se connecter
                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child:
                              _isLoading
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Text(
                                    'Se connecter',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.white,
                                    ),
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
