import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/database_service.dart';

Future<void> main() async {
  // Charger les variables d'environnement
  await dotenv.load(fileName: '.env');

  // Initialiser la base de données
  final dbService = DatabaseService();
  await dbService.initialize();

  // Configurer les routes
  final router = Router();

  router.post('/api/data', (Request request) async {
    final payload = await request.readAsString();
    // Traitez les données ici et insérez-les dans la base de données
    return Response.ok('Données reçues : $payload');
  });

  // Démarrer le serveur
  final handler = Pipeline().addMiddleware(logRequests()).addHandler(router);
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);

  print('Serveur démarré sur http://${server.address.host}:${server.port}');
}
