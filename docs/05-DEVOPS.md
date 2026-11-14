# 05 — DevOps : build, prévisualisation & déploiement

Guide opérationnel pour lancer, compiler et déployer **DTNH Assistant Club**
(application Flutter offline-first). Toutes les commandes sont exécutables
telles quelles depuis la racine du dépôt.

> **Version cible : Flutter 3.44+ / Dart 3.12+.** La CI est épinglée sur
> **Flutter 3.44.9**. Les dossiers `app/android/` et `app/web/` sont versionnés
> et calés sur cette version (Gradle 9.1.0, AGP 9.0.1, Kotlin 2.3.20, JDK 17).

## Sommaire

1. [Prérequis & `flutter doctor`](#1-prérequis--flutter-doctor)
2. [Prévisualisation locale Web (offline / CORS)](#2-prévisualisation-locale-web)
3. [Prévisualisation Android / émulateur](#3-prévisualisation-android--émulateur)
4. [Build Web de production](#4-build-web-de-production)
5. [Build APK & distribution interne](#5-build-apk--distribution-interne)
6. [Déploiement Web (Pages / Vercel / Firebase)](#6-déploiement-web)
7. [CI/CD GitHub Actions](#7-cicd-github-actions)
8. [Synchronisation Supabase](#8-synchronisation-supabase)
9. [Comptes & connexion Google](#9-comptes--connexion-google)
10. [Installer l'application (PWA / APK)](#10-installer-lapplication-pwa--apk)
11. [Dépannage](#11-dépannage)

---

## 1. Prérequis & `flutter doctor`

| Outil | Version | Pour quoi |
|---|---|---|
| Flutter | **≥ 3.44** (stable) | compiler l'app |
| Dart | **≥ 3.12** (livré avec Flutter) | langage |
| JDK | **17** | build Android (APK) |
| Android SDK | API 36, minSdk 24 | build Android |
| Chrome | récent | prévisualisation web |
| Node.js | ≥ 18 | tests du webhook (optionnel) |

Installer Flutter : <https://docs.flutter.dev/get-started/install>

```bash
# Vérification automatique des versions + flutter doctor détaillé
bash scripts/doctor.sh
# ou : make doctor

# Vérification manuelle
flutter --version          # doit afficher Flutter 3.44.x / Dart 3.12.x
flutter doctor -v
```

Si la version est trop ancienne :

```bash
flutter channel stable
flutter upgrade
```

> **Astuce** : `make help` liste tous les raccourcis (`make web`, `make apk`…).

---

## 2. Prévisualisation locale Web

### Commande exacte

```bash
# Serveur web headless, écoute sur toutes les interfaces (idéal proxy/preview)
bash scripts/run_web.sh                 # http://0.0.0.0:8080
# ou : make web

# Ouvrir directement Chrome avec hot reload
bash scripts/run_web.sh --chrome        # http://localhost:8080
# ou : make chrome

# Port personnalisé
PORT=9000 bash scripts/run_web.sh
```

Équivalent Flutter brut :

```bash
cd app
flutter pub get
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
# ou : flutter run -d chrome --web-port 8080
```

### Mode offline & CORS — ce qu'il faut savoir

- **Stockage local (Hive)** : sur le web, Hive utilise **IndexedDB**, qui est
  *same-origin*. Il n'y a donc **aucune restriction CORS** sur les données
  locales, et aucun bypass de sécurité navigateur n'est nécessaire. L'app
  fonctionne **hors-ligne** une fois chargée (PWA + service worker).
- **Webhook Google Apps Script** : c'est le seul appel *cross-origin*. Un POST
  `application/json` déclencherait un préflight `OPTIONS` qu'Apps Script ne gère
  pas. Le client envoie donc le corps en **`text/plain`** sur le web (voir
  [`app/lib/data/remote/apps_script_client.dart`](../app/lib/data/remote/apps_script_client.dart)),
  ce qui en fait une requête « simple » sans préflight. Apps Script lit
  `e.postData.contents` et parse le JSON quel que soit le `Content-Type`.
- **Compatibilité web du code** : `dart:io` n'existe pas sur le web. La détection
  de `SocketException` passe par un import conditionnel
  ([`network_error.dart`](../app/lib/data/remote/network_error.dart)) ;
  `hive_flutter` bascule déjà sur un stub web. `flutter build web` compile donc
  sans erreur.

> **Ne pas** lancer Chrome avec `--disable-web-security` : inutile ici, et
> dangereux. Le correctif `text/plain` est la solution propre.

---

## 3. Prévisualisation Android / émulateur

Le dossier `app/android/` est déjà versionné et configuré (permissions réseau,
splash DTNH, icône). Aucune génération manuelle n'est requise.

```bash
cd app
flutter pub get
flutter devices                 # lister émulateurs/appareils
flutter emulators --launch <id> # démarrer un émulateur (ou ouvrir Android Studio)
flutter run -d <device_id>      # lancer l'app (hot reload)
```

Prérequis Android : Android Studio (SDK + émulateur) et JDK 17. Vérifier avec
`flutter doctor`. Sur un téléphone physique, activer le **débogage USB**.

> iOS n'est pas versionné (dépend de macOS/Xcode). Pour l'ajouter :
> `bash scripts/setup_platforms.sh` (ou `make setup-ios`).

---

## 4. Build Web de production

```bash
# Base href "/" (Vercel, Firebase, domaine racine)
bash scripts/build_web.sh
# ou : make build-web

# Base href "/DTNH-assistant-club/" (GitHub Pages projet)
BASE_HREF="/DTNH-assistant-club/" bash scripts/build_web.sh
# ou : make pages-web
```

Commande Flutter sous-jacente :

```bash
cd app
flutter build web --release --base-href "/" --pwa-strategy=offline-first
```

Résultat : **`app/build/web/`** (statique, prêt à héberger). Le service worker
PWA précache l'app pour l'usage hors-ligne. Tester le rendu :

```bash
python3 -m http.server 8090 --directory app/build/web
# ouvrir http://localhost:8090
```

> `--base-href` **doit** correspondre au chemin réel de déploiement, sinon les
> assets ne chargent pas (page blanche). Voir [Dépannage](#8-dépannage).

---

## 5. Build APK & distribution interne

```bash
bash scripts/build_apk.sh            # debug (rapide, installable)
bash scripts/build_apk.sh release    # release (signé clé debug, installable)
bash scripts/build_apk.sh split      # release split-par-ABI (APK plus légers)
# ou : make apk / make apk-release / make apk-split
```

Résultat : **`dist/dtnh-assistant-v<version>-<mode>.apk`**.

L'APK *release* est signé avec la **clé debug** (config dans
[`android/app/build.gradle.kts`](../app/android/app/build.gradle.kts)) : il est
**immédiatement installable** par le staff, sans keystore à gérer. C'est parfait
pour la distribution interne.

Installer sur un téléphone :

```bash
adb install -r dist/dtnh-assistant-v1.2.0-release.apk
# ou transférer le .apk sur l'appareil et l'ouvrir (autoriser les sources inconnues)
```

### Pour le Play Store (plus tard) : vraie clé de signature

1. Générer un keystore :
   ```bash
   keytool -genkey -v -keystore ~/dtnh-release.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias dtnh
   ```
2. Créer `app/android/key.properties` (**ne jamais committer**) :
   ```properties
   storePassword=...
   keyPassword=...
   keyAlias=dtnh
   storeFile=/chemin/vers/dtnh-release.jks
   ```
3. Charger `key.properties` dans `app/build.gradle.kts` et remplacer
   `signingConfig = signingConfigs.getByName("debug")` par la config release.
4. `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`.

---

## 6. Déploiement Web

Trois options. **GitHub Pages est recommandé** car entièrement automatisé et
sans secret à configurer.

### A. GitHub Pages (automatique, recommandé)

1. Dépôt GitHub → **Settings → Pages → Build and deployment → Source =
   « GitHub Actions »**.
2. Pousser sur `main` : le workflow [`deploy.yml`](../.github/workflows/deploy.yml)
   compile et déploie automatiquement.
3. URL : `https://<owner>.github.io/DTNH-assistant-club/`.

Le `--base-href "/DTNH-assistant-club/"` est calculé automatiquement par la CI.

### B. Vercel

La config [`config/vercel.json`](../config/vercel.json) est copiée dans
`app/build/web/` par `scripts/build_web.sh` (rewrites SPA + en-têtes cache).

```bash
# 1) Builder avec base href racine
bash scripts/build_web.sh

# 2) Déployer le dossier statique (CLI Vercel, https://vercel.com/docs/cli)
npm i -g vercel
cd app/build/web
vercel deploy --prod --yes
```

> Vercel ne fournit pas Flutter dans son image de build : on déploie donc le
> **résultat déjà compilé** (`app/build/web`). Pour un déploiement depuis la CI,
> ajouter un job utilisant `vercel deploy --token=$VERCEL_TOKEN` (secret GitHub).

### C. Firebase Hosting

Config [`firebase.json`](../firebase.json) à la racine (public = `app/build/web`).

```bash
bash scripts/build_web.sh                 # base href "/"
npm i -g firebase-tools
firebase login
cp config/.firebaserc.example .firebaserc  # puis renseigner le project-id
firebase deploy --only hosting
```

---

## 7. CI/CD GitHub Actions

Deux workflows dans [`.github/workflows/`](../.github/workflows/) :

| Fichier | Déclencheur | Action |
|---|---|---|
| `deploy.yml` | push `main` (app/**), PR, manuel | analyze + tests + build web → **GitHub Pages** (déploiement sur `main` uniquement) |
| `android-apk.yml` | push `main`, tag `v*`, manuel | build **APK** → artefact téléchargeable ; sur tag `v*`, attaché à la Release |

- Flutter épinglé : **3.44.9** (`subosito/flutter-action@v2`, cache activé).
- APK : JDK 17 (`actions/setup-java@v4`).
- Récupérer un APK : onglet **Actions** → run → **Artifacts** → `dtnh-assistant-apk`.
- Publier une version : `git tag v1.0.1 && git push origin v1.0.1` → APK release
  attaché à la GitHub Release.

---

## 8. Synchronisation Supabase

Depuis la version 1.1, la cible de synchronisation par défaut est **Supabase
(PostgreSQL)**, avec Google Sheets toujours disponible en second choix (voir
Réglages > Synchronisation dans l'application).

### 8.1 Ce qui existe côté serveur

| Objet | Rôle |
| --- | --- |
| `dtnh_players` | effectif (nom, catégorie, numéro, téléphone, actif) |
| `dtnh_attendance` | une ligne par joueur et par séance |
| `dtnh_transactions` | mouvements financiers (montants en Ariary entiers) |
| `dtnh_sync_log` | journal des lots reçus (diagnostic « le téléphone a-t-il envoyé ? ») |
| `dtnh_finance_summary` | vue : entrées/sorties/solde par mois |
| `dtnh_attendance_summary` | vue : présents/absents/excusés par séance |
| Edge Function `dtnh-sync` | endpoint HTTPS appelé par l'application |

Le schéma complet (rejouable à l'identique) est versionné dans
`supabase/migrations/20261105000000_dtnh_sync_schema.sql`.

**Sécurité** : la RLS est activée **sans aucune policy**. La clé `anon` ne peut
ni lire ni écrire ; seule la clé `service_role` (utilisée par l'Edge Function)
a accès. L'application mobile/web **n'embarque aucune clé Supabase** : elle
présente un simple secret partagé (`DTNH_SHARED_SECRET`) à la fonction, exactement
comme le `SHARED_SECRET` d'Apps Script.

### 8.2 Vérifier que la synchronisation fonctionne

Dans l'application : **Réglages > Synchronisation** doit afficher
« Configuration du club active : rien à saisir. », puis
**Tester la connexion** doit répondre « Supabase connecté (DTNH). ».

En SQL (Dashboard Supabase > SQL Editor) :

```sql
-- Derniers lots reçus
select batch_id, device_id, item_count, received_at
from dtnh_sync_log order by received_at desc limit 10;

-- Totaux financiers du club
select * from dtnh_finance_summary;
```

### 8.3 Regénérer le secret (si fuite ou changement d'équipe)

```bash
# 1) nouveau secret
openssl rand -hex 24

# 2) côté Supabase : Project Settings > Edge Functions > Secrets
#    mettre à jour DTNH_SHARED_SECRET (ou via l'outil de gestion des secrets)

# 3) côté application : rebuild avec la nouvelle valeur
flutter build web --release \
  --dart-define=DTNH_SUPABASE_SECRET="<nouveau secret>"
```

Les téléphones déjà installés continuent de fonctionner hors-ligne ; ils
reprendront l'envoi après mise à jour de l'application (ou saisie du secret
dans Réglages, qui surcharge la valeur compilée).

---

## 9. Comptes & connexion Google

Depuis la version 1.2, les membres peuvent se connecter avec leur **compte
Google**. La connexion est **facultative** : le bouton « Continuer sans compte
(hors-ligne) » reste disponible et l'application démarre même si Supabase est
injoignable (l'initialisation échoue silencieusement).

### 9.1 Ce qui est déjà dans le code

| Élément | Fichier |
| --- | --- |
| Service d'authentification (`signInWithGoogle`, `signOut`, session restaurée) | `app/lib/data/auth/auth_service.dart` |
| État global Riverpod (`user`, `isLoading`, `error`, `isConfigured`) | `app/lib/features/auth/auth_controller.dart` |
| Écran de connexion (carte Google + carte mode local) | `app/lib/features/auth/login_screen.dart` |
| Remplissage automatique du pointage (`authorName` / `authorId`) | `settingsProvider.notifier.setAuthenticatedAuthor()` |
| Retour OAuth Android (`mg.dtnh.dtnh_assistant_club://login-callback`) | `app/android/app/src/main/AndroidManifest.xml` |

Le flux utilisé est **OAuth PKCE via Supabase Auth** (`AuthFlowType.pkce`) :
aucun secret Google n'est embarqué dans l'application, seul l'`anon key`
Supabase est compilé dans le bundle (public par conception, protégé par les RLS).

### 9.2 Les 4 étapes à faire une seule fois (côté console)

> Ces étapes ne peuvent pas être automatisées : elles exigent un accès humain
> aux consoles Google Cloud et Supabase. Tant qu'elles ne sont pas faites, le
> bouton Google renvoie « La connexion Google n'est pas encore activée côté
> serveur » — le reste de l'application fonctionne normalement.

1. **Google Cloud Console** > APIs & Services > *OAuth consent screen* :
   type « External », nom « DTNH Assistant Club », ajouter les e-mails des
   administrateurs en *test users*, publier (ou laisser en test).
2. **Google Cloud Console** > Credentials > *Create credentials* >
   **OAuth client ID** > type **Web application**.
   - *Authorized JavaScript origins* :
     `https://dtnh-assistant-club.vercel.app`
   - *Authorized redirect URIs* (obligatoire, c'est Supabase qui reçoit le code) :
     `https://osjsczvsnyknkdwbciab.supabase.co/auth/v1/callback`
   - Récupérer le **Client ID** et le **Client Secret**.
3. **Supabase** > Authentication > *Sign In / Providers* > **Google** :
   activer, coller le Client ID + Client Secret, enregistrer.
4. **Supabase** > Authentication > *URL Configuration* — déjà configuré, à
   vérifier si le domaine change :
   - *Site URL* : `https://dtnh-assistant-club.vercel.app`
   - *Redirect URLs* : `https://dtnh-assistant-club.vercel.app/**`,
     `https://dtnh-assistant-club-*.vercel.app/**` (previews),
     `http://localhost:8080/**`, `http://localhost:3000/**`,
     `https://fanasinjakaJoan.github.io/DTNH-assistant-club/**`,
     `mg.dtnh.dtnh_assistant_club://login-callback` (retour APK Android).

### 9.3 Variables optionnelles au build

```bash
flutter build web --release \
  --dart-define=DTNH_SUPABASE_URL="https://osjsczvsnyknkdwbciab.supabase.co" \
  --dart-define=DTNH_SUPABASE_ANON_KEY="<anon key>" \
  --dart-define=DTNH_GOOGLE_CLIENT_ID="<client id>.apps.googleusercontent.com"
```

`DTNH_GOOGLE_CLIENT_ID` sert uniquement à afficher un message d'aide explicite ;
le vrai couple ID/secret vit dans le dashboard Supabase. Dans GitHub
(`Settings > Secrets and variables > Actions`), les mêmes valeurs sont injectées
par `deploy.yml` via `DTNH_SUPABASE_URL`, `DTNH_SUPABASE_ANON_KEY`,
`DTNH_GOOGLE_CLIENT_ID`.

### 9.4 Vérifier que la connexion fonctionne

1. Ouvrir l'URL de production, cliquer « Continuer avec Google ».
2. Choisir un compte de test → retour sur l'application, l'écran de pointage
   s'ouvre et l'auteur est pré-rempli avec le nom du compte.
3. Dans Réglages, la section « Compte » affiche l'e-mail et permet de se
   déconnecter.
4. Côté Supabase : *Authentication > Users* montre l'utilisateur créé avec le
   provider `google`.

### 9.5 Erreurs fréquentes

| Message | Cause | Correctif |
| --- | --- | --- |
| « non activée côté serveur » | provider Google désactivé dans Supabase | étape 9.2.3 |
| `redirect_uri_mismatch` | URI de retour absente côté Google Cloud | ajouter `.../auth/v1/callback` |
| « URL de retour non autorisée » | domaine absent des *Redirect URLs* Supabase | étape 9.2.4 |
| `Unsupported provider: provider is not enabled` | même cause que la 1re ligne | étape 9.2.3 |
| Popup fermée immédiatement | bloqueur de pop-up | autoriser les pop-ups du site |

---

## 10. Installer l'application (PWA / APK)

Trois façons d'installer, aucune ne nécessite de store :

1. **Android, navigateur Chrome/Edge** — Réglages > « Installer l'application »
   déclenche le prompt natif (`beforeinstallprompt`, capturé dans
   `app/web/index.html`).
2. **iPhone/iPad, Safari** — la carte affiche les 3 gestes
   (Partager → Sur l'écran d'accueil → Ajouter).
3. **APK Android** — bouton « Télécharger l'application Android (APK) » qui
   pointe vers `DTNH_APK_URL` (par défaut : dernière release GitHub).

L'URL de l'APK est configurable au build :

```bash
flutter build web --release \
  --dart-define=DTNH_APK_URL="https://github.com/<owner>/<repo>/releases/latest"
```

Pour produire un APK publiable (workflow `android-apk.yml`, déclenché par un
tag `v*`), voir la section 5.

---

## 11. Dépannage

**Page blanche après déploiement** — le `--base-href` ne correspond pas au
chemin. GitHub Pages projet → `"/DTNH-assistant-club/"` ; Vercel/Firebase racine
→ `"/"`. Reconstruire avec la bonne valeur.

**Ancienne version affichée (PWA)** — le service worker a mis l'app en cache.
Forcer un rechargement (Ctrl+Shift+R), ou dans DevTools → Application → Service
Workers → *Unregister*, puis recharger. Les en-têtes `no-cache` sur
`index.html` / `flutter_service_worker.js` (configs Vercel/Firebase) limitent ce
problème.

**Erreur CORS sur la sync web** — vérifier que l'URL du webhook se termine par
`/exec` et que le déploiement Apps Script est accessible à « Tout le monde ».
Le client envoie déjà `text/plain` pour éviter le préflight ; aucun réglage
navigateur n'est nécessaire.

**`SocketException` / build web échoue sur `dart:io`** — ne pas importer
`dart:io` directement dans du code compilé pour le web. Utiliser le helper
conditionnel `network_error.dart` (modèle fourni).

**Gradle / `gradlew` introuvable** — le wrapper Gradle (`gradlew`,
`gradle-wrapper.jar`) est **injecté automatiquement** par Flutter au premier
`flutter build apk` / `flutter run`. Ne pas les committer (voir
`app/android/.gitignore`). `local.properties` (chemin du SDK) est aussi généré
automatiquement.

**Versions Gradle/AGP** — calées sur Flutter 3.44.9 (Gradle 9.1.0, AGP 9.0.1,
Kotlin 2.3.20). En cas de montée de version majeure de Flutter, régénérer les
plateformes avec `scripts/setup_platforms.sh` puis réappliquer les
personnalisations DTNH (ou `git checkout app/android app/web`).

**Build APK en échec sur `:workmanager:compileDebugKotlin`** — la version du
plugin `workmanager` doit suivre le toolchain Kotlin. Flutter 3.44.9 embarque
Kotlin 2.3.20 / AGP 9.0.1 : `workmanager` **≥ 0.10.0** est requis (la 0.5.x ne
compile plus). Vérifier `app/pubspec.yaml` avant toute montée de version.

**Build APK en échec sur la mémoire JVM** — `app/android/gradle.properties` fixe
`-Xmx4G` : le modèle Flutter par défaut (`-Xmx8G`) dépasse la RAM des runners
GitHub Actions et des petites machines (« Could not reserve enough space for
object heap »).

**`flutter pub get` échoue** — vérifier `flutter --version` ≥ 3.44. Le
`pubspec.yaml` exige Dart ≥ 3.12 / Flutter ≥ 3.44.
