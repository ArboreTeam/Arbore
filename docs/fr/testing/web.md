# Tests Web (front)

Le front web (Next.js, dossier `web/`) est testé avec **Vitest** (et non Jest) + Testing Library sur jsdom. La configuration vit dans `web/vitest.config.mts` et `web/vitest.setup.ts`.

## Outillage

- **Vitest** avec `@vitejs/plugin-react`, `vite-tsconfig-paths`, environnement `jsdom`, `globals: true`.
- **Testing Library** : `@testing-library/react` + `@testing-library/jest-dom` (importé via `web/vitest.setup.ts`).
- Scripts (`web/package.json`) : `test` = `vitest run`, `test:watch` = `vitest`, `test:coverage` = `vitest run --coverage`.

## Inventaire

| Fichier | Ce qu'il couvre |
|---|---|
| `web/lib/authService.test.ts` | **La connexion** (#725) : le cookie de session posé pour une heure en `SameSite=Lax` et **effacé** à la déconnexion, `signUp` qui rend l'utilisateur même si le backend refuse (le compte Firebase existe déjà), Google qui demande `prompt: select_account`, Apple qui demande les scopes `email` et `name`, l'upsert backend porteur du jeton, et que **tous** les appels visent `/api/backend` — jamais l'API directement, sinon la clé serait dans le bundle. |
| `web/lib/api.test.ts` | Le client API. Mocke `./authService`, stubbe `fetch`. Vérifie l'en-tête `Authorization`, la réécriture vers le proxy `/api/backend/...`, le parsing 2xx et `ApiError` sur non-2xx. |
| `web/middleware.test.ts` | La garde d'hôte et de session. Les deux sens de la protection croisée : l'atelier introuvable depuis `web.arbore.app`, et les pages applicatives introuvables depuis `generator.arbore.app`. |
| `web/lib/generator/depot.test.ts` | Le dépôt sur disque : écriture atomique, jeton de réservation, sérialisation des mutations, expiration. **Y compris qu'un dépôt de maillage n'efface pas la file des vignettes** — une clé absente de `lire()` serait perdue au premier dépôt. |
| `web/lib/generator/session.test.ts` | Cookies signés, durée, attributs. |
| `web/lib/generator/limite.test.ts` | Anti-force-brute de la porte de l'atelier. |
| `web/lib/generator/config.test.ts` | Empreintes de clés acceptées, environnements déclarés, repli de `apiInterne` sur `api`. |
| `web/lib/generator/pot.test.ts`, `profil.test.ts` | Règles de pot et profil botanique. |
| `web/app/api/generator/*.test.ts` | Les routes de l'atelier : artefacts, pots, sources, et le câblage des routes. |
| `web/components/shared/SectionTitle.test.tsx` | Rendu du composant. |

**280 tests sur 14 fichiers** au 2026-11-03. Ce document n'en listait que
**deux** jusque-là, et annonçait qu'aucun job CI ne les exécutait.

## Exécution

```sh
cd web && npm install
cd web && npm test            # vitest run
cd web && npm run test:watch  # mode watch
cd web && npm run typecheck   # tsc --noEmit
```

## Limites connues

- **Un job CI web existe** depuis que ce document a été écrit : `🌱 Web (Next.js)` dans `.github/workflows/ci.yml`. Il enchaîne `npm run typecheck`, `npm run lint` puis les tests, et ne se déclenche que si `web/**` a changé — d'où son `skipped` sur les PR qui n'y touchent pas.
- `npm run test:coverage` **fonctionne** depuis le 2026-11-03 : le provider `@vitest/coverage-v8` est en `devDependencies`, et le job CI l'exécute. Jusque-là la commande échouait faute de provider.
- La configuration pose **`coverage.all: true`**, et ce n'est pas un détail. Sans lui, v8 ne compte que les fichiers que les tests **chargent** : les 140 fichiers qu'aucun test n'importe sortent du dénominateur, et le rapport annonce **91,64 %** pour une couverture réelle de **32,5 %** (1 237 / 3 811 instructions, mesuré le 2026-11-03 ; `.github/couverture-planchers.json` fait foi). Un chiffre faux dans ce sens-là est pire que pas de chiffre.
- **Aucun seuil** n'est configuré, délibérément : on veut d'abord voir le chiffre bouger à chaque PR. Voir #725.
- La couverture est **profonde sur l'atelier** et **mince sur les pages applicatives**. Mesurée, par dossier :

  ```
   100.0%   63/63    lib/authService.ts
     0.0%    0/451   app/garden
     0.0%    0/712   components/ui
    42.9%  211/492   app/api
    91.7%  901/983   lib/generator
    93.8%   45/48    middleware.ts
  ```

  C'est le vrai manque, et il suit là où le travail est allé. `lib/authService.ts` était le plus exposé — `signUp`, `login`, `signInWithGoogle`, `signInWithApple` et l'upsert du compte backend, pour 63 instructions et **zéro test**. Il est à **100 %** depuis le 2026-11-03 (#725). Le volume restant est dans les pages et les primitives d'interface.
