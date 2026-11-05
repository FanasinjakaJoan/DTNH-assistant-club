# Protocole de synchronisation — DTNH Assistant Club

## 1. Vue d'ensemble

```
┌──────────────┐  1. écriture    ┌──────────────┐
│   UI (coach) │ ──────────────► │  Hive local  │
└──────────────┘                 └──────┬───────┘
                                        │ 2. enqueue (PENDING, coalescé)
                                        ▼
                                 ┌──────────────┐
                                 │  sync_queue  │
                                 └──────┬───────┘
            3. retour réseau / bouton   │
               ┌────────────────────────┘
               ▼
      ┌─────────────────┐  4. POST lot JSON   ┌────────────────────┐
      │   SyncEngine    │ ──────────────────► │ Google Apps Script │
      │ (app Flutter)   │ ◄────────────────── │   → Google Sheet   │
      └────────┬────────┘  5. résultats/item └────────────────────┘
               │ 6. SYNCED / ERROR par item
               ▼
        entité.syncState + syncedAt  →  UI (icône nuage)
```

## 2. Machine à états de la file

```
                 enqueue()                envoyé (réponse ok)
      ┌───────┐ ─────────► ┌─────────┐ ─────────────────────► ┌────────┐
      │ ∅     │            │ PENDING │                        │ SYNCED │
      └───────┘            └────┬────┘ ◄──── resetForRetry() ──└────────┘
                                │ échec réseau ou item refusé        ▲
                                ▼                                    │
                           ┌────────┐ ─── envoi réussi ─────────────┘
                           │ ERROR  │
                           └────────┘
                                │  attempts ≥ 8 → reste ERROR
                                │  (réessayable manuellement)
```

| Transition | Déclencheur | Effet |
|---|---|---|
| `∅ → PENDING` | `enqueue()` après écriture métier | Item créé **ou** payload fusionné si un PENDING existe déjà pour la même entité |
| `PENDING → SYNCED` | réponse `ok` ou `duplicate` | `attempts++`, `syncedAt`, `batchId`, entité `syncState = synced` |
| `PENDING → ERROR` | panne réseau **ou** item refusé | `attempts++`, `lastError`, entité `syncState = error` |
| `ERROR → PENDING` | `resetForRetry()` (manuel) ou relance | `attempts = 0`, `lastError = null` |
| `SYNCED → ∅` | `clearSynced()` (nettoyage) | Historique de la file purgé |

**Pourquoi un `ERROR` reste dans la file** : le staff doit voir ce qui n'est pas
passé, pouvoir lire le message et réessayer. Une file qui s'auto-vide masquerait
une perte de données.

## 3. Coalescence (une entité = un envoi)

```
Pointage U16 à 08:45 : p1 = PRESENT   → item A (PENDING, payload v1)
Correction 08:47     : p1 = LATE      → item A **mis à jour** (payload v2)
Correction 08:50     : p1 = EXCUSED   → item A **mis à jour** (payload v3)
Retour réseau 08:52                   → 1 seule requête, payload v3
```

Implémentation : `SyncQueueDao.findPendingFor(entityType, entityId)`. Seuls les
items encore `PENDING` sont fusionnés ; un item `ERROR` **n'est jamais écrasé
silencieusement** (il conserve son message d'erreur pour diagnostic), et un item
`SYNCED` est laissé tel quel.

Effet de bord volontaire : envoyer deux fois « Présent » puis « Absent » ne
produit qu'une ligne et un seul appel réseau — et le Sheet contient l'état final.

## 4. Format d'échange

### 4.1 Requête

```http
POST https://script.google.com/macros/s/<DEPLOY_ID>/exec
Content-Type: application/json; charset=utf-8
```

```json
{
  "action": "push",
  "secret": "<SHARED_SECRET>",
  "deviceId": "0f1c9b2e-…",
  "batchId": "5c8f0f4a-…",
  "sentAt": "2026-11-05T09:12:03.412Z",
  "items": [
    {
      "id": "<uuid de l'item de file>",
      "entity": "attendance",
      "sheet": "Présences",
      "operation": "upsert",
      "data": { "id": "<uuid entité>", "date": "2026-11-05", "categorie": "U16", "...": "..." }
    }
  ]
}
```

- `sheet` est redondant avec `entity` : le serveur accepte l'un ou l'autre
  (`resolveSheetName_`), ce qui tolère un client plus ancien.
- `data.id` est **obligatoire** : sans lui, pas d'idempotence, donc refus explicite.

### 4.2 Réponse

```json
{
  "ok": false,
  "message": "2 ligne(s) OK, 1 en erreur.",
  "serverTime": "2026-11-05T09:12:04.512Z",
  "results": [
    { "id": "item-1", "sheet": "Présences", "status": "ok" },
    { "id": "item-2", "sheet": "Présences", "status": "duplicate" },
    { "id": "item-3", "sheet": "Transactions", "status": "error", "error": "Montant manquant" }
  ]
}
```

Le client apparie `results[].id` avec **l'id de l'item de file** (pas l'id
métier) : c'est ce qui permet un succès partiel propre.

Cas dégradé : si le serveur répond `ok: true` sans `results`, tous les items du
lot sont considérés comme traités (compatibilité avec un webhook minimal).

## 5. Politique de tentatives

| Situation | Classification client | Comportement |
|---|---|---|
| `SocketException`, DNS, timeout 30 s | `SyncOfflineException` | Tous les items du lot : `attempts++`, `ERROR`, message lisible |
| HTTP 5xx | `SyncTransportException(retryable)` | idem |
| HTTP 401/403 | `SyncTransportException(isRetryable: false)` | idem + message « vérifiez le déploiement (Tout le monde) » |
| HTTP 4xx autre | non réessayable | idem |
| Réponse non JSON | non réessayable | message « vérifiez l'URL /exec » |
| `ok:false` + `retryable:true` (verrou Apps Script) | réessayable | aucune perte, l'item repart |
| Item `status:error` | refus métier | seul cet item passe en `ERROR` |

- **Plafond** : `maxAttempts = 8` (constante `SyncEngine.maxAttempts`). Au-delà,
  l'item reste `ERROR` et n'est plus proposé automatiquement ; il reste
  réessayable à la main depuis l'écran Synchro.
- **Déclencheurs** :
  1. transition réseau `none → wifi/mobile` (`connectivity_plus`) avec debounce
     de 3 s (le temps que le Wi-Fi du gymnase s'authentifie) ;
  2. bouton « Synchroniser maintenant » (boucle `drain`, max 10 lots) ;
  3. Workmanager toutes les 15 min (contrainte : réseau disponible) ;
  4. après un enregistrement réussi si `autoSync` est activé et le réseau présent.

## 6. Idempotence et cas limites

| Cas | Comportement |
|---|---|
| **Timeout après écriture serveur** (réponse perdue) | L'item repart ; Apps Script retrouve l'ID en colonne A et **met à jour** la ligne → aucun doublon. |
| **Deux téléphones synchronisent ensemble** | `LockService.getScriptLock()` sérialise ; le second reçoit `retryable:true` et repartira. |
| **App tuée pendant l'envoi** | L'item est encore `PENDING` (le marquage se fait après la réponse) → renvoyé au prochain démarrage. |
| **Item envoyé deux fois dans le même lot** | Le serveur réserve l'ID virtuellement (`index[id] = -n`) ⇒ la 2ᵉ occurrence est traitée comme `duplicate`. |
| **Horloge du téléphone fausse** | Le `SyncTimestamp` est **généré côté serveur** ; la date métier reste celle saisie par le staff. |
| **Suppression d'une transaction** | Item `operation: delete` + payload `{id, deleted:true}` ; le serveur supprime la ligne. L'entité locale est supprimée immédiatement. |
| **Webhook changé / secret tourné** | Réglages → nouveau secret → « Tester » ; les items en `ERROR` sont réessayés sans perte. |
| **Fuseau horaire** | Dates métier au format `yyyy-MM-dd` (jour local) ; horodatages techniques en ISO UTC. |

## 7. Sécurité

- **Aucun OAuth, aucune clé de service dans l'APK.** Le téléphone ne connaît
  qu'une URL et un secret révocable.
- Le secret vit dans les `Script Properties` du Sheet, pas dans le code.
- Toutes les requêtes passent en **HTTPS** (Apps Script l'impose).
- Le webhook refuse tout `POST` sans secret valide et journalise le refus dans
  `_Journal` (appareil, lot, date).
- Le client n'émet **jamais** de requête vers un domaine autre que celui de
  l'URL configurée par l'administrateur.
- Rotation : `setup()` conserve le secret existant ; pour le changer, modifier la
  propriété `SHARED_SECRET` puis mettre à jour les téléphones.

> ⚠️ Limite assumée : le secret est stocké dans la box Hive `settings_v1`
> (non chiffrée). Pour un durcissement, remplacer `SettingsRepositoryImpl` par
> une implémentation `flutter_secure_storage` — l'interface `SettingsRepository`
> est déjà abstraite, aucun autre fichier ne change.

## 8. Supervision

Onglet `_Journal` (masqué) :

| Reçu le | Appareil | Lot | Action | Éléments | OK | Erreurs | Statut |
|---|---|---|---|---|---|---|---|
| 2026-11-05T09:12:04Z | 0f1c… | 5c8f… | push | 15 | 15 | 0 | OK |
| 2026-11-05T09:20:11Z | 7a2b… | 91de… | push | 3 | 2 | 1 | PARTIEL |

Côté application, l'écran **Synchro** expose les mêmes informations : compteurs
(en attente / erreurs / envoyés), file détaillée avec message d'erreur,
`attempts`, et bouton de réessai individuel.

## 9. Tests manuels (curl)

```bash
# 1. Test de vie
curl -s "https://script.google.com/macros/s/<ID>/exec?secret=<SECRET>&action=ping"

# 2. Envoi d'une ligne de présence
curl -s -X POST "https://script.google.com/macros/s/<ID>/exec" \
  -H "Content-Type: application/json" \
  -d '{
    "action":"push",
    "secret":"<SECRET>",
    "deviceId":"curl-test",
    "batchId":"test-001",
    "items":[{
      "id":"item-1",
      "entity":"attendance",
      "operation":"upsert",
      "data":{
        "id":"ent-1","date":"2026-11-05","categorie":"U16",
        "joueur":"Rakotobe Fandresena","statut":"PRESENT",
        "auteur":"Coach Tojo","heure":"08:45"
      }
    }]
  }'

# 3. Rejouer exactement la même requête
#    → status "duplicate", aucune nouvelle ligne dans le Sheet.
```

## 10. Limites connues / évolutions

1. **Pas de pull pour l'instant** : le Sheet n'est pas relu (le roster se saisit
   dans l'app). Un `action: "pull"` est prévu en v1.2 pour importer les licences
   saisies par le secrétariat.
2. **Pas de résolution de conflits** : la dernière écriture gagne (upsert). C'est
   acceptable pour un club où un seul staff pointe une séance donnée ; un champ
   `updatedAt` est déjà transmis pour ajouter plus tard une règle « le plus récent
   gagne » côté serveur.
3. **Taille de lot 80** : au-delà, découper. Apps Script supporte ~6 min
   d'exécution, très au-delà d'un lot de 80 lignes.
