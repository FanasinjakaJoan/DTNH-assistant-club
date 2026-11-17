import 'package:dtnh_assistant_club/data/local/adapters/player_adapter.dart';
import 'dart:typed_data';

import 'package:dtnh_assistant_club/data/remote/sync_payloads.dart';
import 'package:dtnh_assistant_club/domain/entities/player.dart';
import 'package:dtnh_assistant_club/domain/enums/sync_enums.dart';
import 'package:dtnh_assistant_club/domain/enums/team_category.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// Les implémentations concrètes de `BinaryReader`/`BinaryWriter` ne sont pas
// exposées par l'API publique de Hive : les tests d'adapter doivent passer par
// `src/`. C'est le prix d'un adapter écrit à la main (sans `build_runner`).
// ignore: implementation_imports
import 'package:hive/src/binary/binary_reader_impl.dart';
// ignore: implementation_imports
import 'package:hive/src/binary/binary_writer_impl.dart';
// ignore: implementation_imports
import 'package:hive/src/registry/type_registry_impl.dart';

/// Écrit un enregistrement **v1** (schéma d'origine, sans date de naissance) :
/// c'est exactement ce que contiennent les téléphones du staff ayant installé
/// l'application avant l'ajout du champ.
List<int> _v1RecordBytes() {
  final registry = TypeRegistryImpl();
  final writer = BinaryWriterImpl(registry);
  writer.writeByte(1); // version du schéma
  writer.writeString('p-legacy');
  writer.writeString('Rakoto Ancien');
  writer.writeString('U16');
  writer.writeBool(true); // jerseyNumber présent
  writer.writeInt(9);
  writer.writeBool(false); // phone absent
  writer.writeBool(true); // isActive
  writer.writeInt(DateTime(2026, 1, 1).millisecondsSinceEpoch); // createdAt
  writer.writeInt(DateTime(2026, 1, 2).millisecondsSinceEpoch); // updatedAt
  writer.writeString('synced'); // syncState
  writer.writeBool(true); // syncedAt présent
  writer.writeInt(DateTime(2026, 1, 2).millisecondsSinceEpoch);
  return writer.toBytes();
}

BinaryReader _readerFor(List<int> bytes) =>
    BinaryReaderImpl(Uint8List.fromList(bytes), TypeRegistryImpl());

void main() {
  group('Player — âge et catégorie', () {
    Player build({DateTime? birthDate}) => Player(
          id: 'p1',
          fullName: 'Rasoa Miora',
          category: TeamCategory.u14u15,
          birthDate: birthDate,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('sans date de naissance : âge inconnu, aucune suggestion', () {
      final player = build();
      expect(player.age, isNull);
      expect(player.suggestedCategory, isNull);
      expect(player.birthDateYmd, isNull);
    });

    test('anniversaire non encore passé : l\'année ne compte pas', () {
      final player = build(birthDate: DateTime(2012, 12, 31));
      // Le 17 novembre 2026, ce joueur a 13 ans (pas encore 14).
      expect(player.ageAt(DateTime(2026, 11, 17)), 13);
      expect(player.ageAt(DateTime(2026, 12, 31)), 14);
    });

    test('anniversaire du jour même : l\'année compte', () {
      final player = build(birthDate: DateTime(2012, 11, 17));
      expect(player.ageAt(DateTime(2026, 11, 17)), 14);
      expect(player.ageAt(DateTime(2026, 11, 16)), 13);
    });

    test('né un 29 février : convention stable en année non bissextile', () {
      final player = build(birthDate: DateTime(2012, 2, 29));
      // 2026 n'est pas bissextile : le 28 février le joueur a encore 13 ans,
      // il en a 14 le 1er mars. Ce qui compte est que la réponse soit
      // déterministe et sans saut d'année parasite.
      expect(player.ageAt(DateTime(2026, 2, 28)), 13);
      expect(player.ageAt(DateTime(2026, 3, 1)), 14);
    });

    test('catégorie suggérée selon l\'âge', () {
      expect(build(birthDate: DateTime(2016, 1, 1)).suggestedCategory,
          TeamCategory.u12);
      expect(build(birthDate: DateTime(2013, 1, 1)).suggestedCategory,
          TeamCategory.u14u15);
      expect(build(birthDate: DateTime(2010, 1, 1)).suggestedCategory,
          TeamCategory.u16);
      expect(build(birthDate: DateTime(2008, 1, 1)).suggestedCategory,
          TeamCategory.u17u18);
    });

    test('âge hors barème : aucune catégorie imposée', () {
      // 5 ans : trop jeune pour U12 ; 30 ans : au-delà de U17-U18.
      expect(build(birthDate: DateTime(2021, 1, 1)).suggestedCategory, isNull);
      expect(build(birthDate: DateTime(1996, 1, 1)).suggestedCategory, isNull);
    });

    test('date de naissance future : âge inconnu, jamais négatif', () {
      final player = build(birthDate: DateTime(2030, 1, 1));
      expect(player.ageAt(DateTime(2026, 11, 17)), isNull);
    });

    test('birthDateYmd est au format yyyy-MM-dd', () {
      final player = build(birthDate: DateTime(2010, 4, 7));
      expect(player.birthDateYmd, '2010-04-07');
    });

    test('copyWith : mise à jour puis effacement de la date', () {
      final player = build(birthDate: DateTime(2010, 4, 7));
      final updated = player.copyWith(birthDate: DateTime(2011, 5, 8));
      expect(updated.birthDateYmd, '2011-05-08');

      final cleared = updated.copyWith(clearBirthDate: true);
      expect(cleared.birthDate, isNull);
      expect(cleared.age, isNull);
    });
  });

  group('PlayerAdapter — migration v1 -> v2', () {
    late PlayerAdapter adapter;

    setUp(() => adapter = PlayerAdapter());

    test('lit un enregistrement v1 et le complète sans date de naissance',
        () {
      final player = adapter.read(_readerFor(_v1RecordBytes()));

      expect(player.id, 'p-legacy');
      expect(player.fullName, 'Rakoto Ancien');
      expect(player.category, TeamCategory.u16);
      expect(player.jerseyNumber, 9);
      expect(player.phone, isNull);
      expect(player.isActive, isTrue);
      expect(player.syncState, SyncState.synced);
      expect(player.syncedAt, DateTime(2026, 1, 2));
      // Le champ nouveau est simplement absent : aucune donnée inventée.
      expect(player.birthDate, isNull);
      expect(player.age, isNull);
    });

    test('relit en v2 ce qu\'il vient d\'écrire (aller-retour)', () {
      final player = Player(
        id: 'p-new',
        fullName: 'Rasoa Miora',
        category: TeamCategory.u14u15,
        birthDate: DateTime(2012, 4, 17),
        jerseyNumber: 7,
        phone: '0340000000',
        createdAt: DateTime(2026, 11, 5),
        updatedAt: DateTime(2026, 11, 5),
      );

      final writer = BinaryWriterImpl(TypeRegistryImpl());
      adapter.write(writer, player);
      final read = adapter.read(_readerFor(writer.toBytes()));

      expect(read.id, player.id);
      expect(read.fullName, player.fullName);
      expect(read.category, player.category);
      expect(read.birthDateYmd, '2012-04-17');
      expect(read.jerseyNumber, 7);
      expect(read.phone, '0340000000');
      expect(read.createdAt, player.createdAt);
      expect(read.syncState, player.syncState);
    });

    test('version inconnue : échec explicite plutôt que données corrompues',
        () {
      final writer = BinaryWriterImpl(TypeRegistryImpl())..writeByte(99);
      expect(
        () => adapter.read(_readerFor(writer.toBytes())),
        throwsA(isA<HiveError>()),
      );
    });
  });

  group('SyncPayloads.player', () {
    test('transmet la date de naissance au format attendu par le serveur', () {
      final player = Player(
        id: 'p1',
        fullName: 'Rasoa Miora',
        category: TeamCategory.u14u15,
        birthDate: DateTime(2012, 4, 17),
        jerseyNumber: 7,
        createdAt: DateTime(2026, 11, 5),
        updatedAt: DateTime(2026, 11, 5),
      );

      final payload = SyncPayloads.player(player);
      expect(payload['dateNaissance'], '2012-04-17');
    });

    test('date absente : la clé existe avec la valeur null', () {
      final player = Player(
        id: 'p2',
        fullName: 'Sans Date',
        category: TeamCategory.u12,
        createdAt: DateTime(2026, 11, 5),
        updatedAt: DateTime(2026, 11, 5),
      );

      final payload = SyncPayloads.player(player);
      expect(payload.containsKey('dateNaissance'), isTrue);
      expect(payload['dateNaissance'], isNull);
    });
  });
}
