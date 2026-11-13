# 🏀 DTNH Assistant Club

Application mobile **offline-first** pour l'assistant intelligent officiel du club
de basket-ball **Dream Team New Hope (DTNH)** — destinée au staff, aux coachs et
aux administrateurs.

> **Le principe** : au bord du terrain, il n'y a pas de réseau. Le pointage et la
> caisse doivent fonctionner **immédiatement**, sans spinner, sans perte. La
> synchronisation (Supabase ou Google Sheets) est un effet de bord, jamais un
> prérequis.

| Présences | Finances | Historique | Synchronisation |
|---|---|---|---|
| Pointage par catégorie (U12, U14-U15, U16, U17-U18), 4 statuts, 1 tap | Écolages, cotisations, billetterie, terrain, coachs, rafraîchissements | Séances et taux de présence par joueur | File d'attente transparente, retry, succès partiel |

Maquettes visuelles navigables : [`docs/mockups/index.html`](docs/mockups/index.html).

---

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Démarrage rapide](#démarrage-rapide)
- [Build, prévisualisation & déploiement (DevOps)](#build-prévisualisation--déploiement-devops)
- [Synchronisation (Supabase / Google Sheets)](#synchronisation-supabase--google-sheets)
- [Architecture](#architecture)
- [Modèles de données](#modèles-de-données)
- [Moteur de synchronisation](#moteur-de-synchronisation)
- [Tests](#tests)
- [Structure du dépôt](#structure-du-dépôt)
- [Choix techniques](#choix-techniques)
- [Limites connues & roadmap](#limites-connues--roadmap)

---

## Fonctionnalités

### A. Gestion des présences (offline-first)

- Sélection rapide de la catégorie : **U12**, **U14-U15**, **U16**, **U17-U18**.
- Pointage par joueur avec 4 statuts : **Présent**, **Absent**, **En retard**, **Excusé**.
- Enregistrement de la **date**, de l'**heure**, de l'**auteur** et de la **catégorie**.
- Raccourcis terrain : « Tout présent », réinitialisation, 7 derniers jours, calendrier.
- Historique local par catégorie, par séance et **par joueur** (taux de présence,
  retards, absences, excuses).
- Reprise d'un pointage existant : re-pointer la même séance **met à jour** les
  lignes (aucun doublon dans le Sheet).

### B. Gestion des transactions financières (offline-first)

- **Entrées** : Écolage (joueur + mois), Cotisation exceptionnelle, Vente de billets, Autre.
- **Sorties** : Location de terrain, Salaire/indemnité coach, Rafraîchissements, Autre.
- Champs requis : date, flux, motif, montant, mode de paiement, remarque, auteur.
- Modes de paiement locaux : **Espèces, MVola, Orange Money, Airtel Money**,
  virement, chèque.
- **Dashboard local** : solde, entrées/sorties du mois, évolution 6 mois,
  répartition par motif, derniers mouvements.
- Montants en **Ariary entiers** (aucun flottant, donc aucun arrondi faux).

### C. Moteur de synchronisation (Supabase ou Google Sheets)

- Écriture locale immédiate (Hive), puis **file d'attente** `PENDING` / `SYNCED` / `ERROR`.
- Synchronisation **automatique** au retour du réseau (`connectivity_plus` +
  debounce), **périodique** (Workmanager, 15 min) et **manuelle**.
- Envoi par **lot JSON** vers la cible choisie : **Edge Function Supabase**
  (PostgreSQL, par défaut) ou **webhook Google Apps Script** (Sheet). Même
  contrat, **upsert idempotent** par ID et **résultat par ligne**. Aucune clé
  OAuth ni clé Supabase n'est embarquée : seul un secret partagé est présenté.
- Écran Synchro : compteurs, file détaillée, messages d'erreur, réessai individuel
  ou global.

---

## Démarrage rapide

Prérequis : **Flutter ≥ 3.44 / Dart ≥ 3.12** (voir [`docs/05-DEVOPS.md`](docs/05-DEVOPS.md)).

```bash
bash scripts/doctor.sh     # vérifie Flutter/Dart + flutter doctor
cd app && flutter pub get
flutter run                # Android / iOS (appareil ou émulateur)
```

Les dossiers `app/android/` et `app/web/` sont **versionnés et configurés**
(permissions réseau, splash et icône DTNH, PWA). Aucune génération manuelle
n'est requise pour Android et le Web.

- **Android** — permissions `INTERNET` / `ACCESS_NETWORK_STATE` déjà en place
  dans `android/app/src/main/AndroidManifest.xml`.
- **iOS** — non versionné (dépend de macOS/Xcode). Générer avec
  `bash scripts/setup_platforms.sh`, puis activer la capability *Background
  Modes → Background fetch* dans Xcode (nécessaire à Workmanager ; l'app reste
  pleinement fonctionnelle sans, seule la sync en arrière-plan est désactivée).

Au premier lancement :

1. saisir votre nom (auteur du pointage) — option « pré-remplir l'effectif de
   démonstration » (40 joueurs répartis dans les 4 catégories) ;
2. l'application est **immédiatement utilisable hors-ligne** ;
3. la synchronisation Supabase est déjà pré-configurée (`AppConfig`) : rien à
   saisir. Pour utiliser Google Sheets à la place, suivre la section suivante.

```bash
flutter test          # 4 fichiers de tests (unitaires, intégration Hive, sync)
flutter analyze       # lints stricts (strict-casts, strict-raw-types)
```

Aucune génération de code (`build_runner`) n'est nécessaire : les adapters Hive
sont écrits à la main.

---

## Build, prévisualisation & déploiement (DevOps)

Guide complet : **[`docs/05-DEVOPS.md`](docs/05-DEVOPS.md)**. Raccourcis (`make help`) :

| Commande | Effet |
|---|---|
| `make doctor` | Vérifie Flutter 3.44+ / Dart 3.12+ |
| `make web` | Prévisualisation web locale (offline-first, `0.0.0.0:8080`) |
| `make chrome` | Prévisualisation web dans Chrome (hot reload) |
| `make build-web` | Build web de production (`app/build/web/`) |
| `make apk` / `make apk-release` | APK Android debug / release (`dist/`) |
| `make test` / `make analyze` | Tests + lints |

**Déploiement continu** (GitHub Actions) :

- `deploy.yml` — à chaque push sur `main` : analyze + tests + build web →
  **GitHub Pages** (`https://<owner>.github.io/DTNH-assistant-club/`).
- `android-apk.yml` — build **APK** téléchargeable (artefact) ; sur tag `v*`,
  attaché à la GitHub Release.

**Vercel** est déjà branché (intégration Git) : chaque push sur la branche
déploie une preview, et `vercel.json` + `scripts/vercel_build.sh` compilent
l'app web dans le conteneur Vercel. Hébergement alternatif : **Firebase
Hosting** (`firebase.json`) — voir le guide DevOps.

---

## Synchronisation (Supabase / Google Sheets)

### A. Supabase — cible par défaut, zéro configuration

1. Le schéma est déjà déployé (tables `dtnh_players`, `dtnh_attendance`,
   `dtnh_transactions`, journal `dtnh_sync_log`, 2 vues d'agrégation). Version
   SQL rejouable : [`supabase/migrations/20261105000000_dtnh_sync_schema.sql`](supabase/migrations/20261105000000_dtnh_sync_schema.sql).
2. L'Edge Function **`dtnh-sync`** reçoit les lots et écrit en PostgreSQL.
3. L'application pointe dessus automatiquement (`lib/core/config/app_config.dart`).
   **Réglages → Synchronisation → Tester la connexion** doit répondre
   « Supabase connecté (DTNH). ».

Sécurité : RLS activée **sans policy** (la clé `anon` ne voit rien), seule la
clé `service_role` de la fonction écrit. Détails et regénération du secret :
[`docs/05-DEVOPS.md` § 8](docs/05-DEVOPS.md#8-synchronisation-supabase).

### B. Google Sheets — cible alternative (webhook Apps Script)

1. Ouvrir le Google Sheet du club → **Extensions → Apps Script**.
2. Coller [`apps-script/Code.gs`](apps-script/Code.gs) (et
   [`appsscript.json`](apps-script/appsscript.json)).
3. Exécuter la fonction **`setup`** : crée les onglets `Présences`,
   `Transactions`, `Joueurs`, `_Journal` et génère le **secret partagé**.
4. **Déployer → Nouveau déploiement → Application web**
   (Exécuter en tant que : *Moi*, Accès : *Tout le monde*) → copier l'URL `/exec`.
5. Dans l'app : **Réglages → Synchronisation → Google Sheets**, coller l'URL +
   le secret, puis **Tester la connexion**.

---

## Installer l'application

- **Android (Chrome/Edge)** : **Réglages → Installer l'application** →
  prompt natif (PWA).
- **iPhone/iPad (Safari)** : Partager → *Sur l'écran d'accueil*.
- **APK Android** : bouton de téléchargement dans la même carte, ou artefacts du
  workflow `android-apk.yml`.

---

## Architecture

**Feature-first** pour la navigation humaine, **Clean Architecture** à l'intérieur
(`presentation → application → domain ← data`). Le domaine est du Dart pur : ni
Flutter, ni Hive, ni HTTP.

```
app/lib/
├── core/       # thème, widgets partagés, utils (Ariary, dates), erreurs
├── domain/     # entités, enums, contrats de repositories  (Dart pur)
├── data/       # Hive (adapters + DAO), repositories, client Apps Script
├── sync/       # moteur outbox → webhook, scheduler réseau, worker d'arrière-plan
├── di/         # graphe Riverpod
└── features/   # attendance, finance, history, sync, settings, shell
```

Documentation complète : **[`docs/01-ARCHITECTURE.md`](docs/01-ARCHITECTURE.md)**
(diagrammes de couches, cycle de vie d'une écriture, table des providers
Riverpod, comparatif Hive/Drift/Isar, gestion d'erreurs, performance).

---

## Modèles de données

5 modèles persistés :

| Modèle | Rôle | Clé |
|---|---|---|
| `AttendanceEntry` | 1 joueur × 1 séance (statut, auteur, horodatage) | UUID v4 |
| `FinancialTransaction` | Entrée ou sortie d'argent (motif, moyen, auteur) | UUID v4 |
| `SyncQueueItem` | Opération en attente d'envoi (payload JSON, statut, tentatives) | UUID v4 |
| `Player` | Roster local (actif/archivé, numéro, catégorie) | UUID v4 |
| `AppSettings` | Webhook, secret, auteur, préférences | clés plates |

Détail champ par champ, ordre de sérialisation Hive, versionnage des adapters,
et **DDL SQLite/Drift équivalent** (avec index et requêtes d'agrégat) :
**[`docs/02-DATA-MODEL.md`](docs/02-DATA-MODEL.md)**.

Invariants clés :

- `(sessionId, playerId)` unique → re-pointer met à jour, ne duplique pas ;
- un seul `SyncQueueItem` `PENDING` par entité → coalescence des envois ;
- `amount` entier > 0 (le sens est porté par `flow` `IN`/`OUT`) ;
- `status = SYNCED` ⇒ entité locale `syncState = synced` (icône UI).

---

## Moteur de synchronisation

```
écriture UI → Hive (immédiat) → file PENDING → (réseau) → POST lot → Apps Script
                                     ↑                                    │
                                     └──── ERROR / retry ←── résultats/item
```

- **Coalescence** : corriger un pointage 3 fois hors-ligne n'envoie qu'une ligne.
- **Idempotence** : l'ID client est la colonne A du Sheet ; un renvoi met à jour.
- **Succès partiel** : Apps Script renvoie un statut par item ; seuls les refus
  passent en `ERROR`, les autres sont marqués `SYNCED`.
- **Aucune perte** : les tentatives sont comptées avant marquage, plafond 8,
  réessai manuel possible depuis l'écran Synchro.
- **Arrière-plan** : Workmanager (contrainte réseau), isolate dédié qui rouvre
  Hive et relit la configuration.

Détails (machine à états, codes HTTP, cas limites, `curl` de test) :
**[`docs/03-SYNC-PROTOCOL.md`](docs/03-SYNC-PROTOCOL.md)**.

---

## Tests

| Fichier | Périmètre |
|---|---|
| `app/test/core/money_test.dart` | Formatage/parsing Ariary, clés de date, libellés FR |
| `app/test/domain/aggregates_test.dart` | Taux de présence, soldes, enums tolérants |
| `app/test/data/local_repository_test.dart` | Hive réel : idempotence, coalescence, tombstones, stats |
| `app/test/sync/sync_engine_test.dart` | Lots, succès partiel, panne réseau, retry |
| `apps-script/test/webhook_test.mjs` | Webhook **exécuté pour de vrai** hors Google (Sheet simulé) : idempotence, `delete`, quotas, journal |

```bash
cd app && flutter test                  # app Flutter (Dart)
node apps-script/test/webhook_test.mjs  # backend Apps Script (Node, 0 dépendance)
```

Le second script est volontairement sans dépendance : il charge `Code.gs` dans
un contexte `vm` avec un Google Sheet en mémoire, ce qui permet de valider le
backend avant même de déployer le webhook.

> **Vérification honnête** : les fichiers Dart ont été relus et vérifiés
> statiquement (imports, équilibrage syntaxique, formateur `dart_style`), mais
> **le SDK Flutter n'était pas disponible dans l'environnement de génération**.
> Lancez `flutter analyze` puis `flutter test` à la première ouverture : les
> seuls ajustements attendus sont des lints de style.

---

## Structure du dépôt

```
.
├── app/                  # application Flutter
│   ├── lib/ test/        # code Dart + tests
│   ├── android/          # plateforme Android (versionnée, configurée DTNH)
│   ├── web/              # plateforme Web (PWA : index.html, manifest, icônes)
│   └── pubspec.yaml
├── apps-script/          # webhook Google Apps Script (Code.gs, manifest, doc)
├── scripts/              # doctor, run_web, build_web, build_apk, setup_platforms
├── config/               # vercel.json, .firebaserc.example
├── .github/workflows/    # deploy.yml (Pages) + android-apk.yml (APK)
├── docs/                 # architecture, data model, sync, UX, DevOps (05)
│   └── mockups/          # maquettes HTML navigables (+ serve.py)
├── assets/branding/      # logo / icône source DTNH
├── firebase.json         # Firebase Hosting
├── Makefile              # raccourcis (make help)
└── README.md
```

### Voir les maquettes tout de suite

Aucun outil n'est nécessaire (pas de Flutter, pas de npm) : un simple serveur
statique Python affiche les 4 écrans cliquables.

```bash
python3 docs/mockups/serve.py          # http://localhost:8080
python3 docs/mockups/serve.py 9000     # autre port
```

Les maquettes sont servies avec `Cache-Control: no-store` : après une
modification, un rafraîchissement suffit (aucune version fantôme en cache).
Leur JavaScript est vérifié par un test de DOM réel (26 assertions, aucune
erreur d'exécution) :

```bash
cd docs/mockups/test && npm i jsdom && node mockup_dom_test.mjs
```

---

## Choix techniques

| Sujet | Choix | Justification |
|---|---|---|
| Framework | **Flutter** | Un seul code pour Android/iOS, UI réactive, écosystème mature |
| État | **Riverpod** | Flux dérivés (compteurs, synthèses) en une ligne ; injection sans `BuildContext`, donc moteur testable |
| Stockage | **Hive** (adapters manuels) | Aucune génération de code, écritures < 1 ms, projet qui compile dès le clone ; volumétrie club ≈ 1 500 lignes/saison |
| Connectivité | **connectivity_plus** | Détection du retour réseau (déclencheur principal de sync) |
| Fond | **workmanager** | Filet de sécurité quand l'app est fermée ; contrainte réseau respectée |
| Backend | **Apps Script (webhook)** | Aucune clé OAuth dans l'APK, secret révocable, validation et dédoublonnage côté serveur |
| Montants | **int Ariary** | L'ariary n'a pas de sous-unité utilisée : zéro erreur d'arrondi |
| Dates | **`yyyy-MM-dd` + ms epoch** | Tri lexicographique = chronologique, insensible au fuseau |

Alternatives évaluées et raisons du refus : voir
[`docs/01-ARCHITECTURE.md` §6](docs/01-ARCHITECTURE.md).

---

## Limites connues & roadmap

**Limites assumées aujourd'hui**

- Pas de **pull** depuis le Sheet (le roster se saisit dans l'app) — prévu v1.2.
- Pas de résolution de conflits : le dernier `upsert` gagne (acceptable pour un
  staff qui pointe une séance donnée).
- Secret du webhook stocké dans Hive non chiffré : permutation vers
  `flutter_secure_storage` possible sans toucher au reste (interface abstraite).
- Workmanager iOS nécessite la capability *Background Modes* dans Xcode ; sur
  Android, rien à configurer.

**Roadmap**

1. **v1.1** — Édition d'une transaction, export CSV, partage du récapitulatif.
2. **v1.2** — `action: "pull"` : import du roster saisi par le secrétariat.
3. **v1.3** — Notifications locales (rappel de pointage, écolages impayés).
4. **v2.0** — Multi-saison + migration Drift si la volumétrie dépasse
   ~50 000 lignes de présence.

---

## Licence

MIT — voir [LICENSE](LICENSE).
