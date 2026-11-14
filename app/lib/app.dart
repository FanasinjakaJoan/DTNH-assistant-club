import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/settings/settings_controller.dart';
import 'features/shell/home_shell.dart';

/// Racine de l'application.
class DtnhApp extends ConsumerWidget {
  const DtnhApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Maintient la session Google à jour (et alimente l'auteur du pointage)
    // dès le premier frame, y compris après un rechargement de page web.
    ref.watch(authControllerProvider);

    return MaterialApp(
      title: 'DTNH Assistant Club',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: settings.hasAuthor
            ? const HomeShell(key: ValueKey('home'))
            : const LoginScreen(key: ValueKey('login')),
      ),
    );
  }
}
