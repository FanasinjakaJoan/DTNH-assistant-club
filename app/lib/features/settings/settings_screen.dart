import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_x.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/install_app_tile.dart';
import '../../di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/enums/sync_target.dart';
import '../sync/sync_controller.dart';
import 'demo_seed.dart';
import 'roster_screen.dart';
import 'settings_controller.dart';

/// Réglages : identité, webhook Apps Script, automatisation, données.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  final TextEditingController _sheetController = TextEditingController();
  final TextEditingController _supabaseUrlController = TextEditingController();
  final TextEditingController _supabaseSecretController =
      TextEditingController();
  bool _initialized = false;
  bool _isSaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final settings = ref.read(settingsProvider);
    _urlController.text = settings.webhookUrl;
    _secretController.text = settings.webhookSecret;
    _sheetController.text = settings.sheetId ?? '';
    _supabaseUrlController.text = settings.supabaseUrl;
    _supabaseSecretController.text = settings.supabaseSecret;
    _initialized = true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _secretController.dispose();
    _sheetController.dispose();
    _supabaseUrlController.dispose();
    _supabaseSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final counters = ref.watch(syncCountersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          const SectionHeader(
            title: 'Identité du pointage',
            padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
          ),
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.navy,
                      child: Text(
                        _initials(settings.authorName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.authorName ?? 'Aucun auteur',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'Nom enregistré dans la colonne « Auteur »',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _changeAuthor(context, settings.authorName),
                      child: const Text('Changer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader(
            title: 'Synchronisation',
            subtitle: 'Destination des présences, finances et effectif',
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final target in SyncTarget.values)
                  _SyncTargetTile(
                    target: target,
                    selected: settings.syncTarget == target,
                    onTap: () => ref
                        .read(settingsProvider.notifier)
                        .setSyncTarget(target),
                  ),
                const Divider(height: 20),
                if (settings.syncTarget == SyncTarget.supabase)
                  ..._buildSupabaseSection(context, settings)
                else
                  ..._buildAppsScriptSection(context, settings),
              ],
            ),
          ),
          const InstallAppTile(),
          const SectionHeader(title: 'Automatisation'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: settings.autoSyncEnabled,
                  onChanged: (value) =>
                      ref.read(settingsProvider.notifier).setAutoSync(value),
                  activeColor: AppColors.orange,
                  title: const Text(
                    'Synchronisation automatique',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Dès le retour du réseau et en arrière-plan (15 min)',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.schedule_rounded, size: 20),
                  title: const Text(
                    'Dernier envoi réussi',
                    style: TextStyle(fontSize: 13),
                  ),
                  trailing: Text(
                    settings.lastSyncAt == null
                        ? 'Jamais'
                        : '${settings.lastSyncAt!.dmy} · ${settings.lastSyncAt!.hm}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.pending_actions_rounded, size: 20),
                  title: const Text(
                    'Opérations en attente',
                    style: TextStyle(fontSize: 13),
                  ),
                  trailing: Text(
                    '${counters.outstanding}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: counters.error > 0
                          ? AppColors.red
                          : counters.outstanding > 0
                              ? AppColors.amber
                              : AppColors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Effectif'),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.groups_rounded),
                  title: const Text(
                    'Gérer l\'effectif',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'Ajouter, archiver des joueurs (hors-ligne)',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RosterScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: const Text(
                    'Charger l\'effectif de démonstration',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    '40 joueurs répartis dans les 4 catégories',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () async {
                    final created = await DemoSeed(ref.read(playerRepositoryProvider))
        .seedRosterIfEmpty();
                    if (!context.mounted) return;
                    showAppSnack(
                      context,
                      created > 0
                          ? '$created joueurs ajoutés.'
                          : 'L\'effectif est déjà rempli.',
                      icon: Icons.groups_rounded,
                    );
                  },
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Données locales'),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cleaning_services_rounded),
                  title: const Text(
                    'Nettoyer l\'historique des envois',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    '${counters.synced} élément(s) déjà synchronisé(s)',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: counters.synced == 0
                      ? null
                      : () async {
                          await ref
                              .read(syncControllerProvider.notifier)
                              .clearHistory();
                          if (!context.mounted) return;
                          showAppSnack(
                            context,
                            'Historique nettoyé.',
                            icon: Icons.check_circle_rounded,
                          );
                        },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_forever_rounded,
                    color: AppColors.red,
                  ),
                  title: const Text(
                    'Réinitialiser toutes les données',
                    style: TextStyle(fontSize: 13.5, color: AppColors.red),
                  ),
                  subtitle: const Text(
                    'Efface présences, finances et file d\'attente locales',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => _confirmWipe(context),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'À propos'),
          AppCard(
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'DTNH Assistant Club · v1.0.0',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Application offline-first du club Dream Team New Hope. '
                  'Présences et finances fonctionnent sans réseau ; la '
                  'synchronisation Google Sheets se fait par webhook Apps Script '
                  '(aucune clé OAuth stockée sur le téléphone).',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Champs de la cible Supabase.
  ///
  /// Les valeurs par défaut sont compilées dans l'application : le staff n'a
  /// donc rien à saisir. Les champs restent modifiables pour pointer vers un
  /// autre projet Supabase (utile en test ou pour un autre club).
  List<Widget> _buildSupabaseSection(
    BuildContext context,
    AppSettings settings,
  ) {
    final usingDefaults = settings.supabaseUrl.trim().isEmpty;
    return [
      Row(
        children: [
          const Icon(Icons.cloud_done_rounded, size: 18, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              usingDefaults
                  ? 'Configuration du club active : rien à saisir.'
                  : 'Configuration personnalisée enregistrée sur cet appareil.',
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _supabaseUrlController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'URL de la fonction (facultatif)',
          hintText: AppConfig.supabaseSyncUrl,
          prefixIcon: Icon(Icons.cloud_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _supabaseSecretController,
        obscureText: true,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Secret partagé (facultatif)',
          hintText: 'Vide = secret compilé dans l\'application',
          prefixIcon: Icon(Icons.key_rounded),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Les données partent vers PostgreSQL (tables dtnh_*). L\'application '
        'n\'embarque aucune clé Supabase : seul le secret de la fonction '
        'dtnh-sync est utilisé.',
        style: TextStyle(
          fontSize: 11,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 14),
      LoadingButton(
        label: _isSaving ? 'Enregistrement' : 'Enregistrer la configuration',
        icon: Icons.save_rounded,
        loading: _isSaving,
        onPressed: () => _saveSupabase(context),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _testConnection(context),
              icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
              label: const Text('Tester la connexion'),
            ),
          ),
        ],
      ),
    ];
  }

  /// Champs de la cible Google Sheets (webhook Apps Script historique).
  List<Widget> _buildAppsScriptSection(
    BuildContext context,
    AppSettings settings,
  ) {
    return [
      TextField(
        controller: _urlController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'URL du déploiement (/exec)',
          hintText: 'https://script.google.com/macros/s/AKfy…/exec',
          prefixIcon: Icon(Icons.link_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _secretController,
        obscureText: true,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Secret partagé',
          hintText: 'Identique à SHARED_SECRET dans Apps Script',
          prefixIcon: Icon(Icons.key_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _sheetController,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'ID du Google Sheet (facultatif)',
          hintText: '1AbC… (pour vos archives)',
          prefixIcon: Icon(Icons.table_chart_rounded),
        ),
      ),
      const SizedBox(height: 14),
      LoadingButton(
        label: _isSaving ? 'Enregistrement' : 'Enregistrer la configuration',
        icon: Icons.save_rounded,
        loading: _isSaving,
        onPressed: () => _saveWebhook(context),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _testConnection(context),
              icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
              label: const Text('Tester la connexion'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        'Comment obtenir cette URL : extensions Apps Script, collez le '
        'code fourni (dossier apps-script/), puis Déployer > Nouveau '
        'déploiement > Application web > Exécuter en tant que moi > '
        'Accès : Tout le monde. Copiez l\'URL /exec.',
        style: TextStyle(
          fontSize: 11,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ),
    ];
  }

  Future<void> _saveSupabase(BuildContext context) async {
    setState(() => _isSaving = true);
    await ref.read(settingsProvider.notifier).saveSupabase(
          url: _supabaseUrlController.text,
          secret: _supabaseSecretController.text,
        );
    if (!mounted) return;
    setState(() => _isSaving = false);
    showAppSnack(
      context,
      'Synchronisation Supabase enregistrée sur cet appareil.',
      icon: Icons.check_circle_rounded,
    );
  }

  Future<void> _saveWebhook(BuildContext context) async {
    setState(() => _isSaving = true);
    await ref.read(settingsProvider.notifier).saveWebhook(
          url: _urlController.text,
          secret: _secretController.text,
          sheetId: _sheetController.text,
        );
    if (!mounted) return;
    setState(() => _isSaving = false);
    showAppSnack(
      context,
      'Configuration enregistrée sur cet appareil.',
      icon: Icons.check_circle_rounded,
    );
  }

  Future<void> _testConnection(BuildContext context) async {
    // On enregistre d'abord les champs de la cible active : tester une
    // configuration non sauvegardée donnerait un faux négatif.
    final current = ref.read(settingsProvider);
    if (current.syncTarget == SyncTarget.supabase) {
      await ref.read(settingsProvider.notifier).saveSupabase(
            url: _supabaseUrlController.text,
            secret: _supabaseSecretController.text,
          );
    } else {
      await ref.read(settingsProvider.notifier).saveWebhook(
            url: _urlController.text,
            secret: _secretController.text,
            sheetId: _sheetController.text,
          );
    }
    try {
      final message = await ref.read(syncControllerProvider.notifier).testConnection();
      if (!mounted) return;
      showAppSnack(
        context,
        'Connexion établie : $message',
        icon: Icons.wifi_tethering_rounded,
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnack(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        color: AppColors.red,
        icon: Icons.error_outline_rounded,
        duration: const Duration(seconds: 6),
      );
    }
  }

  Future<void> _changeAuthor(BuildContext context, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Votre nom'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Ex : Coach Tojo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await ref.read(settingsProvider.notifier).setAuthor(name);
    if (!mounted) return;
    showAppSnack(context, 'Auteur mis à jour : $name', icon: Icons.badge_rounded);
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Tout effacer ?'),
        content: const Text(
          'Les présences et transactions non synchronisées seront perdues. '
          'Cette action est irréversible.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(localDatabaseProvider).clearAll();
    if (!mounted) return;
    ref.read(settingsProvider.notifier).reload();
    showAppSnack(
      context,
      'Données locales effacées.',
      icon: Icons.delete_forever_rounded,
      color: AppColors.red,
    );
  }

  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Ligne de sélection de la cible de synchronisation.
///
/// Réimplémentée à la main plutôt qu'avec `RadioListTile` : l'API `groupValue`
/// / `onChanged` de Flutter est dépréciée depuis 3.32 et deviendra caduque.
class _SyncTargetTile extends StatelessWidget {
  const _SyncTargetTile({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final SyncTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppColors.orange : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 20,
              color: accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    target.description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
