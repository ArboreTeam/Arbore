# Architecture Decision Records (ADRs)

This section gathers the **architecture decisions** made over the course of the project, in the **MADR** (Markdown Architectural Decision Records) format.

## Format

Each ADR follows this structure:

1. **Status** — `Proposed`, `Accepted`, `Deprecated`, `Superseded by [n]`. The acceptance date is specified.
2. **Context** — the problem to be solved and the constraints bearing on the decision.
3. **Decision** — the chosen option, stated in the active voice.
4. **Consequences** — the positive, negative, and neutral effects of the choice.
5. **Considered alternatives** — the options that were evaluated and discarded, along with the reason for discarding them.

The full format is documented at [adr.github.io/madr](https://adr.github.io/madr/).

## Naming convention

ADRs are numbered starting from `0001` and named in `kebab-case`:

```
0001-mermaid-for-docs.md
0002-scan-stacks.md
0003-relocation-strategy.md
...
```

## Immutability

Once it reaches the `Accepted` status, **an ADR is never modified**. If a decision evolves, a new ADR is created that explicitly **supersedes** the old one (the old one's status becomes `Superseded by 0XXX`). This discipline ensures the historical traceability of choices.

This rule also applies when a factual error is discovered in an existing ADR: a new corrective ADR is created rather than editing the old one.

## Index

| # | Title | Status | Subject |
|---|---|---|---|
| [0001](0001-mermaid-for-docs.md) | Mermaid + C4 semantics carried by flowchart | Accepted (2026-05-10) | Documentation tooling choice |
| [0002](0002-scan-stacks.md) | Dual scan stack: RoomPlan (LiDAR) + perimeter tracing (non-LiDAR) | Accepted (2026-04-15) | AR / spatial capture |
| [0003](0003-relocation-strategy.md) | ARWorldMap relocalization + manual replace fallback | Accepted (2026-04-29) | AR / session persistence |
| [0004](0004-firebase-auth.md) | Firebase Auth as the authentication provider | Accepted (2026-01-20) | Authentication |
| [0005](0005-self-authz-pattern.md) | Self-authz via token uid (no uid in the URL) | Accepted (2026-05-10) | Backend security |
| [0006](0006-ar-quality-adaptive.md) | Adaptive AR quality strategy (`environmentTexturing` + thermal observer) | Accepted (2026-05-12) | AR / perf / thermal |

## Why ADRs

ADRs serve three audiences:

- **New contributors**: understanding existing choices prevents questioning them for no reason or, conversely, working around them out of ignorance.
- **Architecture reviews**: a documented ADR is faster to challenge than a tacit decision.
- **The external examiner (Epitech jury)**: the presence of ADRs demonstrates architectural maturity and the ability to make trade-offs explicit.

All ADRs in this repository are intentionally short (one page maximum) so that they are actually read and maintained.
