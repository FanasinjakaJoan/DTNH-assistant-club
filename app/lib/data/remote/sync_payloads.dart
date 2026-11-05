import '../../domain/entities/attendance_entry.dart';
import '../../domain/entities/financial_transaction.dart';
import '../../domain/entities/player.dart';
import '../../core/utils/date_x.dart';

/// Mapping **entité -> charge utile JSON nommée** envoyée au webhook.
///
/// Les clés sont stables et doivent correspondre aux `fields` déclarés dans
/// `apps-script/Code.gs` (section `SCHEMAS`). On n'envoie jamais de tableau
/// positionnel : l'ordre des colonnes du Sheet peut évoluer sans casser le
/// client.
class SyncPayloads {
  const SyncPayloads._();

  static Map<String, dynamic> attendance(AttendanceEntry entry) => {
        'id': entry.id,
        'date': entry.sessionDate.ymd,
        'categorie': entry.category.code,
        'joueur': entry.playerName,
        'statut': entry.status.code,
        'auteur': entry.authorName,
        'heure': entry.recordedAt.hm,
        'joueurId': entry.playerId,
        'sessionId': entry.sessionId,
        'numero': entry.jerseyNumber,
        'note': entry.note,
        'updatedAt': entry.updatedAt.toIso8601String(),
      };

  static Map<String, dynamic> transaction(FinancialTransaction tx) => {
        'id': tx.id,
        'date': tx.date.ymd,
        'flux': tx.flow.code,
        'categorie': tx.category.code,
        'montant': tx.amount,
        'details': tx.details ?? tx.summary,
        'auteur': tx.authorName,
        'modePaiement': tx.paymentMethod.code,
        'joueur': tx.playerName,
        'staff': tx.staffName,
        'evenement': tx.eventName,
        'mois': tx.periodMonth,
        'updatedAt': tx.updatedAt.toIso8601String(),
      };

  static Map<String, dynamic> player(Player player) => {
        'id': player.id,
        'nom': player.fullName,
        'categorie': player.category.code,
        'numero': player.jerseyNumber,
        'telephone': player.phone,
        'actif': player.isActive,
      };

  /// Payload minimal pour une suppression logique (opération `delete`).
  static Map<String, dynamic> tombstone(String id) => {
        'id': id,
        'deleted': true,
      };
}
