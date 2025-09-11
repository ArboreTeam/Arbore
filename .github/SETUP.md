# GitHub Actions - Secrets et Variables Requis

## 📋 Secrets à configurer dans GitHub

Allez dans Settings > Secrets and variables > Actions de votre repo GitHub et ajoutez :

### 🔒 Secrets obligatoires (pour déploiement)
- `GITHUB_TOKEN` - Automatiquement fourni par GitHub
- Aucun autre secret requis pour le workflow de base !

### 🔧 Secrets optionnels (pour fonctionnalités avancées)
- `OPENAI_API_KEY` - Pour l'AI Generator
- `MONGODB_URI` - URI de connexion MongoDB
- `UNSPLASH_ACCESS_KEY` - Clé API Unsplash pour les images

### 📱 Secrets iOS (pour déploiement TestFlight - optionnel)
- `IOS_CERTIFICATE` - Certificat de développement iOS (base64)
- `IOS_CERTIFICATE_PASSWORD` - Mot de passe du certificat
- `APPLE_ID` - Apple ID pour App Store Connect
- `APPLE_APP_PASSWORD` - Mot de passe d'application spécifique

### 🚀 Secrets de production (pour serveur dédié - optionnel)
- `PROD_HOST` - IP du serveur de production
- `PROD_USER` - Utilisateur SSH
- `PROD_SSH_KEY` - Clé privée SSH

## ⚙️ Variables d'environnement (publiques)

Dans Settings > Secrets and variables > Actions > Variables :

- `GO_VERSION` = "1.24" (ou votre version Go)
- `PYTHON_VERSION` = "3.11" (ou votre version Python)
- `XCODE_VERSION` = "latest-stable"

## 🐳 Images Docker générées

Les workflows créent automatiquement ces images dans GitHub Container Registry :

- `ghcr.io/arboreteam/arbore-backend:latest`
- `ghcr.io/arboreteam/arbore-ai:latest`

## 🔧 Test en local

```bash
# Vérifier le workflow localement (optionnel)
# Installer act : https://github.com/nektos/act
act -j build_summary  # Teste le job de résumé
act push              # Teste le workflow complet

# Build direct des images
docker build -t arbore-backend ArboreBackend/
docker build -t arbore-ai AiGenerator/
```

## 📊 Monitoring

Le workflow affiche automatiquement :
- ✅ Status de chaque composant (Backend, AI, iOS UI, iOS AR)
- 📦 Images Docker créées et pushées
- ⏭️ Composants ignorés (si pas de changements)
- ❌ Erreurs détaillées en cas d'échec
