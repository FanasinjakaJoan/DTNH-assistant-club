import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/entities/sync_queue_item.dart';
import '../auth/auth_token_source.dart';
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

/// Configuration du club renvoyée par l'Edge Function (`action: "config"`).
///
/// Elle est **distribuée aux membres authentifiés** : le secret du webhook
/// Apps Script ne figure plus dans le bundle public, il n'est lisible que par
/// un compte Google autorisé. `webhookUrl == null` signifie « pas de cible
/// Sheets pour ce club » (tout passe par Supabase).
class ClubConfig {
  const ClubConfig({
    this.target,
    this.supabaseUrl,
    this.webhookUrl,
    this.webhookSecret,
    this.sheetId,
    this.serverTime,
    this.identity,
  });

  /// Cible recommandée par le club (`SUPABASE` / `APPS_SCRIPT`), information.
  final String? target;

  /// Endpoint Supabase renvoyé par le serveur (informatif).
  final String? supabaseUrl;

  /// URL `/exec` du webhook Apps Script, ou `null`.
  final String? webhookUrl;

  /// Secret partagé du webhook Apps Script, ou `null`.
  final String? webhookSecret;

  /// Identifiant du Google Sheet du club.
  final String? sheetId;

  final DateTime? serverTime;

  /// Identité reconnue par le serveur (`google` ou `secret`).
  final String? identity;

  bool get hasSheets => (webhookUrl?.trim().isNotEmpty ?? false);

  factory ClubConfig.fromJson(Map<String, dynamic> json) {
    final sheets = json['sheets'];
    final sheetMap = sheets is Map ? Map<String, dynamic>.from(sheets) : null;
    return ClubConfig(
      target: json['target']?.toString(),
      supabaseUrl: json['supabaseUrl']?.toString(),
      webhookUrl: sheetMap?['webhookUrl']?.toString(),
      webhookSecret: sheetMap?['webhookSecret']?.toString(),
      sheetId: sheetMap?['sheetId']?.toString(),
      serverTime: DateTime.tryParse((json['serverTime'] ?? '').toString()),
      identity: json['identity']?.toString(),
    );
  }
}

/// Client HTTP des cibles de synchronisation.
///
/// **Un seul contrat pour deux backends** : l'Edge Function Supabase
/// (`dtnh-sync` → PostgreSQL) et le webhook Google Apps Script (`/exec` → Sheet)
/// reçoivent le même lot JSON et répondent un tableau de résultats par item.
/// Le client peut ainsi marquer chaque élément `SYNCED` ou `ERROR`
/// individuellement, sans rejouer tout le lot sur une seule erreur de ligne.
///
/// Le nom de la classe est conservé pour ne pas casser l'API publique du
/// package, mais elle ne dépend plus de Google : c'est un simple client de
/// webhook authentifié par secret partagé.
class AppsScriptClient {
  AppsScriptClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    AuthTokenSource? tokens,
  })  : _http = httpClient ?? http.Client(),
        _tokens = tokens ?? const AuthTokenSource();

  final http.Client _http;
  final Duration timeout;

  /// Fournit le JWT de la session Google quand elle existe. Le transport reste
  /// utilisable sans (mode hors-ligne / secret partagé seul).
  final AuthTokenSource _tokens;

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
        'URL de synchronisation invalide. Attendu : l\'URL de l\'Edge '
        'Function Supabase (/functions/v1/dtnh-sync) ou l\'URL /exec du '
        'webhook Apps Script.',
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

  /// Récupère la configuration du club auprès de l'Edge Function
  /// (`action: "config"`).
  ///
  /// Ne requiert **aucune saisie utilisateur** : le JWT de la session Google,
  /// présenté dans `Authorization` et `X-DTNH-Auth`, suffit. C'est ce qui
  /// permet à un membre simplement connecté de recevoir l'URL et le secret du
  /// webhook Sheets (qui ne sont donc plus dans le bundle public).
  ///
  /// Le secret partagé est joint quand il existe (appareil non connecté), mais
  /// n'est jamais exigé : la session Google est le chemin nominal.
  Future<ClubConfig> fetchClubConfig({
    required String webhookUrl,
    String secret = '',
  }) async {
    final uri = Uri.tryParse(webhookUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const SyncConfigurationException(
        'URL de synchronisation invalide : impossible de récupérer la '
        'configuration du club.',
      );
    }
    final body = jsonEncode(<String, dynamic>{
      'action': 'config',
      if (secret.trim().isNotEmpty) 'secret': secret.trim(),
      'sentAt': DateTime.now().toUtc().toIso8601String(),
    });
    final json = await _postJson(uri, body);
    if (json['ok'] != true) {
      throw SyncTransportException(
        (json['message'] ?? 'Configuration du club indisponible.').toString(),
        isRetryable: false,
      );
    }
    // Réponse valide, même sans cible Sheets : ce n'est pas une erreur, le
    // club synchronise alors tout vers PostgreSQL.
    return ClubConfig.fromJson(json);
  }

  /// Test de connectivité + validation du secret depuis l'écran Réglages.
  Future<String> ping({
    required String webhookUrl,
    required String secret,
  }) async {
    final uri = Uri.tryParse(webhookUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const SyncConfigurationException('URL de synchronisation invalide.');
    }
    final body = jsonEncode(<String, dynamic>{
      'action': 'ping',
      'secret': secret,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
    });
    final json = await _postJson(uri, body);
    if (json['ok'] != true) {
      throw SyncTransportException(
        (json['message'] ?? 'Le serveur a répondu par une erreur.').toString(),
        isRetryable: false,
      );
    }
    return (json['message'] ?? 'Connexion établie').toString();
  }

  /// En-têtes de la requête.
  ///
  /// Le JWT de la session Google est ajouté **s'il existe**, sur deux en-têtes :
  ///
  /// - `Authorization: Bearer <jwt>` — l'en-tête standard, compris par
  ///   Supabase (Edge Function avec `verify_jwt`) **et** par Apps Script
  ///   (`ScriptApp.getIdentityToken()` / validation via `tokeninfo`) ;
  /// - `X-DTNH-Auth: Bearer <jwt>` — conservé pour la compatibilité avec les
  ///   versions déjà déployées de la fonction `dtnh-sync`, et parce que
  ///   certains préflights CORS réécrivent `Authorization` (réservé à
  ///   `apikey` dans le client Supabase web).
  ///
  /// Sans session (mode hors-ligne), les en-têtes sont absents et le secret
  /// partagé assure seul l'authentification.
  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      // Sur le web, `application/json` sur un corps JSON déclenche un
      // préflight CORS (OPTIONS). Le web envoie donc le corps en `text/plain`
      // (« requête simple », pas de préflight) ; Apps Script lit
      // `e.postData.contents` et parse le JSON quel que soit le type déclaré.
      //
      // Côté Supabase, seuls les en-têtes `apikey` / `Authorization` /
      // `X-Client-Info` évitent le préflight : l'en-tête personnalisé
      // `X-DTNH-Auth` reste donc réservé au natif, et le web s'authentifie par
      // `Authorization` + l'`apikey` publishable.
      'Content-Type': kIsWeb
          ? 'text/plain; charset=utf-8'
          : 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    final anonKey = AppConfig.supabaseAnonKey.trim();
    if (anonKey.isNotEmpty) {
      headers['apikey'] = anonKey;
    }
    try {
      final token = await _tokens.currentAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
        if (!kIsWeb) {
          headers['X-DTNH-Auth'] = 'Bearer $token';
        }
      }
    } on Object {
      // Une session illisible ne doit jamais bloquer un envoi hors-ligne.
    }
    return headers;
  }

  /// `true` si une session Google est disponible pour ce build.
  ///
  /// Permet aux messages d'erreur de distinguer « aucun secret et aucune
  /// session » (vraiment bloquant) de « secret absent mais compte connecté »
  /// (qui fonctionne) : c'est la source de confusion qui faisait croire à une
  /// synchronisation non configurée.
  Future<bool> hasSession() async {
    try {
      final token = await _tokens.currentAccessToken();
      return token != null && token.isNotEmpty;
    } on Object {
      return false;
    }
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, String body) async {
    try {
      final response = await _http
          .post(
            uri,
            headers: await _headers(),
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode >= 500) {
        // Le corps peut contenir un diagnostic exploitable (`BOOT_ERROR` d'une
        // Edge Function mal déployée, « Function failed to start »...). On le
        // remonte tel quel : sans cela, le staff ne voit qu'un « HTTP 503 ».
        final detail = _serverMessage(response.bodyBytes);
        throw SyncTransportException(
          detail == null
              ? 'Le serveur de synchronisation est momentanément indisponible '
                  '(HTTP ${response.statusCode}).'
              : 'Le serveur de synchronisation a refusé le lot '
                  '(HTTP ${response.statusCode}) : $detail',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw SyncTransportException(
          'Accès refusé (HTTP ${response.statusCode}). Vérifiez le secret '
          'partagé de la cible (Supabase : DTNH_SHARED_SECRET ; Apps Script : '
          'Script Property SHARED_SECRET) et, si vous êtes connecté avec '
          'Google, que votre compte est autorisé.',
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
        'Le serveur de synchronisation n\'a pas renvoyé de JSON valide. '
        'Vérifiez l\'URL configurée.',
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

  /// Extrait un message d'erreur lisible d'un corps de réponse serveur.
  ///
  /// Supabase renvoie `{"message": "..."}` ou `{"code": "BOOT_ERROR",
  /// "message": "..."}` ; Apps Script renvoie `{"message": "..."}`. On renvoie
  /// `null` si rien d'exploitable n'est trouvé, pour que l'appelant garde son
  /// message générique.
  String? _serverMessage(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is! Map) return null;
      final message = decoded['message'] ?? decoded['msg'] ?? decoded['error'];
      final text = message?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text.length <= 200 ? text : '${text.substring(0, 200)}…';
    } catch (_) {
      return null;
    }
  }

  void dispose() => _http.close();
}
