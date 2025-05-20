import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'providers/energy_provider.dart';
import 'package:logger/logger.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/screens/owner_dashboard.dart';
import 'ui/screens/maison_screen.dart';
import 'ui/theme/app_theme.dart';

final logger = Logger();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(); // Charge .env AVANT tout accès à ApiConfig/baseUrl
  print('BASE_URL chargé : ${dotenv.env['BASE_URL']}');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => EnergyProvider()),
      ],
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
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const WelcomeScreen(),
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/owner': (context) => const OwnerDashboard(),
        '/maison1':
            (context) =>
                const MaisonScreen(maisonId: 'maison1', maisonName: 'Maison 1'),
        '/maison2':
            (context) =>
                const MaisonScreen(maisonId: 'maison2', maisonName: 'Maison 2'),
      },
    );
  }
}
