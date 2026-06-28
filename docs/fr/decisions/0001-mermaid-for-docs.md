# ADR 0001 — Mermaid + sémantique C4 portée par flowchart

- **Statut** : Accepted
- **Date** : 2026-05-10
- **Décideurs** : Équipe Arbore

## Contexte

La documentation technique de l'application doit être versionnée dans le dépôt Git, rendue automatiquement sur GitHub, et rester compréhensible par tout nouveau contributeur. Plusieurs options ont été évaluées au moment de structurer `docs/` (cf. issue #141) :

- **Mermaid** — text-based, rendu natif GitHub, diff-able comme du code.
- **PlantUML** — text-based, plus complet que Mermaid sur les diagrammes UML, mais ne rend pas nativement sur GitHub (requiert un service externe ou des SVG pré-générés).
- **Structurizr DSL** — DSL dédié à l'architecture C4, génère du PlantUML, demande un outil de build dédié.
- **Figma** — visuel propre, partagé par l'équipe Design, mais hors du flux Git.

Concernant le **modèle C4** spécifiquement, deux options de syntaxe existent dans Mermaid :

1. La syntaxe native `C4Context` / `C4Container` / `C4Component`.
2. La syntaxe `flowchart` avec des labels préfixés `[Person]`, `[Container]`, `[System Ext]`, etc.

La syntaxe native est officiellement marquée [`experimental`](https://mermaid.js.org/syntax/c4.html) au moment de la rédaction (Mermaid v11+). Elle produit des **chevauchements d'arêtes** sur les graphes denses, et ne supporte pas les directives `Lay_U/D/L/R` qui permettraient un contrôle de layout fin.

GitHub natif **ne supporte pas** le renderer alternatif ELK (cf. [github/community#138426](https://github.com/orgs/community/discussions/138426)) qui résoudrait certains de ces problèmes — la licence EUPL du package ELK semble être le bloqueur. Cela élimine ELK pour de la doc portable.

## Décision

La documentation `docs/` utilise **Mermaid** comme outil de diagramme unique, intégré dans des fichiers Markdown. **FigJam** reste utilisé en complément pour la communication non-technique (présentation jury, brainstorming UX) mais n'est pas la source de vérité dev.

La **sémantique du modèle C4** est portée par des diagrammes `flowchart TB` avec des labels préfixés `[Person]`, `[Container]`, `[System Ext]` plutôt que par la syntaxe `C4Context` / `C4Container` native de Mermaid. Le moteur de layout `flowchart` (Dagre) est mature, gère correctement les graphes denses, et reste rendu nativement par GitHub. La sémantique C4 reste intacte — elle est portée par le label, pas par la syntaxe.

## Conséquences

### Positives

- Toute la documentation vit dans le dépôt et bénéficie du flux Git habituel (PR, review, blame, history).
- Aucune dépendance d'outillage externe — pas de service de génération de diagrammes à maintenir.
- Les contributeurs n'ont aucune installation à faire pour lire ou modifier la documentation.
- Le ton documentaire est cohérent avec le ton du code (les deux sont lus dans le même IDE).
- Le moteur de layout `flowchart` est stable depuis longtemps et ne casse pas entre versions Mermaid.

### Négatives

- Les diagrammes complexes en `flowchart` perdent les **rectangles imbriqués** que la syntaxe `C4Container` aurait pu fournir. Le découpage par couches est porté par des classes CSS (color-coding) plutôt que par des boxes visuelles.
- Une partie de la rigueur académique du modèle C4 (notamment l'invariance des relations niveau par niveau) repose désormais sur la discipline de l'auteur, pas sur l'outil.

### Neutres

- Si Mermaid C4 sort un jour de son statut `experimental` et supporte un meilleur layout, la migration depuis `flowchart` reste possible — il suffit de changer la syntaxe des diagrammes concernés sans renommer les fichiers.
- L'absence d'ELK sur GitHub est traitée comme une contrainte permanente. Si GitHub change d'avis, on pourra reconsidérer cette décision dans un ADR de successeur.

## Alternatives considérées

- **PlantUML** — écarté car ne rend pas nativement sur GitHub. Aurait nécessité de pré-générer des SVG dans le dépôt et de les régénérer à chaque modification — friction supplémentaire pour les contributeurs.
- **Structurizr DSL** — écarté pour le même type de raison (outil de build à ajouter à la CI) et parce que la rigueur C4 pure est superflue pour la taille de l'équipe (cinq personnes).
- **Figma comme source de vérité** — écarté car non-versionné dans Git et impossible à diff. Reste utilisé en parallèle pour la communication design.
- **`C4Context` native Mermaid** — testée puis écartée après deux itérations qui ont mis en évidence des chevauchements d'arêtes systématiques sur nos graphes (cf. PR #142 et #143). Le passage en `flowchart` a résolu le problème immédiatement.

## Liens

- [Mermaid — Flowcharts Syntax](https://mermaid.js.org/syntax/flowchart.html)
- [Mermaid — C4 Diagrams (experimental)](https://mermaid.js.org/syntax/c4.html)
- [GitHub Community Discussion #138426 — ELK not supported](https://github.com/orgs/community/discussions/138426)
- [Issue #141 — plan de documentation](https://github.com/ArboreTeam/Arbore/issues/141)
