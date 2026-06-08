# Arbore - Interface Web (Next.js)

## Prérequis

- Node.js 18+
- npm
- Le backend Go doit tourner sur `http://localhost:8080`

## Installation

```bash
npm install
```

## Lancer le projet

### 1. Démarrer le backend Go

Dans un terminal séparé, depuis le dossier `Arbore/ArboreBackend` :

```bash
ARBORE_API_KEY=arbore-secret-2024 \
FIREBASE_SERVICE_ACCOUNT_PATH=./arbore-b1986-firebase-adminsdk-fbsvc-cd1c7271e1.json \
go run .
```

### 2. Démarrer le frontend

```bash
npm run dev
```

L'application est disponible sur : **http://localhost:3000**

## Variables d'environnement

Le fichier `.env.local` doit contenir :

```# Firebase Configuration
NEXT_PUBLIC_FIREBASE_API_KEY=AIzaSyDSqOesYSajdrZVEM5pyp9pydeImKkFRJ8
NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=arboré-b1986.firebaseapp.com
NEXT_PUBLIC_FIREBASE_PROJECT_ID=arbore-b1986
NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET=arboré-b1986.firebasestorage.app
NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID=669272877937
NEXT_PUBLIC_FIREBASE_APP_ID=1:66927287937:ios:7e859ce19838259c6e7780

# Backend API
NEXT_PUBLIC_API_URL=http://localhost:8080

```

## Stack

- Next.js 13
- TypeScript
- Tailwind CSS
- Firebase Auth
