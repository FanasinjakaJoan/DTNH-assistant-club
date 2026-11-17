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
import '../auth/auth_controller.dart';
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
          const _AccountSection(),
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
                _ClubConfigBanner(settings: settings),
                const SizedBox(height: 10),
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
  /// La connexion Google suffit : l'appareil s'authentifie par le JWT de
  /// session, aucun secret n'est requis. Les champs restent disponibles pour
  /// pointer vers un autre projet Supabase (test, autre club) ou pour un
  /// appareil volontairement non connecté.
  List<Widget> _buildSupabaseSection(
    BuildContext context,
    AppSettings settings,
  ) {
    final usingDefaults = settings.supabaseUrl.trim().isEmpty;
    final auth = ref.watch(authControllerProvider);
    return [
      Row(
        children: [
          Icon(
            auth.isSignedIn ? Icons.verified_user_rounded : Icons.cloud_done_rounded,
            size: 18,
            color: AppColors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              auth.isSignedIn
                  ? 'Connecté avec Google : les envois sont authentifiés par '
                      'votre compte, aucun secret à saisir.'
                  : usingDefaults
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
          hintText: 'Inutile si vous êtes connecté avec Google',
          prefixIcon: Icon(Icons.key_rounded),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Les données partent vers PostgreSQL (tables dtnh_*). Votre session '
        'Google signe chaque envoi (author_id = votre compte) ; le secret '
        'partagé ne sert qu\'aux appareils non connectés.',
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

  /// Champs de la cible Google Sheets (webhook Apps Script).
  ///
  /// Rien n'est à saisir normalement : après la connexion Google, l'URL et le
  /// secret sont distribués par l'Edge Function `dtnh-sync` (action `config`)
  /// et affichés ci-dessous en lecture seule. Les champs restent modifiables
  /// pour un appareil géré à la main.
  List<Widget> _buildAppsScriptSection(
    BuildContext context,
    AppSettings settings,
  ) {
    final clubUrl = settings.clubWebhookUrl?.trim() ?? '';
    final hasClubConfig = clubUrl.isNotEmpty;
    return [
      if (hasClubConfig) ...[
        Row(
          children: [
            const Icon(Icons.verified_rounded, size: 18, color: AppColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Configuration du club reçue automatiquement'
                '${settings.clubConfigSyncedAt == null ? '' : ' (${settings.clubConfigSyncedAt!.dmy})'}'
                ' : rien à saisir.',
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
      TextField(
        controller: _urlController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'URL du déploiement (/exec)',
          hintText: clubUrl.isNotEmpty
              ? clubUrl
              : 'Reçue automatiquement après connexion Google',
          prefixIcon: const Icon(Icons.link_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _secretController,
        obscureText: true,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'Secret partagé',
          hintText: hasClubConfig
              ? 'Reçu du club (inutile si vous êtes connecté avec Google)'
              : 'Identique à SHARED_SECRET dans Apps Script',
          prefixIcon: const Icon(Icons.key_rounded),
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
        'Rien à configurer en temps normal : après « Se connecter avec '
        'Google », l\'URL et le secret du club sont récupérés automatiquement. '
        'Les champs ci-dessus ne servent qu\'à un appareil administré à la '
        'main (autre projet, test).',
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
    // configuration non sauvegardée donnerait un faux négatif. Un champ vide
    // n'écrase rien : la configuration du club (ou le build) prend le relais —
    // c'est le cas normal quand l'utilisateur s'est simplement connecté.
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
      final message =
          await ref.read(syncControllerProvider.notifier).testConnection();
      if (!mounted) return;
      // Une session Google authentifie l'appel : on le dit explicitement, sinon
      // le staff croit encore qu'un secret est nécessaire.
      final hasSession =
          await ref.read(appsScriptClientProvider).hasSession();
      if (!mounted) return;
      showAppSnack(
        context,
        hasSession
            ? 'Connexion établie (authentifié par la session Google) : $message'
            : 'Connexion établie : $message',
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

/// Bandeau d'état de la configuration du club.
///
/// Objectif : que le staff **comprenne en un coup d'œil** qu'il n'a rien à
/// saisir. Trois situations :
/// - connecté avec Google et configuration reçue → tout est prêt ;
/// - connecté mais configuration pas encore reçue (hors-ligne) → repli local ;
/// - non connecté → la configuration du club reste disponible si elle a déjà
///   été reçue, sinon on invite à se connecter.
class _ClubConfigBanner extends ConsumerWidget {
  const _ClubConfigBanner({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final status = ref.watch(clubConfigStatusProvider);
    final isLoading = status.isLoading;
    final outcome = status.outcome;

    final IconData icon;
    final Color color;
    final Color background;
    final String message;
    String? actionLabel;
    VoidCallback? onAction;

    if (auth.isSignedIn && settings.isClubConfigFetched) {
      icon = Icons.verified_rounded;
      color = AppColors.green;
      background = AppColors.greenSoft;
      final date = settings.clubConfigSyncedAt;
      message = 'Configuration du club reçue automatiquement'
          '${date == null ? '' : ' le ${date.dmy}'} : '
          'rien à saisir, la synchronisation part toute seule.';
      actionLabel = isLoading ? null : 'Actualiser';
      onAction = () => _refresh(context, ref);
    } else if (auth.isSignedIn) {
      icon = Icons.sync_rounded;
      color = outcome == ClubConfigOutcome.unauthorized
          ? AppColors.red
          : AppColors.amber;
      background =
          outcome == ClubConfigOutcome.unauthorized ? AppColors.redSoft : AppColors.amberSoft;
      message = outcome == ClubConfigOutcome.unauthorized
          ? 'Session Google refusée par le serveur : reconnectez-vous pour '
              'recevoir la configuration du club.'
          : outcome == ClubConfigOutcome.offline
              ? 'Hors-ligne : la configuration du club sera récupérée au '
                  'prochain passage. Les valeurs locales sont utilisées en '
                  'attendant.'
              : 'Connexion Google active : récupération de la configuration '
                  'du club…';
      actionLabel = isLoading ? null : 'Réessayer';
      onAction = () => _refresh(context, ref);
    } else {
      icon = Icons.login_rounded;
      color = AppColors.blue;
      background = AppColors.blueSoft;
      message = settings.hasClubConfig
          ? 'Mode local : la dernière configuration reçue du club est '
              'utilisée. Connectez-vous pour la renouveler automatiquement.'
          : 'Connectez-vous avec Google pour recevoir automatiquement la '
              'configuration du club (aucune saisie nécessaire).';
      actionLabel = 'Se connecter';
      onAction = () => ref
          .read(authControllerProvider.notifier)
          .signInWithGoogle();
    }

    return InfoBanner(
      message: message,
      icon: icon,
      color: color,
      background: background,
      actionLabel: actionLabel,
      onAction: isLoading ? null : onAction,
    );
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final outcome =
        await ref.read(syncControllerProvider.notifier).refreshClubConfig();
    if (!context.mounted) return;
    final message = switch (outcome) {
      ClubConfigOutcome.applied => 'Configuration du club actualisée.',
      ClubConfigOutcome.appliedWithoutSheets =>
        'Configuration du club à jour (cible Supabase).',
      ClubConfigOutcome.notSignedIn => 'Connectez-vous avec Google d\'abord.',
      ClubConfigOutcome.offline =>
        'Serveur injoignable : les valeurs locales restent utilisées.',
      ClubConfigOutcome.unauthorized =>
        'Session expirée : reconnectez-vous avec Google.',
      ClubConfigOutcome.failed =>
        ref.read(clubConfigStatusProvider).error ??
            'Configuration indisponible.',
    };
    showAppSnack(
      context,
      message,
      icon: outcome == ClubConfigOutcome.applied ||
              outcome == ClubConfigOutcome.appliedWithoutSheets
          ? Icons.check_circle_rounded
          : Icons.info_outline_rounded,
      color: outcome == ClubConfigOutcome.applied ||
              outcome == ClubConfigOutcome.appliedWithoutSheets
          ? AppColors.green
          : AppColors.navy,
      duration: const Duration(seconds: 5),
    );
  }
}

/// Ligne de sélection de la cible de synchronisation.
///
/// Réimplémentée à la main plutôt que `RadioListTile` : l'API `groupValue`
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

/// Section « Compte » : état de la connexion Google, connexion / déconnexion.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsProvider);

    if (!auth.isConfigured) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Compte du club',
          subtitle: 'Connexion Google : traçabilité des saisies',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor:
                        auth.isSignedIn ? AppColors.green : AppColors.navyLight,
                    child: auth.isSignedIn
                        ? Text(
                            auth.user!.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          )
                        : const Icon(
                            Icons.person_outline_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.isSignedIn
                              ? auth.user!.displayName
                              : 'Mode local (non connecté)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          auth.isSignedIn
                              ? (auth.user!.email.isEmpty
                                  ? 'Compte Google connecté'
                                  : auth.user!.email)
                              : 'Vos saisies restent sur ce téléphone. '
                                  'Connectez-vous pour les rattacher à votre '
                                  'compte.',
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
              const SizedBox(height: 12),
              if (auth.isSignedIn)
                OutlinedButton.icon(
                  onPressed: auth.isLoading
                      ? null
                      : () => ref
                          .read(authControllerProvider.notifier)
                          .signOut(),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Se déconnecter'),
                )
              else
                FilledButton.icon(
                  onPressed: auth.isLoading
                      ? null
                      : () => ref
                          .read(authControllerProvider.notifier)
                          .signInWithGoogle(),
                  icon: auth.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login_rounded, size: 18),
                  label: Text(
                    auth.isLoading
                        ? 'Connexion…'
                        : 'Se connecter avec Google',
                  ),
                ),
              if (settings.authorName != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Auteur enregistré : ${settings.authorName}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
