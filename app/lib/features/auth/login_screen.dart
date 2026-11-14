import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../settings/demo_seed.dart';
import '../settings/settings_controller.dart';
import '../../di/providers.dart';
import 'auth_controller.dart';

/// Écran de connexion (Google) **ou** identification locale.
///
/// Choix de conception : la connexion Google est **recommandée mais jamais
/// obligatoire**. Le club joue au bord d'un terrain sans réseau ; imposer un
/// OAuth à l'ouverture rendrait l'application inutilisable dans ce cas. Le mode
/// local reste donc accessible en un geste, et la session Google est
/// uniquement ce qui rattache les écritures à un compte réel.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _localMode = false;
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
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

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
                _buildHeader(),
                const SizedBox(height: 24),
                if (_localMode || !auth.isConfigured)
                  _buildLocalCard(context)
                else
                  _buildGoogleCard(context, auth),
                const SizedBox(height: 16),
                _buildFooter(auth),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
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
          style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildGoogleCard(BuildContext context, AuthState auth) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connexion du staff',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Connectez-vous avec le compte Google du club : votre nom sera '
            'l\'auteur de chaque pointage et de chaque transaction.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          if (auth.hasError) ...[
            const SizedBox(height: 12),
            InfoBanner(
              message: auth.error!,
              icon: Icons.error_outline_rounded,
              color: AppColors.red,
              background: AppColors.redSoft,
            ),
          ],
          const SizedBox(height: 16),
          _GoogleButton(
            loading: auth.isLoading,
            onPressed: auth.isLoading
                ? null
                : () => ref
                    .read(authControllerProvider.notifier)
                    .signInWithGoogle(),
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _localMode = true),
              child: const Text(
                'Continuer sans compte (hors-ligne)',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalCard(BuildContext context) {
    return Container(
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            AppSettings.supportsGoogleAuth
                ? 'Mode local : ce nom sera enregistré comme auteur de chaque '
                    'pointage. La connexion Google reste disponible à tout '
                    'moment dans les réglages.'
                : 'Ce nom sera enregistré comme auteur de chaque pointage et de '
                    'chaque transaction.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
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
                    _nameController.text = suggestion;
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
            onChanged: (value) => setState(() => _seedRoster = value),
            title: const Text(
              'Pré-remplir l\'effectif',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '40 joueurs de démonstration dans les 4 catégories',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 6),
          LoadingButton(
            label: _isSubmitting ? 'Préparation…' : 'Commencer',
            icon: Icons.arrow_forward_rounded,
            loading: _isSubmitting,
            onPressed: _canSubmit ? _submitLocal : null,
          ),
          if (AppSettings.supportsGoogleAuth) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => setState(() => _localMode = false),
                child: const Text(
                  'Revenir à la connexion Google',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(AuthState auth) {
    return Row(
      children: [
        const Icon(Icons.cloud_off_rounded, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            auth.isConfigured
                ? 'L\'application reste utilisable hors-ligne ; la connexion '
                    'sert à rattacher vos saisies à votre compte.'
                : 'Aucune connexion requise. La synchronisation se configure '
                    'ensuite dans les réglages.',
            style: const TextStyle(
              fontSize: 11,
              height: 1.35,
              color: Colors.white54,
            ),
          ),
        ),
      ],
    );
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty && !_isSubmitting;

  Future<void> _submitLocal() async {
    setState(() => _isSubmitting = true);
    await ref.read(settingsProvider.notifier).setAuthor(_nameController.text);
    if (_seedRoster) {
      await DemoSeed(ref.read(playerRepositoryProvider)).seedRosterIfEmpty();
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);
  }
}

/// Bouton « Continuer avec Google » aux couleurs de Google (marque).
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed, required this.loading});

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  _GoogleGlyph(),
                  SizedBox(width: 12),
                  Text(
                    'Continuer avec Google',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Glyphe « G » multicolore, dessiné sans asset (aucune dépendance réseau).
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGlyphPainter()),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  static const List<Color> _colors = <Color>[
    Color(0xFF4285F4), // bleu
    Color(0xFF34A853), // vert
    Color(0xFFFBBC05), // jaune
    Color(0xFFEA4335), // rouge
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.22;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.width - stroke) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    const quarter = 3.1415926535 / 2;
    // Quatre arcs colorés, approchant le « G » de Google.
    for (var i = 0; i < 4; i++) {
      paint.color = _colors[i];
      canvas.drawArc(rect, -quarter / 2 + i * quarter, quarter * 0.86, false, paint);
    }
    // Barre horizontale du G.
    final bar = Paint()
      ..color = _colors[3]
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(size.width * 0.55, size.height / 2),
      Offset(size.width, size.height / 2),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
