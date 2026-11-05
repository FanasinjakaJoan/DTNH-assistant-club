import 'dart:io';

import 'package:dtnh_assistant_club/data/local/dao/attendance_dao.dart';
import 'package:dtnh_assistant_club/data/local/dao/sync_queue_dao.dart';
import 'package:dtnh_assistant_club/data/local/dao/transaction_dao.dart';
import 'package:dtnh_assistant_club/data/local/local_database.dart';
import 'package:dtnh_assistant_club/data/repositories/attendance_repository_impl.dart';
import 'package:dtnh_assistant_club/data/repositories/sync_queue_repository_impl.dart';
import 'package:dtnh_assistant_club/data/repositories/transaction_repository_impl.dart';
import 'package:dtnh_assistant_club/domain/entities/financial_transaction.dart';
import 'package:dtnh_assistant_club/domain/entities/player.dart';
import 'package:dtnh_assistant_club/domain/enums/attendance_status.dart';
import 'package:dtnh_assistant_club/domain/enums/sync_enums.dart';
import 'package:dtnh_assistant_club/domain/enums/team_category.dart';
import 'package:dtnh_assistant_club/domain/enums/transaction_enums.dart';
import 'package:dtnh_assistant_club/domain/repositories/sync_queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests d'intégration du stockage local (Hive dans un dossier temporaire).
///
/// Ils vérifient l'invariant central de l'application offline-first :
/// **écriture locale immédiate + file d'attente coalescée + idempotence**.
void main() {
  late Directory tempDir;
  late LocalDatabase database;
  late SyncQueueRepository queue;
  late AttendanceRepositoryImpl attendanceRepository;
  late TransactionRepositoryImpl transactionRepository;

  final sessionDate = DateTime(2026, 11, 5);

  Player player(String id, String name, int jersey) => Player(
        id: id,
        fullName: name,
        category: TeamCategory.u16,
        jerseyNumber: jersey,
        createdAt: sessionDate,
        updatedAt: sessionDate,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dtnh_test_');
    database = await LocalDatabase.open(directory: tempDir.path);
    queue = SyncQueueRepositoryImpl(dao: SyncQueueDao(database));
    attendanceRepository = AttendanceRepositoryImpl(
      dao: AttendanceDao(database),
      queue: queue,
    );
    transactionRepository = TransactionRepositoryImpl(
      dao: TransactionDao(database),
      queue: queue,
    );
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Pointage', () {
    test('enregistre les présences et alimente la file', () async {
      final players = [
        player('p1', 'Rakotobe Fandresena', 3),
        player('p2', 'Andriamihaja Tsiory', 4),
      ];

      await attendanceRepository.saveSession(
        category: TeamCategory.u16,
        date: sessionDate,
        players: players,
        statuses: {
          'p1': AttendanceStatus.present,
          'p2': AttendanceStatus.late,
        },
        authorId: 'coach-1',
        authorName: 'Coach Tojo',
      );

      final entries = await attendanceRepository.entriesForSession(
        category: TeamCategory.u16,
        date: sessionDate,
      );

      expect(entries, hasLength(2));
      expect(
        entries.firstWhere((e) => e.playerId == 'p2').status,
        AttendanceStatus.late,
      );
      expect(entries.every((e) => e.authorName == 'Coach Tojo'), isTrue);
      expect(entries.every((e) => e.syncState == SyncState.pending), isTrue);

      final counters = await queue.counters();
      expect(counters.pending, 2);
    });

    test('re-pointer la même séance met à jour sans dupliquer', () async {
      final players = [
        player('p1', 'Rakotobe Fandresena', 3),
        player('p2', 'Andriamihaja Tsiory', 4),
      ];

      await attendanceRepository.saveSession(
        category: TeamCategory.u16,
        date: sessionDate,
        players: players,
        statuses: {
          'p1': AttendanceStatus.present,
          'p2': AttendanceStatus.absent,
        },
        authorId: 'coach-1',
        authorName: 'Coach Tojo',
      );

      final first = await attendanceRepository.entriesForSession(
        category: TeamCategory.u16,
        date: sessionDate,
      );
      final firstIds = first.map((e) => e.id).toSet();

      await attendanceRepository.saveSession(
        category: TeamCategory.u16,
        date: sessionDate,
        players: players,
        statuses: {
          'p1': AttendanceStatus.present,
          'p2': AttendanceStatus.excused,
        },
        authorId: 'coach-2',
        authorName: 'Coach Naina',
      );

      final second = await attendanceRepository.entriesForSession(
        category: TeamCategory.u16,
        date: sessionDate,
      );

      expect(second, hasLength(2));
      expect(second.map((e) => e.id).toSet(), firstIds);
      expect(
        second.firstWhere((e) => e.playerId == 'p2').status,
        AttendanceStatus.excused,
      );
      expect(
        second.firstWhere((e) => e.playerId == 'p2').authorName,
        'Coach Naina',
      );
      // Un seul item en file par entité : pas de doublon d'envoi.
      expect((await queue.counters()).pending, 2);
    });

    test('un joueur décoché est retiré de la séance', () async {
      final players = [
        player('p1', 'A', 3),
        player('p2', 'B', 4),
      ];

      await attendanceRepository.saveSession(
        category: TeamCategory.u16,
        date: sessionDate,
        players: players,
        statuses: {'p1': AttendanceStatus.present, 'p2': AttendanceStatus.present},
        authorId: 'coach-1',
        authorName: 'Coach Tojo',
      );

      await attendanceRepository.saveSession(
        category: TeamCategory.u16,
        date: sessionDate,
        players: players,
        statuses: {'p1': AttendanceStatus.present},
        authorId: 'coach-1',
        authorName: 'Coach Tojo',
      );

      final entries = await attendanceRepository.entriesForSession(
        category: TeamCategory.u16,
        date: sessionDate,
      );
      expect(entries, hasLength(1));
      expect(entries.first.playerId, 'p1');
    });

    test('agrège les statistiques par joueur et par séance', () async {
      final players = [player('p1', 'A', 3), player('p2', 'B', 4)];

      await attendanceRepository.saveSession(
        category: TeamCategory.u16,
        date: DateTime(2026, 11, 3),
        players: players,
        statuses: {
          'p1': AttendanceStatus.present,
          'p2': AttendanceStatus.absent,
        },
        authorId: 'coach-1',
        authorName: 'Coach Tojo',
      );
      await attendanceRepository.saveSession(
        category: TeamCategory.u16,
        date: sessionDate,
        players: players,
        statuses: {
          'p1': AttendanceStatus.late,
          'p2': AttendanceStatus.present,
        },
        authorId: 'coach-1',
        authorName: 'Coach Tojo',
      );

      final sessions = await attendanceRepository.recentSessions(
        category: TeamCategory.u16,
      );
      expect(sessions, hasLength(2));
      expect(sessions.first.date, sessionDate);
      expect(sessions.first.stats.total, 2);

      final stats = await attendanceRepository.playerStats(
        category: TeamCategory.u16,
      );
      expect(stats, hasLength(2));
      final p1 = stats.firstWhere((s) => s.playerId == 'p1');
      expect(p1.stats.total, 2);
      expect(p1.stats.attended, 2); // présent + retard
      expect(p1.stats.rate, 1);
    });
  });

  group('Transactions', () {
    FinancialTransaction makeTransaction({
      required String id,
      required int amount,
      TransactionFlow flow = TransactionFlow.income,
    }) {
      final now = DateTime(2026, 11, 5, 9, 30);
      return FinancialTransaction(
        id: id,
        date: sessionDate,
        flow: flow,
        category: flow == TransactionFlow.income
            ? TransactionCategory.ecolage
            : TransactionCategory.locationTerrain,
        amount: amount,
        paymentMethod: PaymentMethod.mvola,
        playerName: 'Rasoa Miora',
        periodMonth: '2026-11',
        authorId: 'tresorier-1',
        authorName: 'Trésorier',
        createdAt: now,
        updatedAt: now,
      );
    }

    test('sauvegarde locale + file d\'attente', () async {
      await transactionRepository.save(makeTransaction(id: 't1', amount: 60000));

      final all = await transactionRepository.all();
      expect(all, hasLength(1));
      expect(all.first.amount, 60000);
      expect(all.first.syncState, SyncState.pending);
      expect((await queue.counters()).pending, 1);
    });

    test('suppression = tombstone dans la file', () async {
      await transactionRepository.save(makeTransaction(id: 't1', amount: 60000));
      await transactionRepository.delete('t1');

      expect(await transactionRepository.all(), isEmpty);
      final pending = await queue.pendingBatch(limit: 10);
      expect(pending, hasLength(1));
      expect(pending.first.entityId, 't1');
      expect(pending.first.operation, SyncOperation.delete);
      expect(pending.first.payload['deleted'], isTrue);
    });

    test('une modification avant envoi fusionne l\'item de file', () async {
      await transactionRepository.save(makeTransaction(id: 't1', amount: 60000));
      await transactionRepository.save(makeTransaction(id: 't1', amount: 75000));

      final pending = await queue.pendingBatch(limit: 10);
      expect(pending, hasLength(1));
      expect(pending.first.payload['montant'], 75000);
    });
  });
}
