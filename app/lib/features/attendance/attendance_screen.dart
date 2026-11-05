import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/date_x.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/category_selector.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/date_picker_sheet.dart';
import '../../di/providers.dart';
import '../../domain/entities/player.dart';
import '../../domain/enums/attendance_status.dart';
import '../settings/demo_seed.dart';
import '../settings/roster_screen.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_screen.dart';
import 'attendance_controller.dart';
import 'widgets/attendance_widgets.dart';

/// Écran principal : pointage rapide par catégorie.
///
/// Optimisations terrain :
/// - 4 boutons de statut par joueur, 44 dp de haut, une seule main ;
/// - aucune attente réseau (écriture Hive synchrone perçue) ;
/// - « Tout présent » pour les séances où l'effectif est complet ;
/// - la date par défaut est aujourd'hui, les 7 derniers jours à portée de pouce.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(attendanceDraftProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(attendanceDraftProvider);
    final players = ref.watch(playersByCategoryProvider(draft.category));
    final counters = ref.watch(syncCountersProvider);
    final syncState = ref.watch(syncControllerProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pointage'),
            Text(
              '${draft.category.label} · ${draft.date.longFrenchDate}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          SyncStatusChip(
            pendingCount: counters.pending,
            errorCount: counters.error,
            isOnline: syncState.isOnline,
            isSyncing: syncState.isSyncing,
            onTap: () => _openSyncScreen(context),
          ),
          IconButton(
            tooltip: 'Mon profil (${settings.authorName ?? "non défini"})',
            onPressed: () => _openSettings(context),
            icon: CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.navy,
              child: Text(
                _initials(settings.authorName),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(attendanceDraftProvider.notifier).load(),
        color: AppColors.orange,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            CategorySelector(
              selected: draft.category,
              onChanged: (category) => ref
                  .read(attendanceDraftProvider.notifier)
                  .selectCategory(category),
            ),
            const SizedBox(height: 12),
            DateStrip(
              selected: draft.date,
              onChanged: (date) => ref
                  .read(attendanceDraftProvider.notifier)
                  .selectDate(date),
              onPickDate: () => _pickDate(context, draft.date),
            ),
            const SizedBox(height: 8),
            if (!syncState.isOnline)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: InfoBanner(
                  message:
                      'Hors-ligne : le pointage est enregistré sur le téléphone '
                      'et partira automatiquement au retour du réseau.',
                  icon: Icons.cloud_off_rounded,
                ),
              )
            else if (counters.pending > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InfoBanner(
                  message:
                      '${counters.pending} élément(s) en attente d\'envoi vers '
                      'Google Sheets.',
                  icon: Icons.cloud_upload_outlined,
                  color: AppColors.orangeDark,
                  background: AppColors.orangeSoft,
                  actionLabel: 'Envoyer',
                  onAction: () =>
                      ref.read(syncControllerProvider.notifier).syncNow(),
                ),
              ),
            if (draft.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InfoBanner(
                  message: draft.error!,
                  icon: Icons.error_outline_rounded,
                  color: AppColors.red,
                  background: AppColors.redSoft,
                ),
              ),
            AttendanceSummaryCard(
              stats: draft.stats,
              totalPlayers: players.length,
              onMarkAllPresent: () => ref
                  .read(attendanceDraftProvider.notifier)
                  .markAll(players, AttendanceStatus.present),
              onReset: () =>
                  ref.read(attendanceDraftProvider.notifier).resetDraft(),
            ),
            SectionHeader(
              title: 'Joueurs (${players.length})',
              subtitle: draft.isDirty
                  ? 'Modifications non enregistrées'
                  : draft.savedAt == null
                      ? 'Aucun pointage pour cette séance'
                      : 'Dernier enregistrement à ${draft.savedAt!.hm} · '
                          '${draft.savedCount} joueurs',
              actionLabel: 'Effectif',
              onAction: () => _openRoster(context),
            ),
            if (draft.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (players.isEmpty)
              AppCard(
                child: EmptyState(
                  icon: Icons.groups_2_outlined,
                  title: 'Aucun joueur dans ${draft.category.label}',
                  message:
                      'Ajoutez l\'effectif pour commencer le pointage. Le roster '
                      'reste disponible hors-ligne et se synchronise ensuite.',
                  actionLabel: 'Charger l\'effectif de démo',
                  onAction: () => _seedRoster(context),
                ),
              )
            else
              for (final player in players)
                PlayerAttendanceTile(
                  key: ValueKey('${player.id}-${draft.category.code}'),
                  player: player,
                  status: draft.statuses[player.id],
                  onStatusSelected: (status) => ref
                      .read(attendanceDraftProvider.notifier)
                      .setStatus(player.id, status),
                ),
          ],
        ),
      ),
      bottomNavigationBar: _SaveBar(
        draft: draft,
        players: players,
        onSave: () => _save(players),
      ),
    );
  }

  Future<void> _save(List<Player> players) async {
    final notifier = ref.read(attendanceDraftProvider.notifier);
    final draftBefore = ref.read(attendanceDraftProvider);
    final success = await notifier.save(players);
    if (!mounted) return;

    if (!success) {
      final message = ref.read(attendanceDraftProvider).error ??
          'Échec de l\'enregistrement.';
      showAppSnack(
        context,
        message,
        color: AppColors.red,
        icon: Icons.error_outline_rounded,
      );
      return;
    }

    showAppSnack(
      context,
      'Pointage ${draftBefore.category.label} enregistré · '
      '${draftBefore.pointedCount} joueur(s) · '
      '${draftBefore.statuses.values.where((s) => s.countsAsPresent).length} '
      'présent(s)',
      icon: Icons.check_circle_rounded,
      actionLabel: 'Synchroniser',
      onAction: () => ref.read(syncControllerProvider.notifier).syncNow(),
    );

    final settings = ref.read(settingsProvider);
    final isOnline = ref.read(syncControllerProvider).isOnline;
    if (settings.autoSyncEnabled && isOnline) {
      ref.read(syncControllerProvider.notifier).syncNow();
    }
  }

  Future<void> _pickDate(BuildContext context, DateTime current) async {
    final picked = await showAppDatePicker(context, initialDate: current);
    if (picked == null) return;
    await ref.read(attendanceDraftProvider.notifier).selectDate(picked);
  }

  Future<void> _seedRoster(BuildContext context) async {
    final created = await DemoSeed(ref.read(playerRepositoryProvider))
        .seedRosterIfEmpty();
    if (!mounted) return;
    showAppSnack(
      context,
      created > 0
          ? '$created joueurs ajoutés à l\'effectif.'
          : 'L\'effectif contient déjà des joueurs.',
      icon: Icons.groups_rounded,
    );
  }

  void _openRoster(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RosterScreen()),
    );
  }

  void _openSyncScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SyncScreen()),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
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

/// Barre d'enregistrement persistante (toujours accessible au pouce).
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.draft,
    required this.players,
    required this.onSave,
  });

  final AttendanceDraft draft;
  final List<Player> players;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final canSave = draft.pointedCount > 0 && !draft.isSaving;
    final presentCount = draft.stats.attended;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      draft.pointedCount == 0
                          ? 'Aucun joueur pointé'
                          : '${draft.pointedCount}/${players.length} pointés · '
                              '$presentCount présent(s)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      draft.isDirty
                          ? 'À enregistrer (local)'
                          : draft.savedAt == null
                              ? 'Prêt pour la séance'
                              : 'Enregistré à ${draft.savedAt!.hm}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: draft.isDirty
                            ? AppColors.orangeDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 170,
                child: LoadingButton(
                  label: draft.isSaving ? 'Enregistrement' : 'Enregistrer',
                  icon: Icons.save_rounded,
                  loading: draft.isSaving,
                  onPressed: canSave ? onSave : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
