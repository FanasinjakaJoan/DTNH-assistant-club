import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/entities/attendance_stats.dart';
import '../../domain/enums/team_category.dart';

/// Mode d'affichage de l'historique des présences.
enum HistoryView { sessions, players }

final historyCategoryProvider =
    StateProvider<TeamCategory>((ref) => TeamCategory.u12);

final historyViewProvider =
    StateProvider<HistoryView>((ref) => HistoryView.sessions);

/// Séances récentes de la catégorie sélectionnée.
///
/// `ref.watch(attendanceEntriesProvider)` sert de signal d'invalidation :
/// chaque écriture locale réémet le flux et recalcule les agrégats.
final sessionSummariesProvider =
    FutureProvider.autoDispose<List<AttendanceSessionSummary>>((ref) async {
  final category = ref.watch(historyCategoryProvider);
  ref.watch(attendanceEntriesProvider);
  return ref.watch(attendanceRepositoryProvider).recentSessions(
        category: category,
        limit: 60,
      );
});

/// Statistiques par joueur (taux de présence, retards, absences).
final playerStatsProvider =
    FutureProvider.autoDispose<List<PlayerAttendanceStats>>((ref) async {
  final category = ref.watch(historyCategoryProvider);
  ref.watch(attendanceEntriesProvider);
  return ref.watch(attendanceRepositoryProvider).playerStats(category: category);
});

/// Statistiques d'un joueur sur toutes ses séances (écran de détail).
final playerEntriesProvider = FutureProvider.autoDispose
    .family<List<PlayerAttendanceStats>, String>((ref, playerId) async {
  ref.watch(attendanceEntriesProvider);
  final all = await ref.read(attendanceRepositoryProvider).playerStats();
  return all.where((stat) => stat.playerId == playerId).toList();
});

/// Synthèse globale de la catégorie (bandeau de l'écran Historique).
final categoryStatsProvider =
    FutureProvider.autoDispose<AttendanceStats>((ref) async {
  final category = ref.watch(historyCategoryProvider);
  ref.watch(attendanceEntriesProvider);
  return ref.watch(attendanceRepositoryProvider).statsForCategory(category);
});
