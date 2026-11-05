# Webhook Google Apps Script — DTNH Assistant Club

Ce dossier contient le backend de synchronisation : un petit service Apps Script
attaché au Google Sheet du club, qui reçoit les lots JSON envoyés par
l'application Flutter et **upsert** les lignes par ID.

## Pourquoi un webhook Apps Script plutôt que l'API Sheets côté app ?

| Critère | Webhook Apps Script (retenu) | Google Sheets API directe |
|---|---|---|
| Authentification | 1 secret partagé, révocable en 1 clic | OAuth 2.0 + refresh token par appareil |
| Risque de fuite | L'app ne peut écrire que des lignes validées | Un token volé peut lire/écrire tout le Drive |
| Configuration côté club | Coller un script, déployer | Créer un projet Google Cloud, activer l'API, gérer les consentements |
| Contrôle serveur | Validation, journal, déduplication, quotas | Aucun (logique uniquement côté client) |

## Déploiement (5 minutes)

1. Ouvrir le Google Sheet cible → **Extensions → Apps Script**.
2. Remplacer `Code.gs` par le contenu de [`Code.gs`](./Code.gs).
3. Remplacer `appsscript.json` par [`appsscript.json`](./appsscript.json)
   (activer « Afficher le fichier de manifeste » dans les paramètres du projet).
4. Exécuter la fonction **`setup`** une fois, autoriser les accès :
   - crée les onglets `Présences`, `Transactions`, `Joueurs` et `_Journal` ;
   - génère le `SHARED_SECRET` et l'affiche dans une popup.
5. **Déployer → Nouveau déploiement → Application web**
   - Exécuter en tant que : **Moi**
   - Qui a accès : **Tout le monde**
   - Copier l'URL terminée par `/exec`.
6. Dans l'application : **Réglages → Webhook Google Apps Script**, coller l'URL
   et le secret, puis **Tester la connexion**.

> À chaque modification du script, créez un **nouveau déploiement** (ou
> « Gérer les déploiements → Modifier → Version : Nouvelle version ») : l'URL
> `/exec` reste identique.

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

| ID | Nom | Catégorie | Numéro | Téléphone | Actif | SyncTimestamp |
|---|---|---|---|---|---|---|

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
| HTML / 401 / 403 | erreur non réessayable : message « vérifiez le déploiement » |

## Quotas à connaître

- Apps Script : **20 000** appels `UrlFetch`/jour (non utilisé ici),
  **90 min** d'exécution/jour, **6 min** max par exécution.
- Un lot = 1 exécution : l'app envoie jusqu'à 80 items par lot, ce qui laisse
  une marge très large (un club génère ~200 lignes/semaine).
- `LockService` sérialise les écritures : deux téléphones qui synchronisent en
  même temps ne peuvent pas se marcher dessus.
