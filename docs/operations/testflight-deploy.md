# TestFlight Deploy — Fastlane

Procédure pour déposer une nouvelle build de l'app iOS sur TestFlight et la
distribuer automatiquement au groupe interne « Internal QA ». Lane
principale : `bundle exec fastlane beta`.

Le pipeline en une commande :

1. Bump `CFBundleVersion` à `latest_testflight + 1`
2. `xcodebuild archive` (export `app-store`)
3. Upload sur App Store Connect via l'API Key
4. Attend la fin du processing Apple (5-30 min)
5. Distribue au groupe « Internal QA » (pas de Beta App Review)

---

## Setup initial (one-shot)

### 1. Créer l'App Store Connect API Key

Rôle requis : **Admin** sur ArboreTeam dans App Store Connect.

1. Aller sur [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
2. Cliquer sur **« + »** pour générer une nouvelle clé.
3. Nom : `arbore-fastlane-beta`. Access : **App Manager** (suffisant pour upload TestFlight, pas besoin d'Admin).
4. Télécharger le fichier `.p8` (téléchargeable **une seule fois** — perdu = recommencer).
5. Noter le **Key ID** (visible sur la ligne de la clé après création) et l'**Issuer ID** (en haut de la page).

> **Pourquoi cette clé** : elle remplace l'authentification interactive Apple ID + 2FA. Sans elle, fastlane échoue dans 80 % des cas à cause des codes 2FA reçus sur un device tiers.

### 2. Poser `fastlane/AuthKey.json`

Reformater le contenu du `.p8` en JSON :

```bash
cat > fastlane/AuthKey.json << EOF
{
  "key_id": "<Key ID>",
  "issuer_id": "<Issuer ID>",
  "key": "$(cat ~/Downloads/AuthKey_<KeyID>.p8 | awk '{printf "%s\\n", $0}')",
  "in_house": false
}
EOF
chmod 600 fastlane/AuthKey.json
```

Vérifier que le fichier est bien gitignored :

```bash
git check-ignore -v fastlane/AuthKey.json
# → .gitignore:172:fastlane/AuthKey.json   fastlane/AuthKey.json
```

> ⚠️ Si `git check-ignore` ne retourne rien, ne PAS continuer — `AuthKey.json` serait commit au prochain `git add .`. Le pre-commit hook gitleaks devrait aussi rattraper, mais ne pas s'en remettre.

### 3. Créer le groupe « Internal QA » sur App Store Connect

1. App Store Connect → ArboreUi → **TestFlight → Internal Testing → « + »**.
2. Group Name : `Internal QA`.
3. Cocher **« Enable automatic distribution »** — chaque nouvelle build leur sera poussée sans configuration côté Fastfile.
4. Ajouter les membres : Antonin, Hugo M., Hugo R., Isaac, Tanssime + l'adresse de review interne si applicable.

> Le nom **doit** matcher la constante `INTERNAL_GROUP` dans `fastlane/Fastfile`. S'il change, modifier le Fastfile en conséquence.

### 4. Installer fastlane sur la machine qui déploie

Sur macOS avec Ruby installé via Homebrew, le dossier système des gems
n'est pas writable par défaut. Toujours installer les gems en local au
projet :

```bash
bundle config set --local path 'vendor/bundle'   # one-shot — écrit .bundle/config
bundle install
```

Cela installe la version pinnée dans `Gemfile` dans `vendor/bundle/`
(gitignored). Vérifier ensuite :

```bash
bundle exec fastlane --version
```

> Si `bundle install` échoue avec `Bundler::PermissionError` sur
> `/opt/homebrew/lib/ruby/...`, c'est que le `bundle config set` n'a pas
> été fait. La config est par-projet (dans `.bundle/config`), pas
> globale — chaque clone du repo doit la repasser.

> Alternative sans bundler : `brew install fastlane`. Plus simple mais
> sans pin de version — risque de dériver entre machines.

### 5. Vérifier le code signing Xcode

Ouvrir `ArboreUi.xcworkspace` dans Xcode :

- Target `ArboreUi` → onglet **Signing & Capabilities**
- **Automatically manage signing** activé
- Team : `ArboreTeam (582QH9652J)` (enforced par `.githooks/pre-commit`)

Si « Automatically manage signing » est désactivé, fastlane échouera sur l'étape `build_app` faute de provisioning profile à jour.

---

## Usage courant

### Déposer une nouvelle build interne

```bash
bundle exec fastlane beta
```

La commande :

- Échoue immédiatement si `fastlane/AuthKey.json` est absent.
- Récupère le dernier `build_number` sur TestFlight.
- Incrémente de 1 et l'écrit dans `ArboreUi.xcodeproj`.
- Archive l'app (~ 3-5 min sur M2/M3).
- Upload sur App Store Connect (~ 30-60 s).
- Attend la fin du processing Apple (5-30 min, peut être plus long si Apple charge la queue).
- Distribue automatiquement au groupe « Internal QA ».

Total : 10-40 min selon le processing Apple.

### Vérifier le dernier build sur TestFlight

```bash
bundle exec fastlane current_build
```

Utile pour confirmer que l'upload précédent a bien été enregistré côté ASC avant d'en lancer un autre.

### Annuler un build en cours

`Ctrl-C` pendant `build_app` : l'archive locale est jetée, rien n'est uploadé. Pendant `upload_to_testflight` : l'upload est interrompu, ASC peut ou non avoir enregistré la build (vérifier dans l'UI ASC). Si une build orpheline traîne dans TestFlight, la supprimer via l'UI ASC.

---

## Dépannage

| Symptôme | Cause probable | Fix |
|---|---|---|
| `Fastlane API key missing` au lancement | `fastlane/AuthKey.json` absent ou mal lu | Repasser sur l'étape 2 du setup |
| `Couldn't find bundle identifier` | `fastlane/Appfile` désynchronisé du projet Xcode | Vérifier `PRODUCT_BUNDLE_IDENTIFIER` dans `ArboreUi.xcodeproj/project.pbxproj` |
| `No provisioning profile found` | Automatic signing désactivé ou Team différent | Réactiver Automatic signing avec `ArboreTeam (582QH9652J)` |
| `Build number 42 already exists` | Race condition avec un autre upload en cours | Attendre la fin du processing, vérifier `current_build`, relancer |
| `App Store Connect timeout` | Processing Apple anormalement long | Vérifier le statut sur [Apple System Status](https://www.apple.com/support/systemstatus/), relancer plus tard |
| `Code signing entitlements` divergent | Capabilities Xcode modifiées sans MAJ ASC | Activer/désactiver la capability dans Xcode, builder à nouveau |

### Logs détaillés

```bash
bundle exec fastlane beta --verbose
```

Les rapports Junit sont écrits dans `fastlane/report.xml` (gitignored).

---

## Hors scope (issues séparées si besoin)

- **CI macOS GitHub Actions** qui lance `fastlane beta` sur push de tag : faisable mais demande des minutes Actions macOS (10× plus chères qu'Ubuntu) + un secret pour l'API key. Pas urgent tant que le deploy interne reste manuel.
- **match (fastlane)** pour le code signing multi-machines : nécessite un repo privé séparé pour les certificats chiffrés. À considérer si plusieurs personnes uploadent.
- **Lane `release`** vers les testeurs externes : demande Beta App Review Apple à chaque submission. Sprint 4.

---

## Références

- Issue de mise en place : [#156](https://github.com/ArboreTeam/Arbore/issues/156)
- [Apple — App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [Fastlane — `upload_to_testflight`](https://docs.fastlane.tools/actions/upload_to_testflight/)
- [Fastlane — `app_store_connect_api_key`](https://docs.fastlane.tools/actions/app_store_connect_api_key/)
