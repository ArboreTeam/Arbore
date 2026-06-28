# Arbore — Documentation

Technical documentation for Arbore, an AR gardening application (iOS app + Next.js web companion + Go backend + Python AI generator). Written in **Markdown + Mermaid** so it lives next to the source code and renders natively on GitHub.

This documentation is **bilingual**. French is the source of truth; English is a full mirror.

| Langue / Language | Entrée / Entry point |
|---|---|
| 🇫🇷 **Français** (référence) | **[`fr/README.md`](fr/README.md)** |
| 🇬🇧 **English** (mirror) | **[`en/README.md`](en/README.md)** |

## What's inside / Au sommaire

Both language trees share the same structure:

| Vue / View | 🇫🇷 | 🇬🇧 |
|---|---|---|
| C4 — Context, Containers, Components, Data model | [`fr/architecture/`](fr/architecture/) | [`en/architecture/`](en/architecture/) |
| Dynamic flows (signup, garden creation, AR placement) | [`fr/flows/`](fr/flows/) | [`en/flows/`](en/flows/) |
| Behavioural state machines | [`fr/state-machines/`](fr/state-machines/) | [`en/state-machines/`](en/state-machines/) |
| Per-screen specs (hero screens) | [`fr/screens/`](fr/screens/) | [`en/screens/`](en/screens/) |
| Testing strategy (front + back + web) | [`fr/testing/`](fr/testing/) | [`en/testing/`](en/testing/) |
| Operations (deploy, observability, VPS) | [`fr/operations/`](fr/operations/) | [`en/operations/`](en/operations/) |
| Architecture Decision Records (MADR) | [`fr/decisions/`](fr/decisions/) | [`en/decisions/`](en/decisions/) |
| 3D model LOD architecture | [`fr/3d-lod-architecture.md`](fr/3d-lod-architecture.md) | [`en/3d-lod-architecture.md`](en/3d-lod-architecture.md) |
| Glossary | [`fr/glossary.md`](fr/glossary.md) | [`en/glossary.md`](en/glossary.md) |

Language-neutral reference (multilingual App Store copy): [`appstore-listing.md`](appstore-listing.md). Historical notes kept out of scope: [`legacy/`](legacy/).

## Contributing / Contribuer

- **Update both languages in the same PR.** French is authoritative; the English mirror must stay at parity. Authoring rules and the CI contract are documented in each language's index ([`fr/README.md`](fr/README.md) · [`en/README.md`](en/README.md)).
- A PR touching `docs/**` (or Swift/Go sources cited by the docs) triggers `.github/workflows/docs.yml`, which validates **Mermaid syntax**, **internal links** (lychee), and **code-path drift**. Reproduce the drift check locally with:

```sh
bash .github/scripts/docs-drift-check.sh
```
