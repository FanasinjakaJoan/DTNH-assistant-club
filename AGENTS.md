# AGENTS.md — DTNH Assistant Club

Application Flutter *offline-first* pour la gestion d'un club de basketball
(pointage des présences, finances, effectif, synchronisation vers Google Sheets
puis Supabase).

## Structure

| Chemin | Rôle |
|---|---|
| `app/` | Application Flutter (Clean Architecture : `domain`, `data`, `features`, `sync`) |
| `apps-script/` | Backend Google Apps Script (`Code.gs`) + tests `node --test` |
| `supabase/` | Fonction Edge `dtnh-sync` et migrations SQL |
| `scripts/` | Build, prévisualisation, déploiement |
| `docs/` | Documentation de référence (01 à 05) |

## Commandes

```bash
make doctor          # vérifie Flutter/Dart
make test            # flutter test (dans app/)
make analyze         # flutter analyze
make webhook-test    # tests Apps Script (node --test)
make fn-test         # tests Deno de la fonction Edge
make fn-check        # deno check de la fonction Edge
make deploy-fn       # déploie dtnh-sync (requiert SUPABASE_ACCESS_TOKEN)
```

`make help` liste toutes les cibles.

## Conventions de test

- Toujours tester le vrai code : Hive est ouvert dans un dossier temporaire
  (`LocalDatabase.open(directory: ...)`), jamais mocké.
- Pas de mocks quand un faux objet simple suffit (`_FakeNetwork`,
  `_FakeSettings` dans `app/test/sync/sync_scheduler_test.dart`).
- Les tests Flutter sont dans `app/test/` ; la fonction Edge dans
  `supabase/functions/dtnh-sync/index_test.ts` ; Apps Script dans
  `apps-script/test/webhook_test.mjs`.
- `flutter analyze` doit rester à 0 erreur **et** 0 avertissement.

## Pièges connus

- **Streams Hive et annulation** : ne jamais écrire
  `await for (final store in _db.changes)` dans un générateur `async*`. Un
  `await for` en attente ne se laisse pas annuler, ce qui bloque `dispose()` et
  laisse des abonnements zombies. Utiliser `_db.watch(store)` avec `yield*`
  (helper dans `LocalDatabase`). Régression couverte par des tests dans
  `app/test/data/local_repository_test.dart`.
- **Migration Hive** : toute évolution d'entité persistée incrémente la version
  de l'adaptateur (`PlayerAdapter` v1 → v2 pour `birthDate`). Une version
  inconnue doit échouer explicitement, jamais être lue de travers.
- **Déclencheurs de synchronisation** : quatre (écriture locale, retour en
  ligne, reprise de l'app, filet périodique), coalescés dans
  `SyncScheduler`. Ne pas ajouter d'appel réseau synchrone dans l'UI.
- **`Deno.serve`** : la fonction Edge expose `handleRequest` et ne démarre le
  serveur que si `DTNH_DISABLE_SERVE` n'est pas défini, pour que les tests
  n'ouvrent pas de port.

## Serveur / déploiement

- Projet Supabase : `osjsczvsnyknkdwbciab`.
- Le token `SUPABASE_ACCESS_TOKEN` n'est pas toujours disponible dans
  l'environnement de l'agent : livrer alors l'outillage reproductible
  (`scripts/deploy_supabase_function.sh`, workflow, cibles Makefile) plutôt que
  de tenter un déploiement.
- Voir `docs/05-DEVOPS.md` (§ 8.5 pour `BOOT_ERROR`, § 9.5 pour la connexion
  Google) et `docs/03-SYNC-PROTOCOL.md` (déclencheurs, machine à états).
