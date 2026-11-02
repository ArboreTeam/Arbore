# Tests Web (front)

Le front web (Next.js, dossier `web/`) est testé avec **Vitest** (et non Jest) + Testing Library sur jsdom. La configuration vit dans `web/vitest.config.mts` et `web/vitest.setup.ts`.

## Outillage

- **Vitest** avec `@vitejs/plugin-react`, `vite-tsconfig-paths`, environnement `jsdom`, `globals: true`.
- **Testing Library** : `@testing-library/react` + `@testing-library/jest-dom` (importé via `web/vitest.setup.ts`).
- Scripts (`web/package.json`) : `test` = `vitest run`, `test:watch` = `vitest`, `test:coverage` = `vitest run --coverage`.

## Inventaire

| Fichier | Ce qu'il couvre |
|---|---|
| `web/lib/api.test.ts` | Le client API. Mocke `./authService`, stubbe `fetch`. Vérifie l'en-tête `Authorization`, la réécriture vers le proxy `/api/backend/...`, le parsing 2xx et `ApiError` sur non-2xx. |
| `web/middleware.test.ts` | La garde d'hôte et de session. Les deux sens de la protection croisée : l'atelier introuvable depuis `web.arbore.app`, et les pages applicatives introuvables depuis `generator.arbore.app`. |
| `web/lib/generator/depot.test.ts` | Le dépôt sur disque : écriture atomique, jeton de réservation, sérialisation des mutations, expiration. **Y compris qu'un dépôt de maillage n'efface pas la file des vignettes** — une clé absente de `lire()` serait perdue au premier dépôt. |
| `web/lib/generator/session.test.ts` | Cookies signés, durée, attributs. |
| `web/lib/generator/limite.test.ts` | Anti-force-brute de la porte de l'atelier. |
| `web/lib/generator/config.test.ts` | Empreintes de clés acceptées, environnements déclarés, repli de `apiInterne` sur `api`. |
| `web/lib/generator/pot.test.ts`, `profil.test.ts` | Règles de pot et profil botanique. |
| `web/app/api/generator/*.test.ts` | Les routes de l'atelier : artefacts, pots, sources, et le câblage des routes. |
| `web/components/shared/SectionTitle.test.tsx` | Rendu du composant. |

**256 tests sur 13 fichiers** au 2026-11-02. Ce document n'en listait que
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
- `npm run test:coverage` invoque `--coverage` mais **aucun provider** (`@vitest/coverage-v8`) n'est en `devDependencies` : vérifié le 2026-11-02, la commande échouerait. Aucun seuil de couverture n'est configuré.
- La couverture est **profonde sur l'atelier** (dépôt, session, anti-force-brute, configuration, routes) et **mince sur les pages applicatives** : catalogue, jardin et calendrier n'ont aucun test. C'est le vrai manque, et il suit là où le travail est allé.
