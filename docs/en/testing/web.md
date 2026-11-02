# Web Tests (front)

The web front (Next.js, `web/` directory) is tested with **Vitest** (not Jest) + Testing Library on jsdom. The configuration lives in `web/vitest.config.mts` and `web/vitest.setup.ts`.

## Tooling

- **Vitest** with `@vitejs/plugin-react`, `vite-tsconfig-paths`, `jsdom` environment, `globals: true`.
- **Testing Library**: `@testing-library/react` + `@testing-library/jest-dom` (imported via `web/vitest.setup.ts`).
- Scripts (`web/package.json`): `test` = `vitest run`, `test:watch` = `vitest`, `test:coverage` = `vitest run --coverage`.

## Inventory

| File | What it covers |
|---|---|
| `web/lib/api.test.ts` | The API client. Mocks `./authService`, stubs `fetch`. Checks the `Authorization` header, rewriting to the `/api/backend/...` proxy, 2xx parsing and `ApiError` on non-2xx. |
| `web/middleware.test.ts` | Host and session guarding. Both directions of the cross protection: the workshop unreachable from `web.arbore.app`, and the app pages unreachable from `generator.arbore.app`. |
| `web/lib/generator/depot.test.ts` | The on-disk store: atomic writes, reservation token, serialised mutations, expiry. **Including that depositing a mesh does not wipe the thumbnail queue** — a key missing from `lire()` would be lost on the first deposit. |
| `web/lib/generator/session.test.ts` | Signed cookies, lifetime, attributes. |
| `web/lib/generator/limite.test.ts` | Brute-force protection on the workshop door. |
| `web/lib/generator/config.test.ts` | Accepted key fingerprints, declared environments, `apiInterne` falling back to `api`. |
| `web/lib/generator/pot.test.ts`, `profil.test.ts` | Pot rules and botanical profile. |
| `web/app/api/generator/*.test.ts` | The workshop routes: artefacts, pots, sources, and route wiring. |
| `web/components/shared/SectionTitle.test.tsx` | Component rendering. |

**256 tests across 13 files** as of 2026-11-02. This document listed only
**two** until then, and claimed no CI job ran them.

## Execution

```sh
cd web && npm install
cd web && npm test            # vitest run
cd web && npm run test:watch  # watch mode
cd web && npm run typecheck   # tsc --noEmit
```

## Known limitations

- **A web CI job does exist**, added after this document was written: `🌱 Web (Next.js)` in `.github/workflows/ci.yml`. It chains `npm run typecheck`, `npm run lint` and then the tests, and only fires when `web/**` changed — hence the `skipped` on PRs that do not touch it.
- `npm run test:coverage` passes `--coverage` but **no provider** (`@vitest/coverage-v8`) is in `devDependencies`: verified on 2026-11-02, the command would fail. No coverage threshold is configured.
- Coverage is **deep on the workshop** (store, session, rate limiting, config, routes) and **thin on the application pages**: catalog, garden and calendar have no test. That is the real gap, and it follows where the work went.
