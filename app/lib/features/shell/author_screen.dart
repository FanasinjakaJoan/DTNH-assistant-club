import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../di/providers.dart';
import '../settings/demo_seed.dart';
import '../settings/settings_controller.dart';

/// Premier lancement : identification de l'auteur du pointage.
///
/// Pas de compte, pas de mot de passe : le club fonctionne avec une confiance
/// interne. Le nom sert uniquement de traçabilité dans Google Sheets.
class AuthorScreen extends ConsumerStatefulWidget {
  const AuthorScreen({super.key});

  @override
  ConsumerState<AuthorScreen> createState() => _AuthorScreenState();
}

class _AuthorScreenState extends ConsumerState<AuthorScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _seedRoster = true;
  bool _isSubmitting = false;

  static const List<String> _suggestions = <String>[
    'Coach Tojo',
    'Coach Naina',
    'Président',
    'Trésorier',
    'Secrétaire',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    gradient: AppColors.orangeGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.sports_basketball_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'DTNH Assistant Club',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Dream Team New Hope · présences & finances, même sans réseau.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Qui utilise ce téléphone ?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Ce nom sera enregistré comme auteur de chaque pointage '
                        'et de chaque transaction.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.words,
                        autofocus: false,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Votre nom',
                          hintText: 'Ex : Coach Tojo',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final suggestion in _suggestions)
                            ActionChip(
                              label: Text(
                                suggestion,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              onPressed: () {
                                _controller.text = suggestion;
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _seedRoster,
                        activeColor: AppColors.orange,
                        onChanged: (value) =>
                            setState(() => _seedRoster = value),
                        title: const Text(
                          'Pré-remplir l\'effectif',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          '40 joueurs de démonstration dans les 4 catégories',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      LoadingButton(
                        label: _isSubmitting ? 'Préparation…' : 'Commencer',
                        icon: Icons.arrow_forward_rounded,
                        loading: _isSubmitting,
                        onPressed: _canSubmit ? _submit : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 14,
                      color: Colors.white54,
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Aucune connexion requise. La synchronisation Google '
                        'Sheets se configure ensuite dans les réglages.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _canSubmit => _controller.text.trim().isNotEmpty && !_isSubmitting;

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    await ref.read(settingsProvider.notifier).setAuthor(_controller.text);
    if (_seedRoster) {
      await DemoSeed(ref.read(playerRepositoryProvider)).seedRosterIfEmpty();
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);
  }
}
