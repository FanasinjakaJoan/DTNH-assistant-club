import '../../domain/entities/attendance_entry.dart';
import '../../domain/entities/financial_transaction.dart';
import '../../domain/entities/player.dart';
import '../../core/utils/date_x.dart';

/// Mapping **entité -> charge utile JSON nommée** envoyée au serveur.
///
/// Le même payload alimente les deux cibles :
/// - l'Edge Function Supabase `dtnh-sync` (qui mappe ces clés vers les colonnes
///   `dtnh_attendance`, `dtnh_transactions`, `dtnh_players`) ;
/// - le webhook Google Apps Script (section `SCHEMAS` de `apps-script/Code.gs`).
///
/// Les clés sont donc **stables** : les renommer casserait l'une des deux
/// cibles. On n'envoie jamais de tableau positionnel, pour que l'ordre des
/// colonnes puisse évoluer sans casser le client.
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
        // Traçabilité (utilisée par Supabase, ignorée par le Sheet).
        'auteurId': entry.authorId,
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
        'auteurId': tx.authorId,
        'createdAt': tx.createdAt.toIso8601String(),
      };

  static Map<String, dynamic> player(Player player) => {
        'id': player.id,
        'nom': player.fullName,
        'categorie': player.category.code,
        'numero': player.jerseyNumber,
        'telephone': player.phone,
        'actif': player.isActive,
        'createdAt': player.createdAt.toIso8601String(),
        'updatedAt': player.updatedAt.toIso8601String(),
      };

  /// Payload minimal pour une suppression logique (opération `delete`).
  static Map<String, dynamic> tombstone(String id) => {
        'id': id,
        'deleted': true,
      };
}
