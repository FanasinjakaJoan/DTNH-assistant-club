# Design system & UX — DTNH Assistant Club

Le contexte d'usage dicte tout : **bord de terrain**, plein soleil, une main,
parfois des doigts mouillés ou gantés, réseau absent. Chaque décision ci-dessous
sert ce contexte.

## 1. Tokens

### Couleurs

| Token | Valeur | Usage |
|---|---|---|
| `navy` | `#0F172A` | Identité club, barres, solde |
| `orange` | `#F97316` | Action principale, sélection, progression |
| `orangeSoft` | `#FFEDD5` | Fonds de sélection douce |
| `green` | `#16A34A` | Présent · entrée d'argent · synchronisé |
| `red` | `#DC2626` | Absent · sortie d'argent · erreur |
| `amber` | `#F59E0B` | En retard · hors-ligne · en attente |
| `blue` | `#2563EB` | Excusé · synchronisation en cours |
| `surface` | `#F5F7FA` | Fond d'écran |
| `border` | `#E2E8F0` | Bordures et séparateurs |
| `textPrimary` / `textSecondary` / `textMuted` | `#0F172A` / `#64748B` / `#94A3B8` | Hiérarchie typographique |

Les couleurs de statut sont **sémantiques** : vert = présent partout dans l'app,
rouge = absent/sortie. Un coach doit pouvoir lire l'écran de loin sans lire les
libellés.

Les 4 catégories ont une couleur stable (bleu ciel, violet, orange, émeraude) :
le repère visuel remplace la lecture du code `U14-U15`.

### Typographie

| Rôle | Taille | Graisse |
|---|---|---|
| Chiffre héros (solde, taux) | 30-32 | 800 |
| Titre d'écran | 20 | 700 |
| Titre de section | 16 | 700 |
| Corps | 13,5-14 | 500-600 |
| Métadonnée | 11-11,5 | 500 |
| Micro-libellé (pills) | 9,5-10,5 | 600-700 |

### Espacement, rayons, tactile

- Grille 4 pt ; padding d'écran 16 ; padding de carte 12-18.
- Rayons : `18` (cartes), `14` (champs/boutons), `999` (pills).
- **Cible tactile minimale 48 dp** ; les boutons de statut du pointage font
  **44 dp de haut sur toute la largeur disponible** (4 boutons par joueur).
- Bouton d'enregistrement : pleine largeur, 52 dp, ancré en bas (zone du pouce).

## 2. Écrans et parcours

### 2.1 Premier lancement — `AuthorScreen`

Pas de compte, pas de mot de passe : on demande **le nom de l'utilisateur**
(suggestions : Coach Tojo, Coach Naina, Président, Trésorier, Secrétaire) et on
propose de pré-remplir l'effectif de démonstration. Objectif : arriver au
pointage en moins de 20 secondes.

### 2.2 Pointage — `AttendanceScreen`

```
┌───────────────────────────────────────┐
│ Pointage                  [☁ 3]  (CT)│ ← état sync + avatar auteur
│ U16 · mercredi 5 novembre 2026         │
├───────────────────────────────────────┤
│ [U12] [U14-U15] [U16] [U17-U18]        │ ← catégorie (couleur stable)
│ [dim][lun][mar]… [mer][jeu] [📅]      │ ← 7 derniers jours + calendrier
│ ⚠ Hors-ligne : tout est conservé      │
│ ┌───────────────────────────────────┐ │
│ │ 9 / 10 pointés            90 %    │ │
│ │ ████████████████████░░░           │ │
│ │ ✅ Présent 8  ❌ Absent 1  ⏰ 0  ✓ 0│ │
│ │ [Tout présent]   [Réinitialiser]  │ │
│ └───────────────────────────────────┘ │
│ Joueurs (10)              [Effectif]  │
│ ┌───────────────────────────────────┐ │
│ │ (3) Rakotobe Fandresena   Présent │ │
│ │ [Présent][Absent][Retard][Excusé] │ │
│ └───────────────────────────────────┘ │
│ …                                     │
├───────────────────────────────────────┤
│ 9/10 pointés · 8 présents  [Enregistrer]│
└───────────────────────────────────────┘
```

Règles :

1. **Un tap = un statut.** Re-taper le statut actif l'annule.
2. Le compteur et la barre se mettent à jour instantanément (aucun réseau).
3. La barre basse indique toujours l'état : « À enregistrer (local) »,
   « Enregistré à 08:45 ».
4. « Tout présent » puis correction des absents = 3 taps pour une séance normale.
5. Après enregistrement : snackbar avec action **Synchroniser** (jamais bloquante).

### 2.3 Finances — `FinanceScreen`

```
┌───────────────────────────────────────┐
│ Finances                     [☁]  ⚙  │
│ ┌───────────────────────────────────┐ │
│ │ SOLDE DU CLUB          nov. 2026  │ │
│ │ 1 250 000 Ar                      │ │
│ │ ↘ Entrées 320 k   ↗ Sorties 95 k  │ │
│ └───────────────────────────────────┘ │
│ [Entrées du mois][Sorties du mois]    │
│ Évolution sur 6 mois                  │
│ ▁▂▅█▃▂                                │
│ Répartition des sorties  [Entrée|Sortie]│
│ Rafraîchissements  ████████ 45 k      │
│ Location terrain   ██████ 50 k        │
│ Derniers mouvements        [Tout voir]│
│ 🏫 Écolage · Rasoa Miora · nov. 2026  │
│                          +60 000 Ar ☁ │
│ …                                     │
│                         [+ Nouvelle opération]
└───────────────────────────────────────┘
```

Parcours de saisie : **Nouvelle opération** → feuille de sélection
`Entrées / Sorties` (8 motifs avec icône + description) → **formulaire dédié** :

| Motif | Champs affichés en plus |
|---|---|
| Écolage | montant, date, moyen, **joueur**, **mois**, remarque |
| Cotisation | montant, date, moyen, joueur (facultatif), remarque |
| Billetterie | montant, date, moyen, **événement**, remarque |
| Location terrain | montant, date, moyen, remarque |
| Salaire coach | montant, date, moyen, **coach**, **mois**, remarque |
| Rafraîchissements | montant, date, moyen, **événement**, remarque |

Jamais plus de 6 champs visibles : on saisit une écolage en 4 gestes (montant →
joueur → mois → enregistrer).

### 2.4 Historique — `HistoryScreen`

- Bandeau : taux de présence effectif de la catégorie + répartition P/A/R/E.
- Bascule **Séances / Joueurs** (une icône dans l'AppBar).
- Séance : carte date + « X présents · Y retards · Z absents » + barre + état de
  sync ; tap → détail (qui a pointé, quand).
- Joueur : classement par taux, mini-barre colorée (vert ≥ 75 %, ambre ≥ 50 %,
  rouge sinon) et compte `8P · 1R · 2A`.

### 2.5 Synchro — `SyncScreen`

- Carte d'état (4 états possibles : non configuré / hors-ligne / en attente /
  erreur / à jour) + bouton **Synchroniser maintenant**.
- Compteurs : en attente · erreurs · envoyés.
- Section « À corriger » avec réessai individuel et « Tout réessayer ».
- File d'attente : 25 derniers items avec statut, tentatives, message d'erreur.
- Bloc pédagogique « Comment ça marche ? » en 4 étapes (transparence offline-first).

### 2.6 Réglages — `SettingsScreen`

Identité → Webhook (URL, secret, ID Sheet, test) → Automatisation (switch +
dernier envoi + opérations en attente) → Effectif → Données locales (nettoyage,
réinitialisation avec confirmation) → À propos.

## 3. Feedback hors-ligne (règle d'or)

| Situation | Message affiché | Où |
|---|---|---|
| Pas de réseau | « Hors-ligne : le pointage est enregistré sur le téléphone et partira automatiquement au retour du réseau. » | Bandeau haut du pointage |
| Éléments en attente | « N éléments en attente d'envoi vers Google Sheets. » + action **Envoyer** | Bandeau haut |
| Enregistrement local | « Pointage U16 enregistré · 10 joueur(s) » + action **Synchroniser** | Snackbar |
| Envoi réussi | « 15 élément(s) synchronisé(s) avec Google Sheets. » | Snackbar 3 s |
| Échec | « Synchronisation incomplète : <message serveur> » en rouge | Snackbar + écran Synchro |

L'utilisateur ne doit **jamais** voir un spinner lié au réseau dans le chemin
d'une saisie.

## 4. Accessibilité & terrain

- Contraste texte/fond ≥ 4,5:1 (textPrimary sur blanc, blanc sur navy/orange).
- Informations jamais portées par la couleur seule : chaque statut a une **icône**
  et un **libellé**.
- `Semantics(button: true, selected: …, label: 'Présent pour ce joueur')` sur les
  boutons de statut → VoiceOver/TalkBack utilisables.
- Montants lisibles : séparateur de milliers, jamais de décimales, suffixe `Ar`.
- Aucune donnée personnelle sensible stockée (nom du joueur + téléphone
  facultatif uniquement).
- Les écrans critiques (pointage, finances) fonctionnent **100 % hors-ligne**.

## 5. Micro-copie (français, tutoiement institutionnel)

| Contexte | Formulation |
|---|---|
| Validation montant | « Saisissez un montant supérieur à zéro. » |
| Webhook absent | « Aucun webhook configuré : renseignez l'URL Google Apps Script dans Réglages > Synchronisation. » |
| Secret invalide | « Secret invalide. » (serveur) → affiché tel quel |
| Déploiement mal configuré | « Accès refusé. Vérifiez que le déploiement Apps Script est bien accessible à « Tout le monde ». » |
| Confirmation destructive | « Tout effacer ? Les présences et transactions non synchronisées seront perdues. Cette action est irréversible. » |

Ton : direct, factuel, sans jargon technique dans les messages destinés au
staff ; le jargon reste dans les logs et l'écran Synchro.

## 6. Maquettes

Les maquettes navigables (HTML/CSS, sans dépendance) sont dans
[`mockups/index.html`](./mockups/index.html). Elles reprennent exactement les
tokens ci-dessus et servent de référence visuelle pour valider un écran avant de
l'implémenter en Flutter.
