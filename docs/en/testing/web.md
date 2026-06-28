# Web Tests (front)

The web front (Next.js, `web/` directory) is tested with **Vitest** (not Jest) + Testing Library on jsdom. The configuration lives in `web/vitest.config.mts` and `web/vitest.setup.ts`.

## Tooling

- **Vitest** with `@vitejs/plugin-react`, `vite-tsconfig-paths`, `jsdom` environment, `globals: true`.
- **Testing Library**: `@testing-library/react` + `@testing-library/jest-dom` (imported via `web/vitest.setup.ts`).
- Scripts (`web/package.json`): `test` = `vitest run`, `test:watch` = `vitest`, `test:coverage` = `vitest run --coverage`.

## Inventory

| File | Covers |
|---|---|
| `web/lib/api.test.ts` | The API client (`web/lib/api.ts`). Mocks `./authService` (no Firebase init, `getFirebaseToken` → `TEST_TOKEN`) and stubs `fetch`. Verifies that `fetchWithAuth` adds `Authorization: Bearer TEST_TOKEN` + `Content-Type: application/json` and rewrites URLs to the `/api/backend/...` proxy; that `apiGet` parses the JSON on 2xx and throws `ApiError` on non-2xx (403); that `apiSend` serializes the body and sets the method. |
| `web/components/shared/SectionTitle.test.tsx` | Rendering of `<SectionTitle>` (title from children, display of the `subtitle` when provided, no subtitle by default). |

## Execution

```sh
cd web && npm install
cd web && npm test            # vitest run
cd web && npm run test:watch  # watch mode
cd web && npm run typecheck   # tsc --noEmit
```

## Known limitations

- **No web CI job**: no GitHub Actions workflow runs Vitest to date — web tests run **locally**. This is a tracked area for improvement.
- `npm run test:coverage` invokes `--coverage` but **no provider** (`@vitest/coverage-v8`) is yet in `devDependencies`; no coverage threshold is configured.
- Functional coverage is currently targeted (API client + one shared component); expanding it to the application pages (catalog, garden, calendar) is an open task.
