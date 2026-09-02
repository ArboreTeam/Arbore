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

Immutability covers the **decision**, not its wording.

**The reasoning is frozen.** Once it reaches the `Accepted` status, an ADR's context, decision, consequences and rejected alternatives are never rewritten. If a decision evolves, a new ADR is created that explicitly **supersedes** the old one (whose status becomes `Superseded by 0XXX`). If an ADR contains a flawed argument or a false premise, a corrective ADR is created rather than rewriting the old one. This discipline ensures the historical traceability of choices.

**Code references may be refreshed.** A function, file or symbol name quoted in an ADR may be updated when a later rename makes it impossible to find, under three conditions: the decision itself is unchanged, the original name is kept alongside, and the update is justified in the commit message.

The reason for this nuance: an ADR is only useful if it stays **navigable**. A reader who searches the codebase for `CheckUserBannedFunc` and finds it nowhere learns nothing about the project's history — they lose time, then start doubting the rest of the document. Creating a whole ADR to record a rename would also be disproportionate, and would dilute the index with entries that carry no architectural weight.

## Index

| # | Title | Status | Subject |
|---|---|---|---|
| [0001](0001-mermaid-for-docs.md) | Mermaid + C4 semantics carried by flowchart | Accepted (2026-05-10) | Documentation tooling choice |
| [0002](0002-scan-stacks.md) | Dual scan stack: RoomPlan (LiDAR) + perimeter tracing (non-LiDAR) | Accepted (2026-04-15) | AR / spatial capture |
| [0003](0003-relocation-strategy.md) | ARWorldMap relocalization + manual replace fallback | Accepted (2026-04-29) | AR / session persistence |
| [0004](0004-firebase-auth.md) | Firebase Auth as the authentication provider | Accepted (2026-01-20) | Authentication |
| [0005](0005-self-authz-pattern.md) | Self-authz via token uid (no uid in the URL) | Accepted (2026-05-10) | Backend security |
| [0006](0006-ar-quality-adaptive.md) | Adaptive AR quality strategy (`environmentTexturing` + thermal observer) | Accepted (2026-05-12) | AR / perf / thermal |
| [0007](0007-roles-and-entitlements.md) | Roles (RBAC) kept separate from subscription entitlements | Accepted (2026-09-01) | Backend security / authorization |

## Why ADRs

ADRs serve three audiences:

- **New contributors**: understanding existing choices prevents questioning them for no reason or, conversely, working around them out of ignorance.
- **Architecture reviews**: a documented ADR is faster to challenge than a tacit decision.
- **The external examiner (Epitech jury)**: the presence of ADRs demonstrates architectural maturity and the ability to make trade-offs explicit.

All ADRs in this repository are intentionally short (one page maximum) so that they are actually read and maintained.
