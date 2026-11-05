# Modèles de données — DTNH Assistant Club

Deux perspectives complémentaires :

1. **Persisté (Hive)** : ce qui existe réellement sur le téléphone.
2. **Relationnel (SQLite/Drift)** : le schéma équivalent en DDL, pour ceux qui
   préfèrent SQL ou qui veulent migrer sans changer le domaine.

Le contrat public est le même dans les deux cas : les **entités du domaine**
(`app/lib/domain/entities/`).

---

## 1. Vue d'ensemble

```
              ┌──────────────────┐
              │      Player      │  roster local
              │ id, name, cat…   │
              └────────┬─────────┘
                       │ playerId (dénormalisé : playerName)
                       ▼
   ┌─────────────────────────────┐        ┌──────────────────────────────┐
   │     AttendanceEntry         │        │   FinancialTransaction       │
   │ id, sessionId, sessionDate  │        │ id, date, flow, category     │
   │ category, playerId/Name     │        │ amount, paymentMethod        │
   │ status, author, recordedAt   │        │ player/staff/event, period   │
   └──────────────┬──────────────┘        └───────────────┬──────────────┘
                  │ entityId                              │ entityId
                  └───────────────┬───────────────────────┘
                                  ▼
                    ┌──────────────────────────┐
                    │      SyncQueueItem       │  outbox
                    │ id, entityType, entityId │
                    │ payload, status, attempts│
                    └──────────────────────────┘
```

Invariants :

| Invariant | Portée | Vérifié où |
|---|---|---|
| `(sessionId, playerId)` unique | Présences | `AttendanceRepositoryImpl.saveSession` (upsert par `playerId` sur la séance) |
| `id` immuable et unique (UUID v4) | Toutes les entités | Génération à la création, jamais modifié |
| `amount > 0` (le sens est porté par `flow`) | Transactions | `TransactionFormController.validate()` |
| Un seul item `PENDING` par entité | File | `SyncQueueDao.findPendingFor` (coalescence) |
| `status = SYNCED` ⇒ entité `syncState = synced` | Cohérence UI | `SyncQueueDao.applySyncedState` |

---

## 2. Hive : boxes, typeIds, sérialisation

### 2.1 Boxes

| Box Hive | Type | Clé | Contenu |
|---|---|---|---|
| `attendance_entries_v1` | `Box<AttendanceEntry>` | `entry.id` | Une ligne par joueur et par séance |
| `financial_transactions_v1` | `Box<FinancialTransaction>` | `tx.id` | Entrées et sorties d'argent |
| `players_v1` | `Box<Player>` | `player.id` | Roster (actifs + archivés) |
| `sync_queue_v1` | `Box<SyncQueueItem>` | `item.id` | Outbox de synchronisation |
| `settings_v1` | `Box<dynamic>` | clés plates | Webhook, auteur, préférences |

### 2.2 TypeIds (`data/local/hive_type_ids.dart`)

| TypeId | Classe | Adapter |
|---|---|---|
| `1` | `AttendanceEntry` | `AttendanceEntryAdapter` |
| `2` | `FinancialTransaction` | `FinancialTransactionAdapter` |
| `3` | `SyncQueueItem` | `SyncQueueItemAdapter` |
| `4` | `Player` | `PlayerAdapter` |

> ⚠️ Un TypeId ne doit **jamais** être réutilisé ni réordonné : les téléphones du
> staff contiennent déjà des données binaires indexées par ces identifiants.

### 2.3 Format binaire d'un enregistrement

Les adapters sont écrits à la main (pas de `build_runner`, donc pas de `.g.dart`
à committer et un projet qui compile dès le clone). Chaque enregistrement
commence par un octet de version :

```
[version:1][champ1][champ2]…[champN]
```

Règles de compatibilité :

- **Ajout de champ** → incrémenter `kAdapterVersion`, écrire le nouveau champ en
  fin, et gérer en lecture `case 1:` (ancien format) et `case 2:` (nouveau).
- **Changement de type** → nouvelle version obligatoire.
- **Enums** → stockés par **code string** (`'U16'`, `'PRESENT'`, `'IN'`,
  `'SYNCED'`) et non par index : réordonner un enum ne casse pas les données.
- **Dates** → `millisecondsSinceEpoch` (`int`), donc insensibles au fuseau.
- **Champs nullables** → `bool isPresent` + valeur (aucun sentinelle ambigu).
- **Payload de la file** → `jsonEncode(Map)` dans une `String` : Hive ne sait pas
  sérialiser proprement des maps imbriquées, et la chaîne garantit que le JSON
  envoyé est exactement celui généré au moment de la saisie.

### 2.4 Ordre de sérialisation (contrat des adapters)

**AttendanceEntry** (15 champs) :

```
1 id                     9  status
2 sessionId              10 authorId
3 sessionDate            11 authorName
4 recordedAt             12 note (nullable)
5 category               13 syncState
6 playerId               14 syncedAt (nullable)
7 playerName             15 updatedAt
8 jerseyNumber (nullable)
```

**FinancialTransaction** (17 champs) :

```
1  id                    10 periodMonth (nullable)
2  date                  11 authorId
3  flow                  12 authorName
4  category              13 createdAt
5  amount                14 updatedAt
6  paymentMethod         15 syncState
7  details (nullable)    16 syncedAt (nullable)
8  playerName (nullable)
9  staffName (nullable)
```
`eventName` s'intercale entre `staffName` et `periodMonth` (soit 18 champs au
total dans l'ordre exact implémenté : `id, date, flow, category, amount,
paymentMethod, details, playerName, staffName, eventName, periodMonth, authorId,
authorName, createdAt, updatedAt, syncState, syncedAt`).

**SyncQueueItem** (12 champs) :

```
id, entityType, entityId, operation, payloadJson, status,
attempts, lastError(nullable), createdAt, updatedAt, syncedAt(nullable),
batchId(nullable)
```

**Player** (10 champs) :

```
id, fullName, category, jerseyNumber(nullable), phone(nullable),
isActive, createdAt, updatedAt, syncState, syncedAt(nullable)
```

---

## 3. Champs détaillés des entités

### 3.1 `AttendanceEntry` — une ligne de présence

| Champ | Type | Obligatoire | Description |
|---|---|---|---|
| `id` | `String` (UUID v4) | ✅ | Clé primaire locale **et** clé d'idempotence du Sheet |
| `sessionId` | `String` | ✅ | Regroupe les lignes saisies lors du même pointage |
| `sessionDate` | `DateTime` (minuit local) | ✅ | Date de la séance |
| `recordedAt` | `DateTime` | ✅ | Horodatage exact du pointage (date + heure) |
| `category` | `TeamCategory` | ✅ | `U12`, `U14-U15`, `U16`, `U17-U18` |
| `playerId` | `String` | ✅ | Référence joueur (peut être orphelin après archivage) |
| `playerName` | `String` | ✅ | Dénormalisé : lisibilité du Sheet + historique résilient |
| `jerseyNumber` | `int?` | — | Numéro au moment du pointage |
| `status` | `AttendanceStatus` | ✅ | `PRESENT`, `ABSENT`, `LATE`, `EXCUSED` |
| `authorId` | `String` | ✅ | Auteur du pointage (traçabilité) |
| `authorName` | `String` | ✅ | Nom affiché dans la colonne `Auteur` |
| `note` | `String?` | — | Motif libre (blessure, convocation…) |
| `syncState` | `SyncState` | ✅ | Copie dénormalisée pour l'UI |
| `syncedAt` | `DateTime?` | — | Horodatage serveur du dernier envoi réussi |
| `updatedAt` | `DateTime` | ✅ | Dernière modification locale |

Clé logique de séance : `sessionKey = "<yyyy-MM-dd>#<code>"` → `2026-11-05#U16`.

### 3.2 `FinancialTransaction` — un mouvement d'argent

| Champ | Type | Obligatoire | Description |
|---|---|---|---|
| `id` | `String` (UUID v4) | ✅ | Clé primaire + idempotence |
| `date` | `DateTime` | ✅ | Date effective de l'opération |
| `flow` | `TransactionFlow` | ✅ | `IN` (entrée) / `OUT` (sortie) |
| `category` | `TransactionCategory` | ✅ | Motif (voir 3.4) |
| `amount` | `int` (Ariary) | ✅ | Toujours positif, stocké en entier |
| `paymentMethod` | `PaymentMethod` | ✅ | Espèces, MVola, Orange Money, Airtel Money, virement, chèque |
| `details` | `String?` | — | Remarque libre |
| `playerName` | `String?` | — | Joueur concerné (écolage, cotisation) |
| `staffName` | `String?` | — | Coach concerné (salaire, indemnité) |
| `eventName` | `String?` | — | Événement (billetterie, rafraîchissements) |
| `periodMonth` | `String?` | — | Mois concerné `yyyy-MM` (écolage, salaire) |
| `authorId` / `authorName` | `String` | ✅ | Auteur de la saisie |
| `createdAt` / `updatedAt` | `DateTime` | ✅ | Traçabilité |
| `syncState` / `syncedAt` | `SyncState` / `DateTime?` | ✅ / — | État d'envoi |

**Pourquoi un `int` et pas un `double`** : l'ariary n'a pas de sous-unité en
usage courant. Un entier élimine tout risque d'erreur d'arrondi flottant dans les
cumuls (solde du club) et simplifie le Sheet, qui affiche des montants exacts.

### 3.3 `SyncQueueItem` — l'outbox

| Champ | Type | Rôle |
|---|---|---|
| `id` | `String` | Identifiant de l'item de file |
| `entityType` | `SyncEntityType` | `attendance` / `transaction` / `player` → onglet cible |
| `entityId` | `String` | Clé de coalescence (une entité = un item PENDING max) |
| `operation` | `SyncOperation` | `upsert` ou `delete` |
| `payload` | `Map<String, dynamic>` | JSON prêt à envoyer (clés nommées, jamais positionnelles) |
| `status` | `SyncState` | `pending` → `synced` / `error` |
| `attempts` | `int` | Nombre de tentatives (plafond 8) |
| `lastError` | `String?` | Message lisible (tronqué à 400 caractères) |
| `createdAt` / `updatedAt` | `DateTime` | Ordre d'envoi (FIFO) |
| `syncedAt` | `DateTime?` | Horodatage serveur |
| `batchId` | `String?` | Traçabilité du lot envoyé |

### 3.4 Motifs financiers (`TransactionCategory`)

| Code | Libellé | Flux | Champs spécifiques |
|---|---|---|---|
| `ECOLAGE` | Écolage | Entrée | joueur + mois |
| `COTISATION` | Cotisation exceptionnelle | Entrée | — (joueur facultatif) |
| `BILLETTERIE` | Vente de billets | Entrée | événement |
| `AUTRE_ENTREE` | Autre entrée | Entrée | — |
| `LOCATION_TERRAIN` | Location de terrain | Sortie | — |
| `SALAIRE_COACH` | Salaire / indemnité coach | Sortie | staff + mois |
| `RAFRAICHISSEMENT` | Rafraîchissements | Sortie | événement |
| `AUTRE_SORTIE` | Autre sortie | Sortie | — |

Ces drapeaux (`requiresPlayer`, `requiresPeriod`, `requiresStaff`,
`requiresEvent`) **pilotent dynamiquement le formulaire** : un seul écran de
saisie, six variantes sans duplication de code.

### 3.5 `AppSettings` — configuration locale

| Clé Hive | Type | Défaut | Description |
|---|---|---|---|
| `webhook_url` | `String` | `''` | URL `/exec` du déploiement Apps Script |
| `webhook_secret` | `String` | `''` | Secret partagé avec `SHARED_SECRET` |
| `device_id` | `String` | UUID généré | Identifiant anonyme de l'appareil (journal serveur) |
| `author_name` / `author_id` | `String?` | `null` | Auteur du pointage en cours |
| `auto_sync` | `bool` | `true` | Synchronisation automatique au retour réseau |
| `last_sync_at` | `String ISO?` | `null` | Dernier envoi réussi |
| `last_sync_error` | `String?` | `null` | Dernier message d'erreur |
| `sheet_id` | `String?` | `null` | ID du Sheet (informatif) |

---

## 4. Schéma SQLite/Drift équivalent (option de migration)

Si le club préfère SQL (reporting, jointures, exports), voici le DDL strictement
équivalent. Les repositories exposent déjà des contrats abstraits : seuls les DAO
changent.

```sql
-- =====================================================================
--  Joueurs (roster local)
-- =====================================================================
CREATE TABLE players (
  id             TEXT    PRIMARY KEY,
  full_name      TEXT    NOT NULL,
  category       TEXT    NOT NULL CHECK (category IN ('U12','U14-U15','U16','U17-U18')),
  jersey_number  INTEGER,
  phone          TEXT,
  is_active      INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at     INTEGER NOT NULL,           -- ms epoch
  updated_at     INTEGER NOT NULL,
  sync_state     TEXT    NOT NULL DEFAULT 'pending'
                         CHECK (sync_state IN ('pending','synced','error')),
  synced_at      INTEGER
);
CREATE INDEX idx_players_category ON players(category, is_active);

-- =====================================================================
--  Présences : 1 ligne = 1 joueur pour 1 séance
-- =====================================================================
CREATE TABLE attendance_entries (
  id             TEXT    PRIMARY KEY,
  session_id     TEXT    NOT NULL,
  session_date   TEXT    NOT NULL,           -- 'yyyy-MM-dd' (tri lexicographique)
  recorded_at    INTEGER NOT NULL,           -- ms epoch (heure exacte)
  category       TEXT    NOT NULL,
  player_id      TEXT    NOT NULL,
  player_name    TEXT    NOT NULL,           -- dénormalisé volontairement
  jersey_number  INTEGER,
  status         TEXT    NOT NULL CHECK (status IN ('PRESENT','ABSENT','LATE','EXCUSED')),
  author_id      TEXT    NOT NULL,
  author_name    TEXT    NOT NULL,
  note           TEXT,
  sync_state     TEXT    NOT NULL DEFAULT 'pending',
  synced_at      INTEGER,
  updated_at     INTEGER NOT NULL,
  UNIQUE (session_id, player_id)             -- idempotence du pointage
);
CREATE INDEX idx_attendance_session  ON attendance_entries(session_date DESC, category);
CREATE INDEX idx_attendance_player   ON attendance_entries(player_id, session_date DESC);
CREATE INDEX idx_attendance_category ON attendance_entries(category, session_date DESC);

-- =====================================================================
--  Transactions financières
-- =====================================================================
CREATE TABLE financial_transactions (
  id              TEXT    PRIMARY KEY,
  date            TEXT    NOT NULL,          -- 'yyyy-MM-dd'
  flow            TEXT    NOT NULL CHECK (flow IN ('IN','OUT')),
  category        TEXT    NOT NULL,
  amount          INTEGER NOT NULL CHECK (amount > 0),  -- Ariary, jamais de float
  payment_method  TEXT    NOT NULL,
  details         TEXT,
  player_name     TEXT,
  staff_name      TEXT,
  event_name      TEXT,
  period_month    TEXT,                      -- 'yyyy-MM'
  author_id       TEXT    NOT NULL,
  author_name     TEXT    NOT NULL,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  sync_state      TEXT    NOT NULL DEFAULT 'pending',
  synced_at       INTEGER
);
CREATE INDEX idx_tx_date     ON financial_transactions(date DESC);
CREATE INDEX idx_tx_month    ON financial_transactions(substr(date,1,7), flow);
CREATE INDEX idx_tx_category ON financial_transactions(category);

-- =====================================================================
--  File d'attente de synchronisation (outbox)
-- =====================================================================
CREATE TABLE sync_queue (
  id           TEXT    PRIMARY KEY,
  entity_type  TEXT    NOT NULL CHECK (entity_type IN ('attendance','transaction','player')),
  entity_id    TEXT    NOT NULL,
  operation    TEXT    NOT NULL DEFAULT 'upsert' CHECK (operation IN ('upsert','delete')),
  payload      TEXT    NOT NULL,             -- JSON
  status       TEXT    NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','synced','error')),
  attempts     INTEGER NOT NULL DEFAULT 0,
  last_error   TEXT,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL,
  synced_at    INTEGER,
  batch_id     TEXT
);
-- Un seul item PENDING par entité (coalescence) :
CREATE UNIQUE INDEX idx_queue_pending_unique
  ON sync_queue(entity_type, entity_id)
  WHERE status = 'pending';
CREATE INDEX idx_queue_sendable ON sync_queue(status, created_at)
  WHERE status <> 'synced';

-- =====================================================================
--  Réglages (clé/valeur)
-- =====================================================================
CREATE TABLE app_settings (
  key   TEXT PRIMARY KEY,
  value TEXT
);
```

### Requêtes équivalentes aux agrégats de l'app

```sql
-- Taux de présence par joueur (catégorie U16)
SELECT player_id,
       player_name,
       SUM(status IN ('PRESENT','LATE'))                AS attended,
       COUNT(*)                                          AS total,
       ROUND(100.0 * SUM(status IN ('PRESENT','LATE')) / COUNT(*), 0) AS rate
FROM attendance_entries
WHERE category = 'U16'
GROUP BY player_id
ORDER BY rate DESC;

-- Solde du club
SELECT COALESCE(SUM(CASE WHEN flow='IN' THEN amount ELSE -amount END), 0) AS balance
FROM financial_transactions;

-- Synthèse mensuelle (6 derniers mois)
SELECT substr(date,1,7) AS month,
       SUM(CASE WHEN flow='IN'  THEN amount ELSE 0 END) AS income,
       SUM(CASE WHEN flow='OUT' THEN amount ELSE 0 END) AS expense
FROM financial_transactions
GROUP BY month
ORDER BY month DESC
LIMIT 6;

-- File à envoyer
SELECT * FROM sync_queue
WHERE status <> 'synced' AND attempts < 8
ORDER BY created_at
LIMIT 80;
```

---

## 5. Volumétrie et dimensionnement

| Donnée | Fréquence | Volume / saison | Taille Hive estimée |
|---|---|---|---|
| Présences | 4 catégories × 2 séances/sem × 12 joueurs × 30 sem. | ≈ 2 900 lignes | ≈ 1,5 Mo |
| Transactions | ~8 écolages/mois + 10 dépenses/mois | ≈ 220 lignes | ≈ 120 Ko |
| Joueurs | 40 fiches | 40 lignes | ≈ 10 Ko |
| File d'attente | vidée après envoi (`clearSynced`) | quelques dizaines | < 100 Ko |

Un téléphone Android 8 avec 500 Mo libres héberge **trois saisons** sans purge.
Le bouton « Nettoyer l'historique des envois » évite toute croissance de la file.

---

## 6. Mapping vers Google Sheets

Chaque champ persisté a une colonne cible (contrat : `apps-script/Code.gs` →
`SCHEMAS`). Colonnes **en gras** = imposées par la spécification ; les autres
sont des colonnes de traçabilité ajoutées en fin de tableau.

### Onglet `Présences`

| # | Colonne | Champ source |
|---|---|---|
| 1 | **ID** | `id` |
| 2 | **Date** | `sessionDate` (`yyyy-MM-dd`) |
| 3 | **Catégorie** | `category.code` |
| 4 | **Joueur** | `playerName` |
| 5 | **Statut** | `status.code` |
| 6 | **Auteur** | `authorName` |
| 7 | **SyncTimestamp** | généré par Apps Script (`ISO 8601`) |
| 8 | Heure | `recordedAt.hm` |
| 9 | JoueurID | `playerId` |
| 10 | SessionID | `sessionId` |
| 11 | Numéro | `jerseyNumber` |
| 12 | Note | `note` |

### Onglet `Transactions`

| # | Colonne | Champ source |
|---|---|---|
| 1 | **ID** | `id` |
| 2 | **Date** | `date` |
| 3 | **Flux** | `flow.code` (`IN`/`OUT`) |
| 4 | **Catégorie** | `category.code` |
| 5 | **Montant** | `amount` (entier Ariary) |
| 6 | **Détails** | `details` ou résumé auto |
| 7 | **Auteur** | `authorName` |
| 8 | **SyncTimestamp** | généré par Apps Script |
| 9 | Mode de paiement | `paymentMethod.code` |
| 10 | Joueur | `playerName` |
| 11 | Staff | `staffName` |
| 12 | Événement | `eventName` |
| 13 | Mois | `periodMonth` (`yyyy-MM`) |

### Onglet `Joueurs`

| # | Colonne | Champ source |
|---|---|---|
| 1 | ID | `id` |
| 2 | Nom | `fullName` |
| 3 | Catégorie | `category.code` |
| 4 | Numéro | `jerseyNumber` |
| 5 | Téléphone | `phone` |
| 6 | Actif | `isActive` |
| 7 | SyncTimestamp | généré par Apps Script |
