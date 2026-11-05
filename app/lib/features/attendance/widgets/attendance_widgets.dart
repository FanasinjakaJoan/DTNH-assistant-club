import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/status_styles.dart';
import '../../../core/utils/date_x.dart';
import '../../../domain/entities/attendance_stats.dart';
import '../../../domain/entities/player.dart';
import '../../../domain/enums/attendance_status.dart';

/// Bandeau de dates (7 derniers jours + accès calendrier).
class DateStrip extends StatelessWidget {
  const DateStrip({
    super.key,
    required this.selected,
    required this.onChanged,
    this.onPickDate,
    this.days = 7,
  });

  final DateTime selected;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onPickDate;
  final int days;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().dateOnly;
    final dates = List<DateTime>.generate(
      days,
      (index) => today.subtract(Duration(days: days - 1 - index)),
    );
    if (!dates.any((date) => date.isSameDay(selected))) {
      dates.add(selected);
      dates.sort((a, b) => a.compareTo(b));
    }

    return SizedBox(
      height: 74,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              reverse: true,
              itemCount: dates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final date = dates[dates.length - 1 - index];
                final isSelected = date.isSameDay(selected);
                final isToday = date.isSameDay(today);
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onChanged(date),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 54,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.navy : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.navy
                              : isToday
                                  ? AppColors.orange
                                  : AppColors.border,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _weekdayShort(date),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white70
                                  : AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color:
                                  isSelected ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _monthShort(date),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: isSelected
                                  ? Colors.white70
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (onPickDate != null) ...[
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPickDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 52,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.orangeSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: AppColors.orangeDark,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _weekdayShort(DateTime date) {
    const names = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return names[date.weekday - 1];
  }

  static String _monthShort(DateTime date) {
    const names = [
      'janv',
      'févr',
      'mars',
      'avr',
      'mai',
      'juin',
      'juil',
      'août',
      'sept',
      'oct',
      'nov',
      'déc',
    ];
    return names[date.month - 1];
  }
}

/// Carte de progression du pointage (présents / total + répartition).
class AttendanceSummaryCard extends StatelessWidget {
  const AttendanceSummaryCard({
    super.key,
    required this.stats,
    required this.totalPlayers,
    required this.onMarkAllPresent,
    required this.onReset,
  });

  final AttendanceStats stats;
  final int totalPlayers;
  final VoidCallback onMarkAllPresent;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final progress = stats.total == 0 ? 0.0 : stats.total / totalPlayers;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stats.total}',
                style: const TextStyle(
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 4),
                child: Text(
                  '/ $totalPlayers pointés',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                totalPlayers == 0
                    ? ''
                    : '${((stats.total / totalPlayers) * 100).round()} %',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.orangeDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 8,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final status in AttendanceStatus.values)
                _CountChip(status: status, count: stats.countFor(status)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: totalPlayers == 0 ? null : onMarkAllPresent,
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Tout présent'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: stats.total == 0 ? null : onReset,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Réinitialiser'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.status, required this.count});

  final AttendanceStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final visual = visualForAttendance(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: visual.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 13, color: visual.color),
          const SizedBox(width: 4),
          Text(
            '${visual.label} $count',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: visual.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne joueur avec les 4 boutons de statut « bord de terrain ».
class PlayerAttendanceTile extends StatelessWidget {
  const PlayerAttendanceTile({
    super.key,
    required this.player,
    required this.status,
    required this.onStatusSelected,
  });

  final Player player;
  final AttendanceStatus? status;
  final ValueChanged<AttendanceStatus> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == null
              ? AppColors.border
              : visualForAttendance(status!).color.withOpacity(0.45),
          width: status == null ? 1 : 1.4,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: status == null
                      ? AppColors.surface
                      : visualForAttendance(status!).background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  player.jerseyNumber?.toString() ?? player.initials,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: status == null
                        ? AppColors.textSecondary
                        : visualForAttendance(status!).color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  player.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (status != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: visualForAttendance(status!).background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    visualForAttendance(status!).label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: visualForAttendance(status!).color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final value in AttendanceStatus.values) ...[
                Expanded(
                  child: _StatusButton(
                    status: value,
                    selected: status == value,
                    onTap: () => onStatusSelected(value),
                  ),
                ),
                if (value != AttendanceStatus.values.last)
                  const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final AttendanceStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = visualForAttendance(status);
    return Semantics(
      button: true,
      selected: selected,
      label: '${status.label} pour ce joueur',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            height: 44,
            decoration: BoxDecoration(
              color: selected ? visual.color : visual.background,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected ? visual.color : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  visual.icon,
                  size: 15,
                  color: selected ? Colors.white : visual.color,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    visual.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : visual.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
