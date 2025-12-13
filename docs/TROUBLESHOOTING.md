# 🔧 Guide de dépannage - Arbore CI/CD

## Problèmes courants et solutions

### 🍎 iOS / CocoaPods

#### ❌ Erreur : `None of your spec sources contain a spec satisfying the dependency`

**Cause :** Le pod spécifié n'existe pas ou la source CocoaPods n'est pas configurée.

**Solution :**
1. Vérifiez que `source 'https://cdn.cocoapods.org/'` est présent en haut du Podfile
2. Vérifiez le nom exact du pod sur [cocoapods.org](https://cocoapods.org)
3. Utilisez le script de nettoyage :
   ```bash
   ./scripts/fix-cocoapods.sh
   ```

**Exemple :** FacebookLogin v18 n'existe pas, utilisez `FBSDKLoginKit` à la place.

---

#### ❌ Erreur : `pod install` échoue

**Solution complète :**
```bash
cd ArboreUi

# 1. Nettoyer le cache
pod cache clean --all

# 2. Supprimer les fichiers générés
rm -rf Pods Podfile.lock ArboreUi.xcworkspace

# 3. Mettre à jour les repos
pod repo update

# 4. Réinstaller
pod install --repo-update --verbose
```

Ou utilisez le script automatique :
```bash
./scripts/fix-cocoapods.sh
```

---

#### ❌ Build Xcode échoue avec des erreurs de signature

**Cause :** Code signing requis mais non configuré.

**Solution :** Dans le workflow CI, on désactive la signature :
```yaml
CODE_SIGNING_ALLOWED=NO
CODE_SIGN_IDENTITY=""
```

En local, utilisez votre profil de développement ou désactivez temporairement.

---

### 🐍 Python / AI Generator

#### ❌ Erreur : `black --check` échoue

**Cause :** Le code n'est pas formaté selon les standards Black.

**Solution :**
```bash
cd AiGenerator

# Installer Black
pip install black

# Formater automatiquement
black .

# Vérifier
black --check .
```

**Configuration :** Voir `AiGenerator/pyproject.toml` pour les règles.

---

#### ❌ Erreur : Tests pytest échouent

**Solution :**
```bash
cd AiGenerator

# Installer les dépendances de test
pip install pytest pytest-cov

# Créer le dossier tests si nécessaire
mkdir -p tests
touch tests/__init__.py

# Lancer les tests
pytest -v
```

---

#### ❌ Erreur : `flake8` trouve trop d'erreurs

**Solution :**
```bash
# Voir la configuration dans setup.cfg
cd AiGenerator

# Corriger automatiquement ce qui peut l'être
black .

# Vérifier ce qui reste
flake8 . --max-line-length=88 --extend-ignore=E203,W503
```

---

### 🔒 CodeQL

#### ❌ Erreur : `Swift analysis is only supported on macOS`

**Cause :** CodeQL essaie d'analyser Swift sur Ubuntu.

**Solution ✅ (déjà corrigée) :**
Le workflow `codeql.yml` utilise maintenant une matrice conditionnelle :
```yaml
runs-on: ${{ matrix.language == 'swift' && 'macos-14' || 'ubuntu-latest' }}
```

Swift s'exécute sur macOS, Go et Python sur Ubuntu.

---

### 🐹 Go / Backend

#### ❌ Erreur : `go.mod` out of sync

**Solution :**
```bash
cd ArboreBackend

# Nettoyer et retélécharger
go mod tidy
go mod download
go mod verify
```

---

#### ❌ Erreur : golangci-lint timeout

**Solution :**
```bash
cd ArboreBackend

# Augmenter le timeout
golangci-lint run --timeout=5m ./...
```

Configuration dans `.golangci.yml` :
```yaml
run:
  timeout: 5m
```

---

#### ❌ Tests avec race detector échouent

**Cause :** Condition de course détectée dans le code.

**Solution :** Corriger le code pour éviter les accès concurrents non synchronisés.

**Test en local :**
```bash
go test -race ./...
```

---

### 🐳 Docker

#### ❌ Build Docker échoue

**Solution :**
```bash
# Backend
cd ArboreBackend
docker build -t arbore-backend:test .

# AI Generator
cd AiGenerator
docker build -t arbore-ai:test .
```

**Nettoyer les images :**
```bash
docker system prune -a
```

---

#### ❌ Trivy scan trouve des vulnérabilités

**Action :**
1. Examiner les vulnérabilités dans le rapport
2. Mettre à jour les dépendances concernées
3. Rebuild l'image

**Note :** Le scan Trivy est en `continue-on-error: true` pour ne pas bloquer le build.

---

### 🔧 GitHub Actions

#### ❌ Cache GitHub Actions corrompu

**Solution :**
1. Aller dans `Settings > Actions > Caches`
2. Supprimer les caches problématiques
3. Re-lancer le workflow

---

#### ❌ Workflow timeout

**Cause :** Le job dépasse la limite de temps.

**Solution :** Augmenter le timeout dans le workflow :
```yaml
jobs:
  job-name:
    timeout-minutes: 60  # Défaut: 360 (6h)
```

Nos timeouts actuels :
- iOS UI: 45 minutes
- iOS AR: 30 minutes
- Autres: défaut

---

#### ❌ Artifact upload échoue

**Cause :** Fichier trop volumineux ou chemin incorrect.

**Solution :**
```yaml
- uses: actions/upload-artifact@v4
  with:
    name: mon-artifact
    path: |
      chemin/vers/fichier1
      chemin/vers/fichier2
    retention-days: 7
```

---

### 🔐 Secrets et permissions

#### ❌ `GITHUB_TOKEN` n'a pas les permissions

**Solution :** Ajouter les permissions au workflow :
```yaml
permissions:
  contents: read
  pull-requests: write
  checks: write
  packages: write  # Pour Docker
  security-events: write  # Pour CodeQL
```

---

#### ❌ Codecov upload échoue

**Solution :**
1. Créer un token sur [codecov.io](https://codecov.io)
2. Ajouter `CODECOV_TOKEN` dans les secrets GitHub
3. Le workflow l'utilisera automatiquement

**Note :** Actuellement en `continue-on-error: true`.

---

## 🛠️ Commandes de diagnostic

### Vérifier l'environnement local

```bash
# Script complet
./ci-local.sh

# Ou manuellement
make ci-local
```

### Vérifier Go
```bash
go version
go env
cd ArboreBackend && go mod verify
```

### Vérifier Python
```bash
python3 --version
pip list
cd AiGenerator && pip check
```

### Vérifier Xcode
```bash
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
pod --version
```

---

## 📝 Logs utiles

### Voir les logs détaillés GitHub Actions
Dans GitHub Actions, cliquez sur le job puis le step pour voir les logs complets.

### Activer le mode debug
Ajouter ces secrets dans le repo :
- `ACTIONS_STEP_DEBUG` = `true`
- `ACTIONS_RUNNER_DEBUG` = `true`

### Logs locaux
```bash
# Backend
cd ArboreBackend && go test -v ./...

# Python
cd AiGenerator && pytest -vv

# iOS (verbose)
xcodebuild ... | tee build.log
```

---

## 🆘 Besoin d'aide ?

1. Vérifier la [documentation CI/CD](CI-CD.md)
2. Examiner les logs GitHub Actions
3. Tester localement avec `./ci-local.sh`
4. Ouvrir une issue avec le label `ci/cd`

---

## 📚 Ressources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [CocoaPods Guides](https://guides.cocoapods.org/)
- [golangci-lint](https://golangci-lint.run/)
- [Black Formatter](https://black.readthedocs.io/)
- [CodeQL Documentation](https://codeql.github.com/)
