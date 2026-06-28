# Architecture Decision Records (ADRs)

Cette section regroupe les **décisions d'architecture** prises au fil du projet, au format **MADR** (Markdown Architectural Decision Records).

## Format

Chaque ADR suit la structure suivante :

1. **Statut** — `Proposed`, `Accepted`, `Deprecated`, `Superseded by [n]`. La date d'acceptation est précisée.
2. **Contexte** — le problème à résoudre et les contraintes qui pèsent sur la décision.
3. **Décision** — le choix retenu, exprimé à la voix active.
4. **Conséquences** — les effets positifs, négatifs et neutres du choix.
5. **Alternatives considérées** — les options qui ont été évaluées et écartées, avec la raison de l'écart.

Le format complet est documenté sur [adr.github.io/madr](https://adr.github.io/madr/).

## Convention de nommage

Les ADRs sont numérotés à partir de `0001` et nommés en `kebab-case` :

```
0001-mermaid-for-docs.md
0002-scan-stacks.md
0003-relocation-strategy.md
...
```

## Immutabilité

Une fois passé en statut `Accepted`, **un ADR n'est jamais modifié**. Si une décision évolue, un nouvel ADR est créé et il **supersede** explicitement l'ancien (le statut de l'ancien devient `Superseded by 0XXX`). Cette discipline garantit la traçabilité historique des choix.

Cette règle s'applique également si l'on découvre une erreur factuelle dans un ADR existant : on crée un nouvel ADR de correction plutôt que d'éditer l'ancien.

## Index

| # | Titre | Statut | Sujet |
|---|---|---|---|
| [0001](0001-mermaid-for-docs.md) | Mermaid + sémantique C4 portée par flowchart | Accepted (2026-05-10) | Choix d'outillage documentaire |
| [0002](0002-scan-stacks.md) | Stack de scan double : RoomPlan (LiDAR) + tracé périmètre (non-LiDAR) | Accepted (2026-04-15) | AR / capture spatiale |
| [0003](0003-relocation-strategy.md) | Relocalisation ARWorldMap + fallback manual replace | Accepted (2026-04-29) | AR / persistance session |
| [0004](0004-firebase-auth.md) | Firebase Auth comme provider d'authentification | Accepted (2026-01-20) | Authentification |
| [0005](0005-self-authz-pattern.md) | Self-authz via token uid (pas d'uid dans l'URL) | Accepted (2026-05-10) | Sécurité backend |
| [0006](0006-ar-quality-adaptive.md) | Stratégie adaptative de qualité AR (`environmentTexturing` + thermal observer) | Accepted (2026-05-12) | AR / perf / thermal |

## Pourquoi des ADRs

Les ADRs servent trois publics :

- **Les nouveaux contributeurs** : comprendre les choix existants évite de les remettre en question sans raison ou, à l'inverse, de les contourner par méconnaissance.
- **Les revues d'architecture** : un ADR documenté est plus rapide à challenger qu'une décision tacite.
- **L'examinateur externe (jury Epitech)** : la présence d'ADRs démontre la maturité d'architecte et la capacité à expliciter les compromis.

Tous les ADRs de ce dépôt sont volontairement courts (une page maximum) afin d'être effectivement lus et maintenus.
