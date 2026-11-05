import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_x.dart';
import '../../di/providers.dart';
import '../../domain/entities/attendance_stats.dart';
import '../../domain/entities/player.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/enums/team_category.dart';
import '../settings/settings_controller.dart';

/// État du pointage en cours (une catégorie, une date, N joueurs).
class AttendanceDraft {
  const AttendanceDraft({
    required this.category,
    required this.date,
    this.statuses = const <String, AttendanceStatus>{},
    this.isLoading = false,
    this.isSaving = false,
    this.isDirty = false,
    this.savedAt,
    this.savedCount = 0,
    this.error,
  });

  final TeamCategory category;
  final DateTime date;

  /// `playerId -> statut`. Les joueurs non pointés sont absents de la map.
  final Map<String, AttendanceStatus> statuses;

  final bool isLoading;
  final bool isSaving;
  final bool isDirty;

  /// Dernier enregistrement de cette séance (null si jamais pointée).
  final DateTime? savedAt;
  final int savedCount;
  final String? error;

  int get pointedCount => statuses.length;

  AttendanceStats get stats {
    var present = 0;
    var absent = 0;
    var late = 0;
    var excused = 0;
    for (final status in statuses.values) {
      if (status == AttendanceStatus.present) {
        present++;
      } else if (status == AttendanceStatus.absent) {
        absent++;
      } else if (status == AttendanceStatus.late) {
        late++;
      } else {
        excused++;
      }
    }
    return AttendanceStats(
      present: present,
      absent: absent,
      late: late,
      excused: excused,
    );
  }

  AttendanceDraft copyWith({
    TeamCategory? category,
    DateTime? date,
    Map<String, AttendanceStatus>? statuses,
    bool? isLoading,
    bool? isSaving,
    bool? isDirty,
    DateTime? savedAt,
    bool clearSavedAt = false,
    int? savedCount,
    String? error,
    bool clearError = false,
  }) {
    return AttendanceDraft(
      category: category ?? this.category,
      date: date ?? this.date,
      statuses: statuses ?? this.statuses,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isDirty: isDirty ?? this.isDirty,
      savedAt: clearSavedAt ? null : (savedAt ?? this.savedAt),
      savedCount: savedCount ?? this.savedCount,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final attendanceDraftProvider =
    NotifierProvider<AttendanceDraftController, AttendanceDraft>(
  AttendanceDraftController.new,
);

/// Contrôleur du pointage.
///
/// Toute écriture est **locale d'abord** : `save()` persiste dans Hive et met
/// en file pour Google Sheets. Le coach n'attend jamais le réseau.
class AttendanceDraftController extends Notifier<AttendanceDraft> {
  bool _disposed = false;
  int _loadToken = 0;

  @override
  AttendanceDraft build() {
    ref.onDispose(() => _disposed = true);
    final now = DateTime.now();
    return AttendanceDraft(
      category: TeamCategory.u12,
      date: DateTime(now.year, now.month, now.day),
      isLoading: true,
    );
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _load();
  }

  Future<void> selectCategory(TeamCategory category) async {
    if (category == state.category) return;
    state = state.copyWith(
      category: category,
      isLoading: true,
      isDirty: false,
      clearError: true,
    );
    await _load();
  }

  Future<void> selectDate(DateTime date) async {
    final target = date.dateOnly;
    if (target == state.date) return;
    state = state.copyWith(
      date: target,
      isLoading: true,
      isDirty: false,
      clearError: true,
    );
    await _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final category = state.category;
    final date = state.date;
    try {
      final entries = await ref
          .read(attendanceRepositoryProvider)
          .entriesForSession(category: category, date: date);
      if (_disposed || token != _loadToken) return;
      state = state.copyWith(
        statuses: <String, AttendanceStatus>{
          for (final entry in entries) entry.playerId: entry.status,
        },
        isLoading: false,
        isDirty: false,
        savedCount: entries.length,
        savedAt: entries.isEmpty
            ? null
            : entries
                .map((e) => e.recordedAt)
                .reduce((a, b) => a.isAfter(b) ? a : b),
        clearSavedAt: entries.isEmpty,
        clearError: true,
      );
    } catch (error) {
      if (_disposed || token != _loadToken) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Impossible de charger le pointage local : $error',
      );
    }
  }

  void setStatus(String playerId, AttendanceStatus status) {
    final next = Map<String, AttendanceStatus>.from(state.statuses);
    if (next[playerId] == status) {
      next.remove(playerId);
    } else {
      next[playerId] = status;
    }
    state = state.copyWith(statuses: next, isDirty: true, clearError: true);
  }

  void markAll(List<Player> players, AttendanceStatus status) {
    state = state.copyWith(
      statuses: <String, AttendanceStatus>{
        for (final player in players) player.id: status,
      },
      isDirty: true,
      clearError: true,
    );
  }

  void resetDraft() {
    state = state.copyWith(
      statuses: const <String, AttendanceStatus>{},
      isDirty: true,
      clearError: true,
    );
  }

  /// Enregistre la séance ; retourne `false` si la validation échoue.
  Future<bool> save(List<Player> players) async {
    if (state.statuses.isEmpty) {
      state = state.copyWith(
        error: 'Pointez au moins un joueur avant d\'enregistrer.',
      );
      return false;
    }

    final settings = ref.read(settingsProvider);
    final authorName = settings.authorName;
    final authorId = settings.authorId;
    if (authorName == null ||
        authorId == null ||
        authorName.trim().isEmpty) {
      state = state.copyWith(
        error: 'Aucun auteur défini : choisissez votre nom dans les réglages.',
      );
      return false;
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await ref.read(attendanceRepositoryProvider).saveSession(
            category: state.category,
            date: state.date,
            players: players,
            statuses: state.statuses,
            authorId: authorId,
            authorName: authorName,
          );
      if (_disposed) return true;
      state = state.copyWith(
        isSaving: false,
        isDirty: false,
        savedAt: DateTime.now(),
        savedCount: state.statuses.length,
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isSaving: false,
        error: 'Échec de l\'enregistrement local : $error',
      );
      return false;
    }
  }
}
