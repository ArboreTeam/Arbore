# 🌱 Arbore CI/CD Documentation

## Vue d'ensemble

Ce projet utilise GitHub Actions pour l'intégration et le déploiement continus (CI/CD). Le pipeline est conçu pour être robuste, efficace et professionnel.

## 🔄 Workflows

### 1. **CI/CD Principal** (`.github/workflows/ci.yml`)

Pipeline principal qui s'exécute sur chaque push et PR vers `main` ou `develop`.

**Fonctionnalités :**
- ✅ Détection intelligente des changements (ne build que ce qui a changé)
- ✅ Tests automatisés avec couverture de code
- ✅ Linting et formatage du code
- ✅ Build multi-plateforme
- ✅ Upload des artefacts
- ✅ Résumé détaillé dans GitHub

**Jobs :**
- **changes** : Détecte quels composants ont été modifiés
- **backend** : Tests, lint et build du backend Go
- **ai_generator** : Tests, lint et build de l'AI Generator Python
- **ios_ui** : Build de l'application iOS UI avec CocoaPods
- **ios_ar** : Build du module AR Kit iOS
- **security** : Scan de sécurité avec Trivy
- **build_summary** : Résumé des résultats

### 2. **CodeQL Security** (`.github/workflows/codeql.yml`)

Analyse de sécurité automatique du code.

**Langages analysés :**
- Go
- Python
- Swift

**Fréquence :** Tous les lundis + sur chaque push/PR vers main

### 3. **Docker Publish** (`.github/workflows/docker-publish.yml`)

Build et publication des images Docker.

**Images :**
- Backend Go
- AI Generator Python

**Registry :** GitHub Container Registry (ghcr.io)

## 📋 Configuration requise

### Secrets GitHub (à configurer dans Settings > Secrets)

Aucun secret n'est requis pour la CI de base. Les secrets suivants sont optionnels :

- `CODECOV_TOKEN` : Pour l'upload vers Codecov (optionnel)

### Permissions

Le workflow nécessite les permissions suivantes (déjà configurées) :
- `contents: read`
- `pull-requests: write`
- `checks: write`
- `statuses: write`
- `packages: write` (pour Docker)

## 🛠️ Utilisation locale

### Makefile

Un `Makefile` complet est fourni pour exécuter les mêmes vérifications en local :

```bash
# Installer toutes les dépendances
make install

# Lancer tous les tests
make test

# Linter tout le code
make lint

# Formater le code
make format

# Build tous les composants
make build

# Simuler la CI complète
make ci-local

# Voir toutes les commandes disponibles
make help
```

### Tests individuels par composant

**Backend (Go) :**
```bash
cd ArboreBackend
go test -v -race -coverprofile=coverage.out ./...
golangci-lint run ./...
```

**AI Generator (Python) :**
```bash
cd AiGenerator
pytest -v --cov=. --cov-report=term
black --check .
flake8 . --max-line-length=88
```

**iOS UI :**
```bash
cd ArboreUi
pod install --repo-update
xcodebuild -workspace ArboreUi.xcworkspace \
  -scheme ArboreUi \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  build
```

## 🔧 Configuration des outils

### EditorConfig (`.editorconfig`)
Assure la cohérence du formatage du code entre les éditeurs.

### Golangci-lint (`.golangci.yml`)
Configuration du linter Go avec les règles suivantes :
- Vérification des erreurs non gérées
- Détection de code non utilisé
- Vérification de la complexité cyclomatique
- Détection du code dupliqué
- Analyse de sécurité

### Dependabot (`.github/dependabot.yml`)
Mise à jour automatique des dépendances :
- GitHub Actions (hebdomadaire)
- Go modules (hebdomadaire)
- Python pip (hebdomadaire)
- CocoaPods (hebdomadaire)

## 🐛 Résolution des problèmes courants

### Problème CocoaPods

**Erreur :** `Could not find compatible versions for pod "FacebookLogin"`

**Solution :**
```bash
cd ArboreUi
pod repo update
pod cache clean --all
pod install --repo-update
```

### Problème de cache GitHub Actions

Si les builds échouent de manière inattendue :
1. Aller dans Actions > Caches
2. Supprimer les caches obsolètes
3. Re-lancer le workflow

### Timeout sur les builds iOS

Les builds iOS peuvent prendre du temps. Timeout configuré à 45 minutes.

## 📊 Métriques et monitoring

### Coverage
- Backend : Via `go test -coverprofile`
- AI Generator : Via `pytest --cov`

### Artifacts
Les artefacts suivants sont conservés 7 jours :
- Binaires du backend (Linux + macOS)
- Builds iOS (Simulator)

### Résumé GitHub
Chaque run génère un résumé détaillé visible dans l'onglet Summary.

## 🚀 Déploiement

### Images Docker

Les images sont automatiquement publiées sur GitHub Container Registry :

```bash
# Pull les images
docker pull ghcr.io/arboreteam/arbore/backend:latest
docker pull ghcr.io/arboreteam/arbore/ai-generator:latest

# Run
docker run -p 8080:8080 ghcr.io/arboreteam/arbore/backend:latest
```

### Tags versionnés

Sur push d'un tag `v*.*.*`, les images sont taguées :
- `v1.2.3`
- `v1.2`
- `latest`
- SHA du commit

## 🔐 Sécurité

### CodeQL
Analyse de sécurité automatique chaque semaine et sur chaque PR.

### Trivy
Scan des vulnérabilités dans :
- Le code source
- Les images Docker

### SARIF
Les résultats sont uploadés dans GitHub Security pour un suivi centralisé.

## 📝 Pull Request Template

Un template de PR est fourni (`.github/pull_request_template.md`) avec :
- Description
- Type de changement
- Checklist
- Tests effectués
- Composants affectés

## 👥 Code Owners

Le fichier `.github/CODEOWNERS` définit les reviewers automatiques par composant.

## 🎯 Meilleures pratiques

1. **Toujours tester localement** avant de push avec `make ci-local`
2. **Créer des PR petites et focalisées** pour des reviews plus rapides
3. **Utiliser les labels** appropriés sur les PR
4. **Documenter les changements** dans les commits et PR
5. **Mettre à jour les tests** quand vous modifiez du code
6. **Vérifier les warnings** même s'ils ne cassent pas le build

## 📚 Ressources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [golangci-lint](https://golangci-lint.run/)
- [CodeQL](https://codeql.github.com/)
- [Trivy](https://aquasecurity.github.io/trivy/)

## 🆘 Support

Pour toute question sur la CI/CD, ouvrez une issue avec le label `ci/cd`.
