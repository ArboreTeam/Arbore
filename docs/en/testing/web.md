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
- `npm run test:coverage` **works** as of 2026-11-03: the `@vitest/coverage-v8` provider is in `devDependencies`, and the CI job runs it. Until then the command failed for want of a provider.
- The configuration sets **`coverage.all: true`**, and that is not a detail. Without it, v8 only counts the files the tests **load**: the 140 files no test imports drop out of the denominator, and the report claims **91.64%** for a real coverage of **30.8%** (1,174 / 3,811 statements, measured on 2026-11-03). A number wrong in that direction is worse than no number.
- **No threshold** is configured, deliberately: we want to see the number move on every PR first. See #725.
- Coverage is **deep on the workshop** and **thin on the application pages**. Measured, by directory:

  ```
     0.0%    0/63    lib/authService.ts
     0.0%    0/451   app/garden
     0.0%    0/712   components/ui
    42.9%  211/492   app/api
    91.7%  901/983   lib/generator
    93.8%   45/48    middleware.ts
  ```

  That is the real gap, and it follows where the work went. The most exposed is not the volume but `lib/authService.ts`: it carries `signUp`, `login`, `signInWithGoogle`, `signInWithApple` and the backend account upsert, in **63 statements with zero tests**.
