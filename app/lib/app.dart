import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/settings/settings_controller.dart';
import 'features/shell/author_screen.dart';
import 'features/shell/home_shell.dart';

/// Racine de l'application.
class DtnhApp extends ConsumerWidget {
  const DtnhApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'DTNH Assistant Club',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: settings.hasAuthor
            ? const HomeShell(key: ValueKey('home'))
            : const AuthorScreen(key: ValueKey('author')),
      ),
    );
  }
}
