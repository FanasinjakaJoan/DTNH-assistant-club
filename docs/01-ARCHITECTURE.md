# Architecture — DTNH Assistant Club

> Application mobile Flutter **offline-first** pour le club de basket-ball
> Dream Team New Hope : pointage des présences, gestion des finances et
> synchronisation Google Sheets.

## 1. Principes directeurs

| # | Principe | Traduction concrète |
|---|---|---|
| 1 | **Le téléphone est la source de vérité** | Toute écriture va d'abord dans Hive, puis dans une file d'attente. Le réseau ne bloque jamais une saisie. |
| 2 | **Zéro perte de données** | Une entité + son item de file sont écrits en deux temps ; si l'envoi échoue, l'item reste `PENDING`/`ERROR` avec un compteur de tentatives. |
| 3 | **Idempotence** | Chaque ligne possède un UUID client utilisé comme clé primaire dans le Sheet : rejouer un lot met à jour au lieu de dupliquer. |
| 4 | **Le domaine ne connaît ni Flutter ni Hive** | `domain/` est du Dart pur : testable, réutilisable, insensible au choix de stockage. |
| 5 | **UI optimiste et instantanée** | Le pointage affiche l'état retenu immédiatement ; l'icône « nuage » indique la vérité côté synchronisation. |
| 6 | **Une seule source d'état** | Riverpod. Aucun `setState` métier, aucune vérité dupliquée entre widgets. |

## 2. Style architectural : Feature-first + Clean Architecture

- **Feature-first** pour la navigation humaine : un développeur qui reçoit un
  ticket « bug sur l'écolage » trouve tous les fichiers concernés dans
  `features/finance/`.
- **Clean Architecture** interne : `presentation → application → domain ← data`.
  Le sens des dépendances est **toujours** vers le domaine ; jamais l'inverse.

```
┌──────────────────────────────────────────────────────────────────────┐
│  PRESENTATION (Flutter widgets, écrans, widgets partagés)            │
│  features/*/*_screen.dart, core/widgets/**                            │
└───────────────▲──────────────────────────────────────────────────────┘
                │ ref.watch / ref.read (Riverpod)
┌───────────────┴──────────────────────────────────────────────────────┐
│  APPLICATION (contrôleurs d'état : Notifier)                          │
│  attendance_controller, transaction_form_controller, sync_controller  │
│  features/*/*_controller.dart, features/*/*_state.dart               │
└───────────────▲──────────────────────────────────────────────────────┘
                │ appels de méthodes
┌───────────────┴──────────────────────────────────────────────────────┐
│  DOMAIN (Dart pur : entités, enums, contrats de repositories)        │
│  domain/entities/**  domain/enums/**  domain/repositories/**          │
└───────────────▲──────────────────────────────────────────────────────┘
                │ implémente les interfaces
┌───────────────┴──────────────────────────────────────────────────────┐
│  DATA (Hive, DAO, repositories, client HTTP Apps Script)             │
│  data/local/**  data/repositories/**  data/remote/**                  │
└───────────────▲──────────────────────────────────────────────────────┘
                │
┌───────────────┴──────────────────────────────────────────────────────┐
│  CORE (shared kernel : thème, widgets, utils, erreurs)               │
└──────────────────────────────────────────────────────────────────────┘
```

Règle vérifiable en revue de code : **aucun fichier de `domain/` n'importe
`package:flutter`, `package:hive` ou `package:http`.**

## 3. Arborescence du projet

```
DTNH-assistant-club/
├── app/                                  # Application Flutter
│   ├── pubspec.yaml
│   ├── analysis_options.yaml             # lints stricts (strict-casts, single quotes…)
│   ├── lib/
│   │   ├── main.dart                     # point d'entrée (délègue à bootstrap)
│   │   ├── bootstrap.dart                # init Hive + Workmanager + ProviderScope
│   │   ├── app.dart                      # MaterialApp + garde d'identité
│   │   │
│   │   ├── core/                         # Shared kernel
│   │   │   ├── errors/app_exception.dart # exceptions typées (Validation, Sync…)
│   │   │   ├── theme/
│   │   │   │   ├── app_colors.dart       # palette navy/orange + couleurs sémantiques
│   │   │   │   ├── app_theme.dart        # Material 3, cibles tactiles 48 dp
│   │   │   │   └── status_styles.dart    # mapping statut -> couleur/icône
│   │   │   ├── utils/
│   │   │   │   ├── date_x.dart           # clés de date triables + libellés FR
│   │   │   │   └── money.dart            # formatage/parsing Ariary
│   │   │   └── widgets/
│   │   │       ├── app_card.dart         # AppCard, SectionHeader
│   │   │       ├── common_widgets.dart   # StatusPill, EmptyState, InfoBanner…
│   │   │       ├── category_selector.dart
│   │   │       ├── date_picker_sheet.dart
│   │   │       └── amount_field.dart     # montant + séparateur de milliers
│   │   │
│   │   ├── domain/                       # ❤️ Dart pur
│   │   │   ├── entities/
│   │   │   │   ├── attendance_entry.dart
│   │   │   │   ├── attendance_stats.dart        # agrégats (séance, joueur)
│   │   │   │   ├── financial_transaction.dart
│   │   │   │   ├── finance_summary.dart         # synthèse + série mensuelle
│   │   │   │   ├── sync_queue_item.dart
│   │   │   │   ├── player.dart
│   │   │   │   └── app_settings.dart
│   │   │   ├── enums/
│   │   │   │   ├── team_category.dart    # U12, U14-U15, U16, U17-U18
│   │   │   │   ├── attendance_status.dart# PRESENT / ABSENT / LATE / EXCUSED
│   │   │   │   ├── transaction_enums.dart# flow, motifs, moyens de paiement
│   │   │   │   └── sync_enums.dart       # SyncState, operation, entityType
│   │   │   └── repositories/             # contrats (abstract interface class)
│   │   │       ├── attendance_repository.dart
│   │   │       ├── transaction_repository.dart
│   │   │       ├── player_repository.dart
│   │   │       ├── sync_queue_repository.dart
│   │   │       └── settings_repository.dart
│   │   │
│   │   ├── data/
│   │   │   ├── local/
│   │   │   │   ├── local_database.dart    # ouverture des boxes + flux de changements
│   │   │   │   ├── hive_type_ids.dart     # typeIds & noms de boxes (stables)
│   │   │   │   ├── adapters/              # adapters Hive écrits à la main
│   │   │   │   │   ├── adapter_utils.dart
│   │   │   │   │   ├── attendance_entry_adapter.dart
│   │   │   │   │   ├── financial_transaction_adapter.dart
│   │   │   │   │   ├── sync_queue_item_adapter.dart
│   │   │   │   │   └── player_adapter.dart
│   │   │   │   └── dao/                   # lecture/écriture bas niveau
│   │   │   │       ├── attendance_dao.dart
│   │   │   │       ├── transaction_dao.dart
│   │   │   │       ├── player_dao.dart
│   │   │   │       └── sync_queue_dao.dart
│   │   │   ├── remote/
│   │   │   │   ├── apps_script_client.dart# POST lot, ping, erreurs typées
│   │   │   │   └── sync_payloads.dart     # entité -> JSON nommé (contrat Sheet)
│   │   │   └── repositories/              # implémentations concrètes
│   │   │       ├── attendance_repository_impl.dart
│   │   │       ├── transaction_repository_impl.dart
│   │   │       ├── player_repository_impl.dart
│   │   │       ├── sync_queue_repository_impl.dart
│   │   │       └── settings_repository_impl.dart
│   │   │
│   │   ├── sync/                         # moteur de synchronisation (application)
│   │   │   ├── sync_engine.dart          # outbox -> webhook -> statuts
│   │   │   ├── sync_scheduler.dart       # listener réseau + debounce + backoff
│   │   │   └── background_worker.dart    # Workmanager (isolate séparé)
│   │   │
│   │   ├── di/providers.dart             # graphe d'injection Riverpod
│   │   │
│   │   └── features/                     # Feature-first
│   │       ├── attendance/
│   │       │   ├── attendance_screen.dart
│   │       │   ├── attendance_controller.dart
│   │       │   └── widgets/attendance_widgets.dart
│   │       ├── finance/
│   │       │   ├── finance_screen.dart
│   │       │   ├── finance_state.dart
│   │       │   ├── transactions_screen.dart
│   │       │   ├── new_transaction_sheet.dart
│   │       │   ├── transaction_form_screen.dart
│   │       │   ├── transaction_form_controller.dart
│   │       │   └── widgets/finance_widgets.dart
│   │       ├── history/
│   │       │   ├── history_screen.dart
│   │       │   └── history_state.dart
│   │       ├── sync/
│   │       │   ├── sync_screen.dart
│   │       │   └── sync_controller.dart
│   │       ├── settings/
│   │       │   ├── settings_screen.dart
│   │       │   ├── settings_controller.dart
│   │       │   ├── roster_screen.dart
│   │       │   └── demo_seed.dart
│   │       └── shell/
│   │           ├── home_shell.dart       # navigation 4 onglets
│   │           └── author_screen.dart    # premier lancement (identité)
│   └── test/
│       ├── core/money_test.dart
│       ├── domain/aggregates_test.dart
│       ├── data/local_repository_test.dart
│       └── sync/sync_engine_test.dart
│
├── apps-script/                          # Backend Google Sheets
│   ├── Code.gs                           # doPost / doGet / setup / upsert idempotent
│   ├── appsscript.json                   # manifeste (V8, webapp ANYONE_ANONYMOUS)
│   └── README.md                         # déploiement, contrat d'API, quotas
│
├── docs/
│   ├── 01-ARCHITECTURE.md                # (ce document)
│   ├── 02-DATA-MODEL.md                  # modèles Hive + DDL SQLite équivalent
│   ├── 03-SYNC-PROTOCOL.md               # protocole, états, cas limites
│   ├── 04-UX-GUIDELINES.md               # design system & parcours
│   └── mockups/index.html                # maquettes HTML navigables
└── README.md
```

## 4. Cycle de vie d'une écriture (exemple : pointage U16)

```
Coach tape « Présent » sur Rakotobe
        │
        ▼
AttendanceDraftController.setStatus()          (application)
        │  state = statuses + {p1: present}
        ▼
Coach tape « Enregistrer »
        │
        ▼
AttendanceRepositoryImpl.saveSession()          (data)
        ├─► AttendanceDao.putAll(...)           → Hive box attendance_entries_v1
        ├─► LocalDatabase.notify(DbStore.attendance)
        │       └─► Stream re-diffusé → UI à jour (icône PENDING)
        └─► SyncQueueRepository.enqueue(...)
                ├─ SyncQueueDao.findPendingFor()  → coalescence
                ├─ SyncQueueDao.put(item PENDING)
                └─ applyPendingState()            → entité.syncState = pending
        │
        ▼
SyncController.syncNow() (ou retour réseau)     (application)
        │
        ▼
SyncEngine.pushPending()                        (sync)
        ├─ lit SettingsRepository (URL + secret)
        ├─ pendingBatch(limit: 80)
        ├─ AppsScriptClient.sendBatch()  ──HTTPS──► Apps Script doPost
        │                                          upsert par ID dans le Sheet
        ├─ résultat par item : ok → SYNCED / error → ERROR
        └─ applySyncedState() → entité.syncedAt + icône verte dans l'UI
```

Points clés :

- **Aucun `await` réseau dans le chemin de l'UI** : `save()` rend la main dès
  l'écriture locale. La synchronisation est un effet de bord déclenché ensuite.
- **L'UI ne lit jamais la file directement** pour savoir si une donnée est
  envoyée : elle lit `entity.syncState`, dénormalisé par le moteur (évite une
  jointure en mémoire à chaque ligne affichée).

## 5. Gestion d'état (Riverpod)

| Provider | Type | Rôle |
|---|---|---|
| `localDatabaseProvider` | `Provider` (overridé au boot) | Point d'entrée Hive |
| `*RepositoryProvider` | `Provider` | Injecte les implémentations (substituables en test) |
| `attendanceEntriesProvider` | `StreamProvider` | Flux local des présences |
| `transactionsProvider` | `StreamProvider` | Flux local des transactions |
| `playersStreamProvider` | `StreamProvider` | Roster (réactif aux ajouts) |
| `syncQueueItemsProvider` | `StreamProvider` | File d'attente (badges) |
| `syncCountersProvider` | `Provider` (dérivé) | Compteurs pending/error/synced |
| `totalSummaryProvider`, `currentMonthSummaryProvider`, `monthlySeriesProvider` | `Provider` | Agrégats financiers calculés en mémoire |
| `attendanceDraftProvider` | `NotifierProvider` | Brouillon de pointage (catégorie, date, statuts) |
| `transactionFormProvider(category)` | `NotifierProvider.family` | Formulaire dédié par motif |
| `syncControllerProvider` | `NotifierProvider` | Orchestrateur réseau + actions manuelles |
| `settingsProvider` | `NotifierProvider` | Config persistée (webhook, auteur) |

Pourquoi **Riverpod** plutôt que Bloc : les flux dérivés (compteurs, synthèses
financières, stats par joueur) s'expriment en une ligne avec `Provider`, alors
qu'un Bloc par agrégat imposerait des `emit` manuels et davantage de boilerplate.
Riverpod permet aussi l'injection sans `BuildContext`, ce qui rend le moteur de
synchronisation testable sans widget tree.

## 6. Choix du stockage local : Hive (et pourquoi pas Drift/Isar)

| Critère | Hive (retenu) | Drift / SQLite | Isar |
|---|---|---|---|
| Génération de code | **Aucune** (adapters à la main) | `build_runner` obligatoire | `build_runner` obligatoire |
| Vitesse d'écriture | Très rapide (< 1 ms) | Rapide (WAL) | Très rapide |
| Requêtes relationnelles | Non (agrégation Dart) | **Oui (SQL)** | Non (index) |
| Poids / binaire | Léger, pur Dart | Plugin natif SQLite | Binaire lourd |
| Risque de build cassé | Faible | Moyen (versions de générateur) | Moyen |
| Historique / audit SQL | Non | **Oui** | Non |

**Décision** : Hive, parce que la volumétrie réelle du club est faible
(4 catégories × ~10-15 joueurs × 2 séances/semaine ≈ **1 500 lignes de présence
par saison**, ~500 transactions) et que l'agrégation en mémoire reste sous la
milliseconde. En contrepartie, les adapters sont écrits à la main et versionnés
(voir `docs/02-DATA-MODEL.md`).

**Seuil de migration** : si le club dépasse ~50 000 lignes de présence
(multi-saisons, plusieurs équipes) ou si un besoin d'export/reporting SQL
apparaît, `Drift` prend le relais **sans toucher au domaine** : seuls les DAO et
les adapters changent, car les repositories exposent des contrats abstraits.

## 7. Gestion des erreurs

```
Core exceptions (core/errors/app_exception.dart)
├── ValidationException        → formulaire : message sous le champ
├── SyncConfigurationException → écran Synchro : « webhook non configuré »
├── SyncOfflineException       → bandeau « hors-ligne », aucune tentative perdue
├── SyncTransportException     → HTTP 4xx/5xx, JSON invalide (retryable ou non)
└── StorageException           → écran de secours au boot
```

Les contrôleurs ne laissent jamais fuiter d'exception non typée vers l'UI :
chaque `catch` produit un `state.error` en français, prêt à afficher.

## 8. Performance et limites assumées

- Les listes utilisent `ListView.builder` (listes de mouvements) ou des colonnes
  bornées (≤ 40 séances récentes).
- Les agrégats (`FinanceSummary`, `playerStats`) sont recalculés sur changement
  du flux. À 500 transactions, le coût est négligeable (< 2 ms). Au-delà de
  5 000, un cache par mois + invalidation ciblée est prévu.
- Le moteur de synchronisation envoie **80 items par lot** : un pointage complet
  de 15 joueurs = 1 requête. Une journée de tournoi (4 catégories) = 4 requêtes.
- Aucune image, aucune police custom : APK léger, démarrage à froid < 2 s sur un
  téléphone d'entrée de gamme.

## 9. Tests

| Niveau | Fichier | Ce qui est garanti |
|---|---|---|
| Unitaire pur | `test/core/money_test.dart` | Formatage Ariary, parsing, clés de date |
| Unitaire domaine | `test/domain/aggregates_test.dart` | Taux de présence, soldes, enums tolérants |
| Intégration stockage | `test/data/local_repository_test.dart` | Écriture Hive réelle, idempotence, coalescence, tombstones |
| Intégration sync | `test/sync/sync_engine_test.dart` | Lots, succès partiel, panne réseau, retry |

Les tests d'intégration ouvrent Hive dans un dossier temporaire
(`LocalDatabase.open(directory: ...)`) : pas de mock de la base, on teste le
vrai code de sérialisation.

## 10. Roadmap technique

1. **v1.1** — Édition d'une transaction existante (formulaire prérempli) + export CSV.
2. **v1.2** — Pull du Sheet vers l'app (récupération du roster saisi par le
   secrétariat), via un `action: 'pull'` sur le webhook.
3. **v1.3** — Notifications locales (rappel de pointage, relance des écolages
   impayés), `flutter_local_notifications`.
4. **v2.0** — Multi-saison + migration Drift si volumétrie > 50 000 lignes.
