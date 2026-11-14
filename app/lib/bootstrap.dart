import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'data/local/local_database.dart';
import 'di/providers.dart';
import 'sync/background_worker.dart';

/// Démarrage : ouvre la base locale **avant** le premier frame.
///
/// L'application est offline-first : aucun appel réseau n'est nécessaire pour
/// afficher les écrans, ce qui garantit un lancement instantané au bord du
/// terrain même en zone blanche.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final database = await LocalDatabase.open();

    // Authentification Google : initialisée seulement si la clé est présente.
    // Un échec ici ne doit jamais empêcher l'application de démarrer — le mode
    // local reste le socle de fonctionnement hors-ligne.
    try {
      if (AppConfig.supabaseAnonKey.trim().isNotEmpty) {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
          // Sur le web, Supabase lit les jetons du retour OAuth dans l'URL.
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.pkce,
          ),
        );
      }
    } catch (error, stack) {
      debugPrint('Supabase Auth indisponible : $error\n$stack');
    }

    // La synchronisation de fond est optionnelle : si le plugin échoue
    // (émulateur, iOS sans capability), l'app reste pleinement utilisable.
    try {
      await registerBackgroundSync();
    } catch (error, stack) {
      debugPrint('Background sync indisponible : $error\n$stack');
    }

    runApp(
      ProviderScope(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
        ],
        child: const DtnhApp(),
      ),
    );
  } catch (error) {
    runApp(_StartupErrorApp(error: error));
  }
}

/// Écran de secours si la base locale ne peut pas s'ouvrir (stockage plein...).
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.storage_rounded, size: 40),
                const SizedBox(height: 16),
                const Text(
                  'Impossible d\'ouvrir le stockage local',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Fermez l\'application puis relancez-la. Si le problème '
                  'persiste, vérifiez l\'espace disponible sur le téléphone.',
                ),
                const SizedBox(height: 16),
                Text(
                  '$error',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
