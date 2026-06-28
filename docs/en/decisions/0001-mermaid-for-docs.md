# ADR 0001 — Mermaid + C4 semantics carried by flowchart

- **Status**: Accepted
- **Date**: 2026-05-10
- **Deciders**: Arbore team

## Context

The application's technical documentation must be versioned in the Git repository, rendered automatically on GitHub, and remain understandable by any new contributor. Several options were evaluated when structuring `docs/` (see issue #141):

- **Mermaid** — text-based, native GitHub rendering, diff-able like code.
- **PlantUML** — text-based, more complete than Mermaid for UML diagrams, but does not render natively on GitHub (requires an external service or pre-generated SVGs).
- **Structurizr DSL** — a DSL dedicated to C4 architecture, generates PlantUML, requires a dedicated build tool.
- **Figma** — clean visuals, shared by the Design team, but outside the Git flow.

Regarding the **C4 model** specifically, two syntax options exist in Mermaid:

1. The native `C4Context` / `C4Container` / `C4Component` syntax.
2. The `flowchart` syntax with labels prefixed `[Person]`, `[Container]`, `[System Ext]`, etc.

The native syntax is officially marked [`experimental`](https://mermaid.js.org/syntax/c4.html) at the time of writing (Mermaid v11+). It produces **edge overlaps** on dense graphs, and does not support the `Lay_U/D/L/R` directives that would allow fine-grained layout control.

Native GitHub **does not support** the alternative ELK renderer (see [github/community#138426](https://github.com/orgs/community/discussions/138426)) which would solve some of these problems — the EUPL license of the ELK package appears to be the blocker. This rules out ELK for portable documentation.

## Decision

The `docs/` documentation uses **Mermaid** as its single diagramming tool, embedded in Markdown files. **FigJam** remains used as a complement for non-technical communication (jury presentation, UX brainstorming) but is not the dev source of truth.

The **C4 model semantics** are carried by `flowchart TB` diagrams with labels prefixed `[Person]`, `[Container]`, `[System Ext]` rather than by Mermaid's native `C4Context` / `C4Container` syntax. The `flowchart` layout engine (Dagre) is mature, handles dense graphs correctly, and is still rendered natively by GitHub. The C4 semantics remain intact — they are carried by the label, not by the syntax.

## Consequences

### Positive

- All documentation lives in the repository and benefits from the usual Git flow (PR, review, blame, history).
- No external tooling dependency — no diagram generation service to maintain.
- Contributors have nothing to install in order to read or edit the documentation.
- The documentation tone is consistent with the code tone (both are read in the same IDE).
- The `flowchart` layout engine has been stable for a long time and does not break between Mermaid versions.

### Negative

- Complex `flowchart` diagrams lose the **nested rectangles** that the `C4Container` syntax could have provided. Layering is conveyed through CSS classes (color-coding) rather than visual boxes.
- Part of the academic rigor of the C4 model (notably the level-by-level invariance of relationships) now relies on the author's discipline rather than on the tool.

### Neutral

- If Mermaid C4 ever leaves its `experimental` status and supports a better layout, migration from `flowchart` remains possible — it suffices to change the syntax of the affected diagrams without renaming the files.
- The absence of ELK on GitHub is treated as a permanent constraint. If GitHub changes its mind, we can reconsider this decision in a successor ADR.

## Alternatives considered

- **PlantUML** — discarded because it does not render natively on GitHub. It would have required pre-generating SVGs in the repository and regenerating them on every change — additional friction for contributors.
- **Structurizr DSL** — discarded for the same kind of reason (a build tool to add to CI) and because pure C4 rigor is superfluous for the team's size (five people).
- **Figma as source of truth** — discarded because it is not versioned in Git and impossible to diff. It remains used in parallel for design communication.
- **Native Mermaid `C4Context`** — tested and then discarded after two iterations that highlighted systematic edge overlaps on our graphs (see PR #142 and #143). Switching to `flowchart` resolved the problem immediately.

## Links

- [Mermaid — Flowcharts Syntax](https://mermaid.js.org/syntax/flowchart.html)
- [Mermaid — C4 Diagrams (experimental)](https://mermaid.js.org/syntax/c4.html)
- [GitHub Community Discussion #138426 — ELK not supported](https://github.com/orgs/community/discussions/138426)
- [Issue #141 — documentation plan](https://github.com/ArboreTeam/Arbore/issues/141)
