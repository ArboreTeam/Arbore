# 🌱 Arbore

[![CI/CD](https://github.com/ArboreTeam/Arbore/actions/workflows/ci.yml/badge.svg)](https://github.com/ArboreTeam/Arbore/actions/workflows/ci.yml)
[![CodeQL](https://github.com/ArboreTeam/Arbore/actions/workflows/codeql.yml/badge.svg)](https://github.com/ArboreTeam/Arbore/actions/workflows/codeql.yml)
[![Docker](https://github.com/ArboreTeam/Arbore/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/ArboreTeam/Arbore/actions/workflows/docker-publish.yml)
[![Docs](https://github.com/ArboreTeam/Arbore/actions/workflows/docs.yml/badge.svg)](https://github.com/ArboreTeam/Arbore/actions/workflows/docs.yml)

Arbore est un projet de 4ᵉ et 5ᵉ année : une application de jardinage qui aide à concevoir et entretenir ses jardins, avec la puissance de la réalité augmentée et de l'intelligence artificielle.

> 📚 **Documentation technique (bilingue FR/EN)** : **[`docs/`](docs/README.md)** — architecture C4, flows, tests, opérations, ADR.
> 🇬🇧 Technical docs are bilingual — see the [English entry point](docs/en/README.md).

## 📱 Fonctionnalités

- **🪴 Placement de plantes en AR** : concevez votre jardin en plaçant des plantes 3D en réalité augmentée (ARKit / RoomPlan).
- **🤖 Fiches plantes générées par IA** : conseils d'entretien multilingues générés via un service IA dédié.
- **🌍 Multilingue** : interface iOS en français, anglais, espagnol et allemand.
- **🌐 Compagnon web** : consultation du catalogue, des jardins, calendrier d'arrosage et gestion du compte sur [web.arbore.app](https://web.arbore.app).
- **🔐 Authentification sécurisée** : Firebase Auth (email/password, Google, Sign in with Apple).
- **📊 Données cloud** : stockage via le backend Go + MongoDB Atlas.

## 🏗️ Architecture

Arbore est composé de quatre modules déployés :

```
Arbore/
├── 📱 ArboreUi/          # Application iOS (SwiftUI · ARKit · RoomPlan)
├── 🌐 web/               # Front web compagnon (Next.js · TypeScript)
├── 🔧 ArboreBackend/     # API backend (Go 1.24 · Gin · MongoDB)
└── 🤖 AiGenerator/       # Service IA de génération de fiches (Python · FastAPI)
```

Le backend, l'AI Generator et le web tournent en containers Docker sur un VPS unique (Docker Compose) ; l'app iOS et le web parlent au backend via une API REST sécurisée (clé API + token Firebase). Détails complets : [`docs/`](docs/README.md) ([C4 Containers](docs/fr/architecture/02-containers.md)).

## 🚀 Démarrage rapide

### Backend (Go)

```bash
cd ArboreBackend
go mod download
cp .env.example .env        # renseigner MONGODB_URI, ARBORE_API_KEY, etc.
go run .                    # écoute sur :8080
```

### Web (Next.js)

```bash
cd web
npm install
cp .env.example .env.local  # BACKEND_API_URL + ARBORE_API_KEY (serveur), NEXT_PUBLIC_FIREBASE_*
npm run dev                 # http://localhost:3000
```

### iOS

```bash
cd ArboreUi
cp Secrets.xcconfig.example Secrets.xcconfig   # ARBORE_API_KEY, ARBORE_BACKEND_PROTOCOL/HOST
pod install
open ArboreUi.xcworkspace
```

Ajouter ensuite `GoogleService-Info.plist` (Firebase) et compiler sur un appareil iOS physique (requis pour ARKit). Runbooks détaillés (VPS, TestFlight, observabilité) : [`docs/fr/operations/`](docs/fr/operations/).

## 🧪 Tests

| Cible | Commande |
|---|---|
| Backend (Go) | `make test-backend` |
| iOS | `cd ArboreUi && xcodebuild test -workspace ArboreUi.xcworkspace -scheme ArboreUi -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2'` |
| Web | `cd web && npm test` |

Stratégie de test complète : [`docs/fr/testing/`](docs/fr/testing/).

## 🛠️ Technologies

| Composant | Technologies |
|---|---|
| **Mobile** | SwiftUI, ARKit, RoomPlan, RealityKit, Firebase, GoogleSignIn |
| **Web** | Next.js, React, TypeScript, Tailwind, shadcn/ui |
| **Backend** | Go, Gin, MongoDB driver, Unsplash API |
| **IA** | Python, FastAPI, OpenAI / Mistral |
| **Auth** | Firebase Auth, Google OAuth, Sign in with Apple |
| **Données** | MongoDB Atlas |
| **Observabilité** | Sentry (iOS + web) |
| **CI/CD** | GitHub Actions, Docker, fastlane (TestFlight) |

## 🤝 Contribution

Projet développé dans un cadre académique.

1. Fork du projet
2. Branche feature (`git checkout -b feature/ma-fonctionnalite`)
3. Commit des changements
4. Push vers la branche
5. Ouverture d'une Pull Request

> Toute PR touchant un domaine documenté doit mettre à jour la documentation correspondante (FR **et** EN) — cf. [`docs/`](docs/README.md).

## 📄 Licence

Projet développé dans un cadre éducatif (beta étudiante gratuite, non commerciale).

## 👥 Équipe

Développé par l'équipe ArboreTeam dans le cadre d'un projet de fin d'études.

| [<img src="https://github.com/Matribuk.png?size=85" width=85><br><sub>Antonin Leprest</sub>](https://github.com/Matribuk) | [<img src="https://github.com/hugorth.png?size=85" width=85><br><sub>Hugo Rath</sub>](https://github.com/hugorth) | [<img src="https://github.com/Jus2Orange.png?size=85" width=85><br><sub>Hugo Michel</sub>](https://github.com/Jus2Orange) | [<img src="https://github.com/tanssime.png?size=85" width=85><br><sub>Tanssime Mansour</sub>](https://github.com/tanssime) |
|:---:|:---:|:---:|:---:|

---

*Arbore — Cultivez votre passion du jardinage avec l'IA et la réalité augmentée* 🌱✨
