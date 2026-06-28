# Tests Web (front)

Le front web (Next.js, dossier `web/`) est testé avec **Vitest** (et non Jest) + Testing Library sur jsdom. La configuration vit dans `web/vitest.config.mts` et `web/vitest.setup.ts`.

## Outillage

- **Vitest** avec `@vitejs/plugin-react`, `vite-tsconfig-paths`, environnement `jsdom`, `globals: true`.
- **Testing Library** : `@testing-library/react` + `@testing-library/jest-dom` (importé via `web/vitest.setup.ts`).
- Scripts (`web/package.json`) : `test` = `vitest run`, `test:watch` = `vitest`, `test:coverage` = `vitest run --coverage`.

## Inventaire

| Fichier | Couvre |
|---|---|
| `web/lib/api.test.ts` | Le client API (`web/lib/api.ts`). Mocke `./authService` (pas d'init Firebase, `getFirebaseToken` → `TEST_TOKEN`) et stubbe `fetch`. Vérifie que `fetchWithAuth` ajoute `Authorization: Bearer TEST_TOKEN` + `Content-Type: application/json` et réécrit les URLs vers le proxy `/api/backend/...` ; que `apiGet` parse le JSON sur 2xx et lève `ApiError` sur non-2xx (403) ; que `apiSend` sérialise le corps et pose la méthode. |
| `web/components/shared/SectionTitle.test.tsx` | Rendu de `<SectionTitle>` (titre depuis les enfants, affichage du `subtitle` quand fourni, aucun sous-titre par défaut). |

## Exécution

```sh
cd web && npm install
cd web && npm test            # vitest run
cd web && npm run test:watch  # mode watch
cd web && npm run typecheck   # tsc --noEmit
```

## Limites connues

- **Pas de job CI web** : aucun workflow GitHub Actions n'exécute Vitest à ce jour — les tests web tournent **localement**. C'est un axe d'amélioration suivi.
- `npm run test:coverage` invoque `--coverage` mais **aucun provider** (`@vitest/coverage-v8`) n'est encore en `devDependencies` ; aucun seuil de couverture n'est configuré.
- La couverture fonctionnelle est aujourd'hui ciblée (client API + un composant partagé) ; l'élargissement aux pages applicatives (catalogue, jardin, calendrier) est un chantier ouvert.
