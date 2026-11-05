import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../core/utils/date_x.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/category_selector.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/entities/attendance_stats.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/enums/sync_enums.dart';
import '../../domain/enums/team_category.dart';
import 'history_state.dart';

/// Historique des présences : par séance ou par joueur.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(historyCategoryProvider);
    final view = ref.watch(historyViewProvider);
    final stats = ref.watch(categoryStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
            tooltip: 'Basculer la vue',
            onPressed: () {
              final next = view == HistoryView.sessions
                  ? HistoryView.players
                  : HistoryView.sessions;
              ref.read(historyViewProvider.notifier).state = next;
            },
            icon: Icon(
              view == HistoryView.sessions
                  ? Icons.people_alt_outlined
                  : Icons.calendar_view_week_rounded,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          CategorySelector(
            selected: category,
            onChanged: (value) =>
                ref.read(historyCategoryProvider.notifier).state = value,
          ),
          const SizedBox(height: 12),
          stats.when(
            data: (value) => _CategorySummaryCard(
              category: category,
              stats: value,
            ),
            loading: () => const AppCard(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (error, _) => InfoBanner(
              message: 'Impossible de calculer les statistiques : $error',
              icon: Icons.error_outline_rounded,
              color: AppColors.red,
              background: AppColors.redSoft,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ViewToggle(
                  label: 'Séances',
                  icon: Icons.event_note_rounded,
                  selected: view == HistoryView.sessions,
                  onTap: () => ref.read(historyViewProvider.notifier).state =
                      HistoryView.sessions,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ViewToggle(
                  label: 'Joueurs',
                  icon: Icons.leaderboard_rounded,
                  selected: view == HistoryView.players,
                  onTap: () => ref.read(historyViewProvider.notifier).state =
                      HistoryView.players,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (view == HistoryView.sessions)
            const _SessionsList()
          else
            const _PlayersList(),
        ],
      ),
    );
  }
}

class _CategorySummaryCard extends StatelessWidget {
  const _CategorySummaryCard({
    required this.category,
    required this.stats,
  });

  final TeamCategory category;
  final AttendanceStats stats;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${stats.ratePercent} %',
                style: const TextStyle(
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'de présence effective\n(présents + retards)',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorForCategoryIndex(category.index)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${stats.total} pointages',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colorForCategoryIndex(category.index),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: stats.rate,
              minHeight: 8,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.green),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final status in AttendanceStatus.values)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${stats.countFor(status)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: visualForAttendance(status).color,
                        ),
                      ),
                      Text(
                        visualForAttendance(status).label,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.navy : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionsList extends ConsumerWidget {
  const _SessionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionSummariesProvider);
    return sessions.when(
      data: (items) {
        if (items.isEmpty) {
          return AppCard(
            child: EmptyState(
              icon: Icons.event_busy_rounded,
              title: 'Aucune séance pointée',
              message:
                  'L\'historique s\'enrichit à chaque pointage enregistré, même '
                  'hors-ligne.',
            ),
          );
        }
        return Column(
          children: [
            for (final session in items) _SessionTile(session: session),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => InfoBanner(
        message: 'Erreur de lecture locale : $error',
        icon: Icons.error_outline_rounded,
        color: AppColors.red,
        background: AppColors.redSoft,
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final AttendanceSessionSummary session;

  @override
  Widget build(BuildContext context) {
    final stats = session.stats;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      onTap: () => _showDetails(context),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorForCategoryIndex(session.category.index)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${session.date.day}',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: colorForCategoryIndex(session.category.index),
                      ),
                    ),
                    Text(
                      session.date.shortFrenchMonth.split(' ').first,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: colorForCategoryIndex(session.category.index),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.date.longFrenchDate,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.present} présents · ${stats.late} retards · '
                      '${stats.absent} absents · ${stats.excused} excusés',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill.sync(
                session.isFullySynced ? SyncState.synced : SyncState.pending,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: stats.rate,
              minHeight: 6,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.green),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${session.category.label} · ${session.date.dmy}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              DetailRow(
                label: 'Joueurs pointés',
                value: '${session.stats.total}',
                icon: Icons.groups_rounded,
              ),
              DetailRow(
                label: 'Présents',
                value: '${session.stats.present}',
                icon: Icons.check_rounded,
                valueColor: AppColors.green,
              ),
              DetailRow(
                label: 'En retard',
                value: '${session.stats.late}',
                icon: Icons.schedule_rounded,
                valueColor: AppColors.amber,
              ),
              DetailRow(
                label: 'Absents',
                value: '${session.stats.absent}',
                icon: Icons.close_rounded,
                valueColor: AppColors.red,
              ),
              DetailRow(
                label: 'Excusés',
                value: '${session.stats.excused}',
                icon: Icons.verified_rounded,
                valueColor: AppColors.blue,
              ),
              DetailRow(
                label: 'Pointé par',
                value: session.authors.join(', '),
                icon: Icons.badge_outlined,
              ),
              DetailRow(
                label: 'Dernier pointage',
                value:
                    '${session.lastRecordedAt.dmy} à ${session.lastRecordedAt.hm}',
                icon: Icons.schedule_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayersList extends ConsumerWidget {
  const _PlayersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(playerStatsProvider);
    return stats.when(
      data: (items) {
        if (items.isEmpty) {
          return AppCard(
            child: EmptyState(
              icon: Icons.insights_rounded,
              title: 'Pas encore de statistiques',
              message:
                  'Chaque pointage alimente le taux de présence individuel des '
                  'joueurs de la catégorie.',
            ),
          );
        }
        return Column(
          children: [
            for (var index = 0; index < items.length; index++)
              _PlayerStatTile(rank: index + 1, data: items[index]),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => InfoBanner(
        message: 'Erreur de lecture locale : $error',
        icon: Icons.error_outline_rounded,
        color: AppColors.red,
        background: AppColors.redSoft,
      ),
    );
  }
}

class _PlayerStatTile extends StatelessWidget {
  const _PlayerStatTile({required this.rank, required this.data});

  final int rank;
  final PlayerAttendanceStats data;

  @override
  Widget build(BuildContext context) {
    final stats = data.stats;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              data.jerseyNumber?.toString() ??
                  data.playerName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.playerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: stats.rate,
                    minHeight: 5,
                    backgroundColor: AppColors.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      stats.rate >= 0.75
                          ? AppColors.green
                          : stats.rate >= 0.5
                              ? AppColors.amber
                              : AppColors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stats.ratePercent} %',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${stats.present}P · ${stats.late}R · ${stats.absent}A',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
