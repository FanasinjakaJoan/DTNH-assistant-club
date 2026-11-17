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
      │   SyncEngine    │ ──────────────────► │ Edge Function      │
      │ (app Flutter)   │ ◄────────────────── │ dtnh-sync          │
      └────────┬────────┘  5. résultats/item │   → PostgreSQL     │
               │ 6. SYNCED / ERROR par item  └────────────────────┘
               ▼                                       │ ou
        entité.syncState + syncedAt                     ▼
        →  UI (icône nuage)                    ┌────────────────────┐
                                               │ Webhook Apps Script│
                                               │   → Google Sheet   │
                                               └────────────────────┘
```

### 1.0 Configuration : se connecter suffit

**L'utilisateur n'a rien à configurer.** Il se connecte avec son compte Google
et c'est tout : la session ouvre l'accès à la configuration du club, que
l'application récupère automatiquement.

```
     Connexion Google réussie
              │
              ▼
   POST /functions/v1/dtnh-sync   { "action": "config" }
   Authorization: Bearer <jwt>
              │
              ▼
   ┌─────────────────────────────────────┐
   │ { ok: true,                         │
   │   sheets: {                         │
   │     webhookUrl:    "…/exec",        │   ← zéro saisie
   │     webhookSecret: "…",             │
   │     sheetId:       "1VuV…" } }      │
   └─────────────────────────────────────┘
              │
              ▼
   AppSettings.clubWebhookUrl / clubWebhookSecret / clubSheetId
```

D'où viennent ces valeurs ? D'une **ligne unique** de la base
(`dtnh_club_config`), avec repli sur les secrets de la fonction :

| Source | Modifiable sans redéploiement | Remarque |
|---|---|---|
| `public.dtnh_club_config` (ligne `id = 1`) | ✅ un simple `update` SQL | source nominale |
| `DTNH_SHEETS_WEBHOOK_URL` / `_SECRET` / `DTNH_SHEET_ID` | ❌ nécessite un redéploiement | repli de compatibilité |
| Saisie manuelle dans Réglages | ✅ | prioritaire, pour un appareil administré à la main |
| Valeurs compilées (`AppConfig`) | ❌ | dernier repli hors-ligne |

Une **URL vide** n'est pas une erreur : elle signifie « ce club synchronise
tout vers PostgreSQL, sans Google Sheets ». L'application le traite comme un
succès (`ClubConfigOutcome.appliedWithoutSheets`).

### 1.0.1 Authentification : deux chemins, un seul obligatoire

| Chemin | En-tête / champ | Quand | Obligatoire ? |
|---|---|---|---|
| **Session Google** | `Authorization: Bearer <jwt>` (+ `X-DTNH-Auth` en natif) | utilisateur connecté | non, mais c'est le mode nominal |
| **Secret partagé** | `secret` dans le corps | appareil non connecté, hors-ligne, secours | non |

Une requête est acceptée si **l'un des deux** est valide. C'est le correctif
central : auparavant le secret était exigé *en plus*, si bien qu'un membre
simplement connecté restait bloqué en « synchronisation non configurée ».

Conséquence directe : `AppSettings.hasSyncTarget` ne teste plus que la présence
d'une **URL**. La présence d'un secret est exposée séparément
(`isSecretMissing`), mais ne bloque plus jamais un envoi.

### 1.1 Déclencheurs de synchronisation

La synchronisation ne dépend jamais d'une action manuelle du staff : quatre
déclencheurs se complètent (implémentation : `SyncScheduler`).

| Déclencheur | Moment | Rôle |
|---|---|---|
| Après une écriture | chaque saisie (pointage, paiement, joueur) | envoi rapide, regroupé par une temporisation courte (anti-rebond) |
| Retour en ligne | transition hors-ligne → ligne | vide la file accumulée pendant la coupure réseau |
| Reprise de l'application | l'app revient au premier plan | rattrape ce qui a été saisi pendant que l'app était en arrière-plan |
| Filet de sécurité périodique | toutes les quelques minutes | garantit qu'aucune donnée ne reste bloquée par un déclenchement manqué |

Les déclencheurs sont **coalescés** : si un envoi est déjà en cours, une
nouvelle demande n'ouvre pas un second envoi concurrent, elle est fusionnée
avec le suivant. Un seul envoi peut donc traiter plusieurs saisies.

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

### 4.3 Payload `player` (roster)

Depuis la v1.2, le roster se synchronise aussi (`entity: "player"`), avec la
date de naissance qui sert à la catégorisation par âge :

```json
{
  "id": "<uuid entité>",
  "nom": "Rasoa Miora",
  "categorie": "U14-U15",
  "dateNaissance": "2012-04-17",
  "numero": 7,
  "telephone": "0340000000",
  "actif": true,
  "updatedAt": "2026-11-05T09:12:03.412Z"
}
```

- `dateNaissance` est au format `yyyy-MM-dd` (jour local, sans fuseau) et vaut
  `null` si le staff n'a pas saisi la date : le serveur écrit alors `NULL` en
  base (`birth_date`), il n'invente **jamais** de date.
- Une date partielle ou mal formée est **rejetée** côté serveur (item en
  `error`) plutôt que devinée : une date de naissance fausse fausserait la
  catégorie d'âge du joueur.
- Les téléphones portant encore un schéma Hive **v1** (sans date de naissance)
  continuent d'envoyer des lots valides : la migration locale v1 → v2 remplit le
  champ à `null` sans perte de données (voir `PlayerAdapter`).

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
| **Webhook changé / secret tourné** | `update dtnh_club_config set sheets_webhook_url = …` (aucun redéploiement) ; les membres connectés reçoivent la nouvelle valeur au prochain passage. Items en `ERROR` réessayables sans perte. |
| **Membre simplement connecté, aucun secret saisi** | Cas nominal : le JWT authentifie l'envoi. Avant correctif, cet état était (à tort) traité comme « non configuré ». |
| **Configuration pas encore reçue (1er lancement hors-ligne)** | Repli sur les valeurs locales/compilées ; la récupération est retentée à la reprise de l'app et à chaque tentative de synchronisation (anti-rebond 60 s). |
| **Fuseau horaire** | Dates métier au format `yyyy-MM-dd` (jour local) ; horodatages techniques en ISO UTC. |

## 7. Sécurité

- **Aucune clé de service dans l'APK.** Le téléphone ne détient qu'une URL
  publique et, éventuellement, un secret révocable.
- **L'authentification nominale est la session Google** : le JWT est vérifié
  par Supabase (`/auth/v1/user`) côté Edge Function, et par Google
  (`oauth2.googleapis.com/tokeninfo`) côté Apps Script. Aucun de ces deux
  serveurs ne fait confiance à une identité déclarée par le client.
- Le secret Sheets vit dans les `Script Properties` du Sheet et, côté serveur,
  dans `dtnh_club_config` (RLS **sans policy** : seule la clé de service y
  accède) ou dans les secrets de fonction. Il n'est **jamais** dans le bundle
  public : il n'est renvoyé qu'à une requête authentifiée, via `action: config`.
- Toutes les requêtes passent en **HTTPS** (Apps Script l'impose, Supabase
  aussi).
- Côté Apps Script, une liste d'accès optionnelle (`ALLOWED_EMAILS`, séparée par
  des virgules) restreint les comptes Google acceptés. Sans elle, tout compte
  Google vérifié est accepté — utile pour un déploiement interne.
- Les jetons Google déjà vérifiés sont mis en cache 600 s (`CacheService`),
  ce qui évite un appel `tokeninfo` par requête sans affaiblir la vérification.
- Le client n'émet **jamais** de requête vers un domaine autre que celui de
  l'URL résolue (saisie locale, configuration du club, ou valeur compilée).
- Rotation : mettre à jour `SHARED_SECRET` dans les `Script Properties` du
  Sheet et `dtnh_club_config.sheets_webhook_secret` (ou le secret de fonction
  correspondant). Les membres connectés n'ont rien à faire : ils reçoivent la
  nouvelle valeur au prochain `action: config`. Les appareils non connectés
  doivent ressaisir le secret.

> ⚠️ Limite assumée : le secret est stocké dans la box Hive `settings_v1`
> (non chiffrée). Pour un durcissement, remplacer `SettingsRepositoryImpl` par
> une implémentation `flutter_secure_storage` — l'interface `SettingsRepository`
> est déjà abstraite, aucun autre fichier ne change.
>
> La configuration reçue du club est **effacée à la déconnexion**
> (`forgetClubConfig()`), pour qu'un appareil partagé ne conserve pas un secret
> distribué à un compte autorisé. Les valeurs saisies à la main, elles, sont
> conservées : elles appartiennent à l'appareil, pas au compte.

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
# 0. Edge Function Supabase : ping + configuration distribuée
curl -s -X POST "https://osjsczvsnyknkdwbciab.supabase.co/functions/v1/dtnh-sync" \
  -H "Content-Type: application/json" \
  -d '{"action":"ping","secret":"<DTNH_SHARED_SECRET>"}'

curl -s -X POST "https://osjsczvsnyknkdwbciab.supabase.co/functions/v1/dtnh-sync" \
  -H "Content-Type: application/json" \
  -d '{"action":"config","secret":"<DTNH_SHARED_SECRET>"}'
# → {"ok":true,"sheets":{"webhookUrl":"…/exec","webhookSecret":"…","sheetId":"…"}}

# Avec une session Google (chemin nominal, aucun secret requis) :
curl -s -X POST "https://osjsczvsnyknkdwbciab.supabase.co/functions/v1/dtnh-sync" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <access_token>" \
  -d '{"action":"config"}'

# 1. Test de vie (Apps Script)
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
