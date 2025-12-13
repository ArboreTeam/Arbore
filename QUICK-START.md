# 🚀 Quick Start - CI/CD Arbore

## Pour commencer immédiatement

### 1️⃣ Vérifier que tout est OK
```bash
# Depuis la racine du projet
./scripts/validate-ci-config.sh
```

### 2️⃣ Installer les dépendances
```bash
make install
```

Ou manuellement :
```bash
# Backend Go
cd ArboreBackend && go mod download

# AI Generator Python
cd AiGenerator && pip install -r requirements.txt

# iOS UI (macOS uniquement)
cd ArboreUi && pod install --repo-update
```

### 3️⃣ Tester localement
```bash
# Test complet (simule la CI)
./ci-local.sh

# Ou par composant
make test-backend
make test-ai
```

### 4️⃣ Vérifier le code
```bash
# Linting
make lint

# Formatage
make format
```

### 5️⃣ Push avec confiance !
```bash
git add .
git commit -m "feat: amélioration CI/CD"
git push origin main
```

---

## 🔥 Commandes les plus utilisées

```bash
make help          # Liste toutes les commandes
make install       # Installe tout
make test          # Teste tout
make lint          # Vérifie le code
make format        # Formate le code
make clean         # Nettoie les builds
make ci-local      # Simule la CI
```

---

## 🆘 Problème ?

### CocoaPods ne s'installe pas
```bash
./scripts/fix-cocoapods.sh
```

### Code Python pas formaté
```bash
cd AiGenerator && black .
```

### Build Go échoue
```bash
cd ArboreBackend
go mod tidy
go mod download
```

### Plus d'aide
- 📖 [Documentation complète](docs/CI-CD.md)
- 🔧 [Guide de dépannage](docs/TROUBLESHOOTING.md)
- 📊 [Status final](CI-CD-FINAL-STATUS.md)

---

**C'est tout ! Votre CI/CD est prête ! 🎉**
