import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../platform/install_prompt.dart';
import '../theme/app_colors.dart';
import 'app_card.dart';
import 'common_widgets.dart';

/// Carte « Installer l'application ».
///
/// Comportement par plateforme :
/// - **Chrome/Edge Android** : bouton qui déclenche le prompt natif PWA
///   (`beforeinstallprompt` capturé dans `web/index.html`) ;
/// - **Safari iOS** : instructions « Partager → Sur l'écran d'accueil » ;
/// - **Bureau** : message explicite (pas d'installation, mais possibilité
///   d'épingler l'onglet) + accès au téléchargement de l'APK ;
/// - **Application native** : la carte n'est pas affichée.
///
/// Aucune dépendance à un package tiers : le pont JS passe par un
/// `MethodChannel` déclaré dans `web/index.html`.
class InstallAppTile extends StatefulWidget {
  const InstallAppTile({super.key, this.showHeader = true});

  /// Affiche le `SectionHeader` au-dessus de la carte.
  final bool showHeader;

  @override
  State<InstallAppTile> createState() => _InstallAppTileState();
}

class _InstallAppTileState extends State<InstallAppTile> {
  InstallPlatform _platform = InstallPlatform.desktopBrowser;
  bool _canPrompt = false;
  bool _loading = true;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final platform = await InstallPrompt.detect();
    final canPrompt = platform == InstallPlatform.androidBrowser
        ? await InstallPrompt.canPrompt()
        : false;
    if (!mounted) return;
    setState(() {
      _platform = platform;
      _canPrompt = canPrompt;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _platform == InstallPlatform.nativeApp) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader)
          const SectionHeader(
            title: 'Installer l\'application',
            subtitle: 'Accès direct depuis l\'écran d\'accueil du téléphone',
          ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_icon, color: AppColors.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _subtitle,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_platform == InstallPlatform.installed)
                const _InstalledBanner()
              else ...[
                if (_canPrompt)
                  LoadingButton(
                    label: _installing
                        ? 'Installation…'
                        : 'Installer sur cet appareil',
                    icon: Icons.download_for_offline_rounded,
                    loading: _installing,
                    onPressed: _installNow,
                  )
                else
                  _ManualSteps(platform: _platform),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: _downloadApk,
                    icon: const Icon(Icons.android_rounded, size: 18),
                    label: const Text('Télécharger l\'application Android (APK)'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  IconData get _icon {
    switch (_platform) {
      case InstallPlatform.installed:
        return Icons.verified_rounded;
      case InstallPlatform.iosBrowser:
        return Icons.phone_iphone_rounded;
      case InstallPlatform.androidBrowser:
        return Icons.add_to_home_screen_rounded;
      case InstallPlatform.desktopBrowser:
        return Icons.desktop_windows_rounded;
      case InstallPlatform.nativeApp:
        return Icons.phone_android_rounded;
    }
  }

  String get _title {
    switch (_platform) {
      case InstallPlatform.installed:
        return 'Application installée';
      case InstallPlatform.iosBrowser:
        return 'Ajouter à l\'écran d\'accueil';
      case InstallPlatform.androidBrowser:
        return 'Installer DTNH Assistant';
      case InstallPlatform.desktopBrowser:
        return 'Utiliser sur le téléphone';
      case InstallPlatform.nativeApp:
        return 'Application installée';
    }
  }

  String get _subtitle {
    switch (_platform) {
      case InstallPlatform.installed:
        return 'Vous utilisez déjà la version installée : elle fonctionne même '
            'sans réseau.';
      case InstallPlatform.iosBrowser:
        return 'Sur iPhone/iPad, l\'installation se fait en deux gestes depuis '
            'Safari.';
      case InstallPlatform.androidBrowser:
        return 'Installez l\'application pour un lancement instantané, même '
            'hors-ligne, sans passer par le navigateur.';
      case InstallPlatform.desktopBrowser:
        return 'Ouvrez cette page sur votre téléphone pour l\'installer, ou '
            'téléchargez directement l\'APK Android ci-dessous.';
      case InstallPlatform.nativeApp:
        return 'Vous utilisez déjà l\'application native.';
    }
  }

  Future<void> _installNow() async {
    setState(() => _installing = true);
    final outcome = await InstallPrompt.prompt();
    if (!mounted) return;
    setState(() => _installing = false);
    switch (outcome) {
      case InstallOutcome.accepted:
        showAppSnack(
          context,
          'Installation lancée : l\'icône DTNH apparaîtra sur votre écran '
          'd\'accueil.',
          icon: Icons.install_mobile_rounded,
        );
      case InstallOutcome.dismissed:
        showAppSnack(
          context,
          'Installation annulée. Vous pouvez réessayer à tout moment.',
          icon: Icons.info_outline_rounded,
        );
      case InstallOutcome.manualInstructionsRequired:
      case InstallOutcome.unavailable:
        showAppSnack(
          context,
          'Utilisez le menu du navigateur > « Installer l\'application ».',
          icon: Icons.info_outline_rounded,
        );
    }
  }

  Future<void> _downloadApk() async {
    await InstallPrompt.openUrl(AppConfig.apkReleaseUrl);
    if (!mounted) return;
    showAppSnack(
      context,
      'Ouverture de la page de téléchargement Android…',
      icon: Icons.download_rounded,
    );
  }
}

class _InstalledBanner extends StatelessWidget {
  const _InstalledBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.green.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: AppColors.green),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Mode application : plein écran, hors-ligne et sans barre '
              'd\'adresse.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualSteps extends StatelessWidget {
  const _ManualSteps({required this.platform});

  final InstallPlatform platform;

  @override
  Widget build(BuildContext context) {
    final steps = platform == InstallPlatform.iosBrowser
        ? const <String>[
            'Appuyez sur le bouton Partager (carré avec une flèche) en bas '
                'de Safari.',
            'Choisissez « Sur l\'écran d\'accueil ».',
            'Validez avec « Ajouter » : l\'icône DTNH apparaît sur le bureau.',
          ]
        : const <String>[
            'Ouvrez le menu du navigateur (⋮).',
            'Choisissez « Installer l\'application » ou « Ajouter à l\'écran '
                'd\'accueil ».',
            'Validez : l\'icône DTNH apparaît sur le bureau.',
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.navy,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
