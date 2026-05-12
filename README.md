# 🌱 Arbore

[![CI/CD](https://github.com/ArboreTeam/Arbore/actions/workflows/ci.yml/badge.svg)](https://github.com/ArboreTeam/Arbore/actions/workflows/ci.yml)
[![CodeQL](https://github.com/ArboreTeam/Arbore/actions/workflows/codeql.yml/badge.svg)](https://github.com/ArboreTeam/Arbore/actions/workflows/codeql.yml)
[![Docker](https://github.com/ArboreTeam/Arbore/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/ArboreTeam/Arbore/actions/workflows/docker-publish.yml)
[![Docs](https://github.com/ArboreTeam/Arbore/actions/workflows/docs.yml/badge.svg)](https://github.com/ArboreTeam/Arbore/actions/workflows/docs.yml)

Arbore est un projet de 4ème et 5ème année - une application complète de jardinage qui vous aide à organiser et entretenir vos jardins avec la puissance de la réalité augmentée et de l'intelligence artificielle.

> 📚 **[Documentation CI/CD complète](docs/CI-CD.md)**

## 📱 Fonctionnalités

- **🔍 Identification de plantes avec AR** : Scannez et identifiez les plantes en temps réel grâce à la réalité augmentée
- **🤖 Génération d'informations par IA** : Obtenez des conseils personnalisés sur l'entretien des plantes grâce à l'IA
- **🌍 Support multilingue** : Interface disponible en français, anglais, espagnol et allemand
- **📱 Application mobile native** : Interface utilisateur moderne et intuitive sur iOS
- **🔐 Authentification sécurisée** : Connexion via Google Sign-In et Firebase Auth
- **📊 Base de données cloud** : Stockage sécurisé avec MongoDB et Firebase Firestore

## 🏗️ Architecture

Le projet Arbore est composé de plusieurs modules interconnectés :

```
Arbore/
├── 📱 ArboreUi/          # Application iOS principale (SwiftUI)
├── 🥽 ArboreARkit/       # Module de réalité augmentée (ARKit)
├── 🔧 ArboreBackend/     # API Backend (Go + Gin + MongoDB)
└── 🤖 AiGenerator/       # Service IA de génération d'informations (Python + FastAPI)
```

### 📱 ArboreUi
- **Technologies** : SwiftUI, Firebase, Google Sign-In
- **Fonctionnalités** : Interface utilisateur principale, authentification, gestion des profils utilisateur
- **Localisation** : Support de 4 langues (fr, en, es, de)

### 🥽 ArboreARkit
- **Technologies** : ARKit, SwiftUI, RoomPlan
- **Fonctionnalités** : Scan 3D d'objets, visualisation AR, capture de modèles USDZ

### 🔧 ArboreBackend
- **Technologies** : Go, Gin Framework, MongoDB
- **Fonctionnalités** : API RESTful, gestion des données utilisateurs et plantes, intégration Unsplash

### 🤖 AiGenerator
- **Technologies** : Python, FastAPI, OpenAI GPT
- **Fonctionnalités** : Génération automatique d'informations sur les plantes multilingues

## 🚀 Installation et Lancement

### Prérequis
- **iOS** : Xcode 15+, iOS 17+
- **Backend** : Go 1.24+, MongoDB
- **IA** : Python 3.8+, clé API OpenAI
- **Services** : Compte Firebase, Google Cloud

### 🔧 Configuration du Backend

```bash
cd ArboreBackend

# Installation des dépendances
go mod tidy

# Configuration des variables d'environnement
cp .env.example .env
# Éditer .env et remplir les valeurs:
# - ARBORE_API_KEY (clé pour sécuriser l'API)
# - MONGODB_URI (connexion MongoDB)
# - OPENAI_API_KEY (pour génération IA)
# - UNSPLASH_ACCESS_KEY (pour images de plantes)

# Lancement du serveur
go run .
```

### 🤖 Configuration du générateur IA

```bash
cd AiGenerator

# Installation des dépendances
pip install -r requirements.txt

# Configuration de la clé OpenAI
export OPENAI_API_KEY="your_openai_api_key"

# Lancement du service
python main.py
```

### 📱 Configuration de l'application iOS

1. **Configuration des secrets**
   ```bash
   cd ArboreUi

   # Copier le template de secrets
   cp Secrets.xcconfig.example Secrets.xcconfig

   # Éditer Secrets.xcconfig et remplir les valeurs
   # ARBORE_API_KEY = votre_clé_api_backend
   # ARBORE_BACKEND_URL = http://79.137.92.154:8080
   ```

2. Ouvrez `ArboreUi.xcworkspace` dans Xcode
3. Configurez votre fichier `GoogleService-Info.plist` Firebase
4. Assurez-vous que les permissions caméra sont configurées dans `Info.plist`
5. Compilez et lancez sur un appareil iOS physique (requis pour ARKit)

## 🎯 Utilisation

1. **Connexion** : Connectez-vous avec votre compte Google
2. **Scan AR** : Utilisez la caméra pour scanner une plante
3. **Identification** : L'IA identifie automatiquement la plante
4. **Informations** : Consultez les conseils d'entretien personnalisés
5. **Suivi** : Organisez votre jardin et suivez vos plantes

## 📡 API Endpoints

### Backend (Port 8080)
- `POST /api/plants` - Créer une nouvelle plante
- `GET /api/plants` - Récupérer toutes les plantes
- `GET /api/plants/:id` - Récupérer une plante spécifique
- `POST /api/users` - Créer un utilisateur
- `GET /api/users/:uid` - Récupérer un utilisateur

### Générateur IA (Port 8000)
- `POST /generate` - Générer des informations sur une plante

## 🛠️ Technologies Utilisées

| Composant | Technologies |
|-----------|-------------|
| **Mobile** | SwiftUI, ARKit, Firebase, GoogleSignIn |
| **Backend** | Go, Gin, MongoDB, Unsplash API |
| **IA** | Python, FastAPI, OpenAI GPT-3.5/4 |
| **Auth** | Firebase Auth, Google OAuth |
| **Base de données** | MongoDB, Firebase Firestore |
| **3D/AR** | ARKit, RoomPlan, USDZ |

## 🌍 Internationalisation

L'application supporte 4 langues :
- 🇫🇷 Français (fr)
- 🇬🇧 Anglais (en)
- 🇪🇸 Espagnol (es)
- 🇩🇪 Allemand (de)

## 🤝 Contribution

Ce projet est développé dans le cadre d'un cursus académique. Les contributions sont les bienvenues via :

1. Fork du projet
2. Création d'une branche feature (`git checkout -b feature/nouvelle-fonctionnalite`)
3. Commit des changements (`git commit -m 'Ajout nouvelle fonctionnalité'`)
4. Push vers la branche (`git push origin feature/nouvelle-fonctionnalite`)
5. Ouverture d'une Pull Request

## 📄 Licence

Ce projet est développé dans un cadre éducatif.

## 👥 Équipe

Développé par l'équipe ArboreTeam dans le cadre d'un projet de fin d'études.

### Developers

| [<img src="https://github.com/Matribuk.png?size=85" width=85><br><sub>Antonin Leprest</sub>](https://github.com/Matribuk) | [<img src="https://github.com/hugorth.png?size=85" width=85><br><sub>Hugo Rath</sub>](https://github.com/hugorth) | [<img src="https://github.com/Jus2Orange.png?size=85" width=85><br><sub>Hugo Michel</sub>](https://github.com/Jus2Orange) | [<img src="https://github.com/tanssime.png?size=85" width=85><br><sub>Tanssime Mansour</sub>](https://github.com/tanssime) |
|:---:|:---:|:---:|:---:|

---

*Arbore - Cultivez votre passion du jardinage avec l'IA et la réalité augmentée* 🌱✨
