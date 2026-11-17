# Webhook Google Apps Script — DTNH Assistant Club

Ce dossier contient le backend de synchronisation : un petit service Apps Script
attaché au Google Sheet du club, qui reçoit les lots JSON envoyés par
l'application Flutter et **upsert** les lignes par ID.

## Pourquoi un webhook Apps Script plutôt que l'API Sheets côté app ?

| Critère | Webhook Apps Script (retenu) | Google Sheets API directe |
|---|---|---|
| Authentification | **identité Google** (le membre est déjà connecté) ou 1 secret partagé révocable | OAuth 2.0 + refresh token par appareil |
| Risque de fuite | L'app ne peut écrire que des lignes validées | Un token volé peut lire/écrire tout le Drive |
| Configuration côté club | Coller un script, déployer | Créer un projet Google Cloud, activer l'API, gérer les consentements |
| Contrôle serveur | Validation, journal, déduplication, quotas | Aucun (logique uniquement côté client) |

## Déploiement (5 minutes)

1. Ouvrir le Google Sheet cible → **Extensions → Apps Script**.
2. Remplacer `Code.gs` par le contenu de [`Code.gs`](./Code.gs).
3. Remplacer `appsscript.json` par [`appsscript.json`](./appsscript.json)
   (activer « Afficher le fichier de manifeste » dans les paramètres du projet).
4. Exécuter la fonction **`setup`** une fois, autoriser les accès :
   - crée (ou met à jour) les onglets `Présences`, `Transactions`, `Joueurs`
     et `_Journal` — y compris l'ajout de colonnes récentes comme
     « Date de naissance » ;
   - génère le `SHARED_SECRET` s'il n'existe pas ;
   - publie la **fiche de configuration** (`URL`, secret, ID du classeur) et
     l'affiche dans une popup.
5. **Déployer → Nouveau déploiement → Application web**
   - Exécuter en tant que : **Moi**
   - Qui a accès : **Tout le monde**
   - Copier l'URL terminée par `/exec`.
6. **Publier la configuration côté Supabase** (une seule fois, puis à chaque
   fois que l'URL `/exec` change) :

   ```sql
   update public.dtnh_club_config
      set sheets_webhook_url    = 'https://script.google.com/macros/s/<ID>/exec',
          sheets_webhook_secret = '<SHARED_SECRET>',
          sheet_id              = '<id du classeur>',
          updated_by            = 'votre@email'
    where id = 1;
   ```

   C'est la dernière étape de configuration manuelle de tout le projet. Elle
   n'est **pas** à refaire par membre : chaque personne qui se connecte avec
   Google reçoit automatiquement l'URL et le secret, et l'application les
   utilise sans aucune saisie.

> À chaque modification du script, créez un **nouveau déploiement** (ou
> « Gérer les déploiements → Modifier → Version : Nouvelle version »). Si l'URL
> `/exec` change, refaites l'étape 6 : c'est une ligne de SQL, pas un
> redéploiement de l'Edge Function.

## Authentification : la connexion Google suffit

Le webhook accepte **deux** preuves d'identité. Une seule est requise.

| Preuve | Comment | Usage |
|---|---|---|
| **Jeton Google** | en-tête `Authorization: Bearer <id_token>` | chemin nominal : l'utilisateur est déjà connecté dans l'app |
| **Secret partagé** | champ `secret` du corps JSON | appareil non connecté, secours, scripts |

Vérification d'un jeton Google (`authenticate_` / `verifyGoogleToken_`) :

1. appel `https://oauth2.googleapis.com/tokeninfo?id_token=<jeton>` ;
2. réponse **200** exigée, e-mail présent, `email_verified` respecté ;
3. si la propriété de script `ALLOWED_EMAILS` est définie (liste séparée par
   des virgules), l'e-mail doit y figurer — sinon réponse
   « compte non autorisé » ;
4. résultat mis en cache 600 s dans `CacheService`, la clé étant un SHA-256 du
   jeton (aucun jeton en clair dans le cache) ;
5. **aucun repli silencieux** vers le secret quand un jeton invalide est
   présenté : la requête est refusée. Un jeton expiré ne doit pas dégrader
   l'authentification en douce.

`ping` renvoie l'identité réellement reconnue, ce qui rend le diagnostic
immédiat :

```json
{ "ok": true, "identity": "google", "email": "coach@dtnh.mg",
  "serverTime": "2026-11-05T09:12:00.000Z", "message": "DTNH webhook actif" }
```

`identity` vaut `"google"` ou `"secret"`.

## Contrat d'API

### Test de vie

```
GET  .../exec?secret=<SHARED_SECRET>&action=ping
```

```json
{ "ok": true, "message": "DTNH webhook actif", "serverTime": "2026-11-05T09:12:00.000Z" }
```

### Envoi d'un lot

```http
POST .../exec
Content-Type: application/json
```

```json
{
  "action": "push",
  "secret": "e3b0c44298fc1c149afbf4c8",
  "deviceId": "5f1c…",
  "batchId": "b7a2…",
  "sentAt": "2026-11-05T09:12:03.000Z",
  "items": [
    {
      "id": "8c2f…",
      "entity": "attendance",
      "sheet": "Présences",
      "operation": "upsert",
      "data": {
        "id": "8c2f…",
        "date": "2026-11-05",
        "categorie": "U16",
        "joueur": "Rakotobe Fandresena",
        "statut": "PRESENT",
        "auteur": "Coach Tojo",
        "heure": "08:45",
        "joueurId": "9a1e…",
        "sessionId": "41d0…",
        "numero": 3,
        "note": null
      }
    },
    {
      "id": "b19a…",
      "entity": "transaction",
      "sheet": "Transactions",
      "operation": "upsert",
      "data": {
        "id": "b19a…",
        "date": "2026-11-05",
        "flux": "IN",
        "categorie": "ECOLAGE",
        "montant": 60000,
        "details": "Écolage novembre",
        "auteur": "Trésorier",
        "modePaiement": "MVOLA",
        "joueur": "Rasoa Miora",
        "mois": "2026-11"
      }
    }
  ]
}
```

Réponse (une ligne de résultat **par item** — le client marque chaque élément
`SYNCED` ou `ERROR` individuellement) :

```json
{
  "ok": true,
  "message": "2 ligne(s) enregistrée(s).",
  "serverTime": "2026-11-05T09:12:04.512Z",
  "results": [
    { "id": "8c2f…", "sheet": "Présences", "status": "ok" },
    { "id": "b19a…", "sheet": "Transactions", "status": "duplicate" }
  ]
}
```

`status` ∈ `ok` (nouvelle ligne) · `duplicate` (ligne existante mise à jour,
comptée comme un succès) · `error` (avec un champ `error` lisible).

### Idempotence

- La colonne A (`ID`) est la clé primaire logique.
- Un renvoi du même lot (après timeout réseau) **met à jour** les lignes
  existantes au lieu d'en créer de nouvelles : aucun doublon possible.
- `operation: "delete"` supprime la ligne correspondante (utilisé quand une
  transaction est annulée dans l'app).

## Schéma des onglets

### `Présences`

| ID | Date | Catégorie | Joueur | Statut | Auteur | SyncTimestamp | Heure | JoueurID | SessionID | Numéro | Note |
|---|---|---|---|---|---|---|---|---|---|---|---|

### `Transactions`

| ID | Date | Flux | Catégorie | Montant | Détails | Auteur | SyncTimestamp | Mode de paiement | Joueur | Staff | Événement | Mois |
|---|---|---|---|---|---|---|---|---|---|---|---|---|

### `Joueurs`

| ID | Nom | Catégorie | Date de naissance | Numéro | Téléphone | Actif | SyncTimestamp |
|---|---|---|---|---|---|---|---|

« Date de naissance » est **nullable** : les fiches créées avant l'ajout de la
colonne restent valides, la cellule est simplement vide. `setup()` réapplique
les en-têtes sur une feuille existante, ce qui fait apparaître la colonne sans
migration manuelle.

### `_Journal` (masqué)

Traçabilité technique : date de réception, appareil, lot, nombre d'éléments,
succès, erreurs, statut. Permet de diagnostiquer un problème réseau sans
toucher aux données métier.

## Codes de statut attendus côté client

| Réponse | Comportement de l'app |
|---|---|
| `200` + `ok: true` | items marqués `SYNCED` |
| `200` + `ok: false` et `results` partiels | items OK → `SYNCED`, les autres → `ERROR` |
| `200` + `retryable: true` (verrou, quota) | tentatives incrémentées, backoff |
| `401` / `403` (jeton Google invalide, secret faux) | erreur **non** réessayable, message « vérifiez le secret / le compte » |
| `5xx` (Apps Script indisponible, `BOOT_ERROR`) | retenté, avec message incluant le détail serveur |
| HTML inattendu (URL fausse, mauvais déploiement) | erreur non réessayable : message « vérifiez le déploiement » |

## Quotas à connaître

- Apps Script : **20 000** appels `UrlFetch`/jour (non utilisé ici),
  **90 min** d'exécution/jour, **6 min** max par exécution.
- Un lot = 1 exécution : l'app envoie jusqu'à 80 items par lot, ce qui laisse
  une marge très large (un club génère ~200 lignes/semaine).
- `LockService` sérialise les écritures : deux téléphones qui synchronisent en
  même temps ne peuvent pas se marcher dessus.

## Tester le webhook sans déployer

`apps-script/test/webhook_test.mjs` exécute `Code.gs` dans Node en simulant les
services Google (Sheet en mémoire, `PropertiesService`, `LockService`,
`ContentService`, `CacheService`, `UrlFetchApp` et `Utilities.computeDigest`).
Aucune dépendance npm, aucun compte Google nécessaire :

```bash
node apps-script/test/webhook_test.mjs
```

Le harnais vérifie le contrat réel du webhook : `ping`, secret invalide,
création des en-têtes, upsert idempotent (un rejeu renvoie `duplicate` sans
ajouter de ligne), mise à jour d'une ligne existante, opération `delete`,
isolement d'un item invalide, garde-fou `MAX_ITEMS`, journal `_Journal`,
réinjection de l'ID si le client l'oublie, **identité Google** (jeton valide,
jeton inconnu, compte hors `ALLOWED_EMAILS`, cache des jetons, absence de
`ALLOWED_EMAILS`) et publication de la configuration par `setup()`. Sortie code
`0`/`1` : utilisable en CI avant de redéployer l'Apps Script.

> Ce harnais a déjà détecté un bug réel : un client qui n'envoyait pas `id`
> dans `data` produisait des lignes sans clé, donc non dédupliquées. `Code.gs`
> réinjecte désormais l'ID depuis l'item avant construction de la ligne.
