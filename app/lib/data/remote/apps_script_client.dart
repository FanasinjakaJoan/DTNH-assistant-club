import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../../core/errors/app_exception.dart';
import '../../domain/entities/sync_queue_item.dart';
import 'network_error.dart' as net_error;

/// Une entrée du lot envoyé au webhook.
class SheetBatchEntry {
  const SheetBatchEntry({required this.item});

  final SyncQueueItem item;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': item.id,
        'entity': item.entityType.code,
        'sheet': item.entityType.sheetName,
        'operation': item.operation.code,
        'data': item.payload,
      };
}

/// Résultat renvoyé par Apps Script pour une entrée du lot.
class SheetItemResult {
  const SheetItemResult({
    required this.id,
    required this.ok,
    this.error,
    this.duplicate = false,
  });

  final String id;
  final bool ok;
  final String? error;

  /// `true` si la ligne existait déjà (upsert idempotent) : c'est un succès.
  final bool duplicate;
}

/// Réponse complète du webhook.
class SheetBatchResponse {
  const SheetBatchResponse({
    required this.ok,
    required this.message,
    required this.results,
    this.serverTime,
  });

  final bool ok;
  final String message;
  final List<SheetItemResult> results;
  final DateTime? serverTime;

  SheetItemResult? resultFor(String id) {
    for (final result in results) {
      if (result.id == id) return result;
    }
    return null;
  }

  factory SheetBatchResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'];
    final results = <SheetItemResult>[];
    if (rawResults is List) {
      for (final entry in rawResults) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final id = map['id']?.toString();
        if (id == null) continue;
        final status = map['status']?.toString().toLowerCase();
        results.add(
          SheetItemResult(
            id: id,
            ok: status == 'ok' || status == 'duplicate' || map['ok'] == true,
            error: map['error']?.toString(),
            duplicate: status == 'duplicate',
          ),
        );
      }
    }
    return SheetBatchResponse(
      ok: json['ok'] == true,
      message: (json['message'] ?? '').toString(),
      results: results,
      serverTime: DateTime.tryParse((json['serverTime'] ?? '').toString()),
    );
  }
}

/// Client du webhook Google Apps Script.
///
/// Le webhook reçoit un **lot** JSON et répond un tableau de résultats par
/// item : le client peut ainsi marquer chaque élément `SYNCED` ou `ERROR`
/// individuellement, sans rejouer tout le lot sur une seule erreur de ligne.
class AppsScriptClient {
  AppsScriptClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  Future<SheetBatchResponse> sendBatch({
    required String webhookUrl,
    required String secret,
    required String deviceId,
    required String batchId,
    required List<SheetBatchEntry> entries,
  }) async {
    final uri = Uri.tryParse(webhookUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const SyncConfigurationException(
        'URL de webhook invalide. Collez l\'URL /exec du déploiement '
        'Google Apps Script.',
      );
    }

    final body = jsonEncode(<String, dynamic>{
      'action': 'push',
      'secret': secret,
      'deviceId': deviceId,
      'batchId': batchId,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'items': entries.map((entry) => entry.toJson()).toList(),
    });

    final json = await _postJson(uri, body);
    final response = SheetBatchResponse.fromJson(json);

    if (!response.ok && response.results.isEmpty) {
      throw SyncTransportException(
        response.message.isEmpty
            ? 'Le serveur a refusé le lot (réponse non conforme).'
            : response.message,
        isRetryable: false,
      );
    }
    return response;
  }

  /// Test de connectivité + validation du secret depuis l'écran Réglages.
  Future<String> ping({
    required String webhookUrl,
    required String secret,
  }) async {
    final uri = Uri.tryParse(webhookUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const SyncConfigurationException('URL de webhook invalide.');
    }
    final body = jsonEncode(<String, dynamic>{
      'action': 'ping',
      'secret': secret,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
    });
    final json = await _postJson(uri, body);
    if (json['ok'] != true) {
      throw SyncTransportException(
        (json['message'] ?? 'Le webhook a répondu par une erreur.').toString(),
        isRetryable: false,
      );
    }
    return (json['message'] ?? 'Connexion établie').toString();
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, String body) async {
    try {
      final response = await _http
          .post(
            uri,
            headers: const <String, String>{
              // Sur le web, `application/json` déclenche un préflight CORS
              // (OPTIONS) que Google Apps Script ne gère pas. `text/plain` en
              // fait une requête « simple » (pas de préflight) ; Apps Script lit
              // `e.postData.contents` et parse le JSON quel que soit le type.
              // En natif (Android/iOS), pas de CORS : on garde `application/json`.
              'Content-Type': kIsWeb
                  ? 'text/plain; charset=utf-8'
                  : 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode >= 500) {
        throw SyncTransportException(
          'Le service Google est momentanément indisponible '
          '(HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw SyncTransportException(
          'Accès refusé (HTTP ${response.statusCode}). Vérifiez que le '
          'déploiement Apps Script est bien accessible à « Tout le monde ».',
          statusCode: response.statusCode,
          isRetryable: false,
        );
      }
      if (response.statusCode >= 400) {
        throw SyncTransportException(
          'Requête refusée (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
          isRetryable: false,
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const SyncTransportException(
          'Réponse inattendue du webhook (JSON objet attendu).',
          isRetryable: false,
        );
      }
      return Map<String, dynamic>.from(decoded);
    } on SyncTransportException {
      rethrow;
    } on SyncConfigurationException {
      rethrow;
    } on TimeoutException catch (error) {
      throw SyncTransportException(
        'Délai dépassé : le réseau est trop lent, la synchronisation sera '
        'retentée automatiquement.',
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw SyncTransportException(
        'Échec réseau : ${error.message}',
        cause: error,
      );
    } on FormatException catch (error) {
      throw SyncTransportException(
        'Le webhook n\'a pas renvoyé de JSON valide. Vérifiez l\'URL /exec.',
        isRetryable: false,
        cause: error,
      );
    } catch (error) {
      // `SocketException` (natif) est détectée via un import conditionnel :
      // `dart:io` n'existe pas sur le web, où les coupures réseau remontent
      // déjà via `http.ClientException` ci-dessus. On convertit en
      // `SyncOfflineException` pour que le moteur déclenche son backoff.
      if (net_error.isOfflineError(error)) {
        throw SyncOfflineException(
          'Aucune connexion Internet exploitable : '
          '${net_error.offlineErrorMessage(error)}.',
        );
      }
      rethrow;
    }
  }

  void dispose() => _http.close();
}
