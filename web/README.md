# Arbore — front web (Next.js)

Compagnon web de l'application iOS : consultation du catalogue, des jardins et
de leurs plantes, calendrier d'arrosage, guide saisonnier, gestion du compte
(export et suppression RGPD). **Les jardins se créent sur iOS**, en réalité
augmentée.

Le même container sert aussi l'atelier de génération 3D sur
`generator.arbore.app` ; c'est l'hôte de la requête qui les distingue, et le
middleware rend 404 sur `/generator*` pour toute requête arrivant par
`web.arbore.app`.

Architecture détaillée :
[`docs/fr/architecture/03-components-web.md`](../docs/fr/architecture/03-components-web.md).

## Prérequis

- **Node.js 24+** — l'image de production est bâtie sur `node:26-alpine3.24`
- npm
- le backend Go joignable (par défaut `http://localhost:8080`)

## Démarrer

```bash
cd web
npm install
cp .env.example .env.local   # puis renseigner les valeurs
npm run dev                  # http://localhost:3000
```

Le backend, dans un autre terminal :

```bash
cd ArboreBackend
cp .env.example .env         # MONGODB_URI, ARBORE_API_KEY, etc.
go run .                     # écoute sur :8080
```

## Variables d'environnement

**La source de vérité est [`.env.example`](.env.example)** — ce tableau dit à
quoi chacune sert, pas quelles valeurs y mettre.

| Variable | Portée | Rôle |
|---|---|---|
| `NEXT_PUBLIC_FIREBASE_*` | navigateur | configuration du SDK Firebase client, inlinée **à la compilation** |
| `BACKEND_API_URL` | **serveur** | adresse du backend Go vue par le proxy (`http://backend:8080` en container) |
| `ARBORE_API_KEY` | **serveur** | clé applicative injectée par le proxy ; **jamais** préfixée `NEXT_PUBLIC_` |
| `NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_*` | mixte | observabilité, optionnelle — sans DSN le SDK ne démarre pas |

> ⚠️ **Le navigateur n'appelle jamais le backend directement.** Tout passe par
> `app/api/backend/[...path]/route.ts`, un proxy same-origin qui ajoute
> `X-API-Key` **côté serveur** et relaie le jeton Firebase de l'utilisateur.
> C'est ce qui fait qu'il n'y a pas de CORS, et que la clé d'API n'atteint
> jamais le client. Une variable `NEXT_PUBLIC_API_URL` pointant le backend
> annulerait les deux propriétés : il n'y en a pas.

## Scripts

| Commande | Effet |
|---|---|
| `npm run dev` | serveur de développement |
| `npm run build` | build de production (`output: 'standalone'`) |
| `npm run lint` | ESLint |
| `npm run typecheck` | `tsc --noEmit` |
| `npm test` | Vitest, une passe |
| `npm run test:coverage` | Vitest + couverture v8 (`coverage.all: true`) |

Stratégie de test : [`docs/fr/testing/web.md`](../docs/fr/testing/web.md).

## Stack

Next.js 16 (App Router) · React 19 · TypeScript · Tailwind · shadcn/ui sur
Radix · Firebase Auth · Sentry.

Les versions exactes vivent dans [`package.json`](package.json), qui reste la
seule source à jour : ce paragraphe a annoncé « Next.js 13 » et « Node.js
18+ » jusqu'au 2026-11-13.
