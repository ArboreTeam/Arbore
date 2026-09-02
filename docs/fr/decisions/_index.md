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

L'immuabilité porte sur la **décision**, pas sur sa mise en forme.

**Le raisonnement est figé.** Une fois passé en statut `Accepted`, le contexte, la décision, ses conséquences et les alternatives écartées d'un ADR ne sont jamais réécrits. Si une décision évolue, un nouvel ADR est créé et **supersede** explicitement l'ancien (dont le statut devient `Superseded by 0XXX`). Si un ADR contient une erreur de raisonnement ou un constat faux, on crée un ADR de correction plutôt que de réécrire l'ancien. Cette discipline garantit la traçabilité historique des choix.

**Les références au code peuvent être rafraîchies.** Un nom de fonction, de fichier ou de symbole cité dans un ADR peut être mis à jour lorsqu'un renommage ultérieur le rend introuvable, à trois conditions : la décision reste inchangée, la mention du nom d'origine est conservée, et la mise à jour est justifiée dans le message de commit.

La raison de cette nuance : un ADR n'est utile que s'il reste **navigable**. Un lecteur qui cherche `CheckUserBannedFunc` dans le code et ne le trouve nulle part n'apprend rien de l'histoire du projet — il perd du temps, puis se met à douter du reste du document. Créer un ADR entier pour acter un renommage serait par ailleurs disproportionné, et diluerait l'index sous des entrées sans portée architecturale.

## Index

| # | Titre | Statut | Sujet |
|---|---|---|---|
| [0001](0001-mermaid-for-docs.md) | Mermaid + sémantique C4 portée par flowchart | Accepted (2026-05-10) | Choix d'outillage documentaire |
| [0002](0002-scan-stacks.md) | Stack de scan double : RoomPlan (LiDAR) + tracé périmètre (non-LiDAR) | Accepted (2026-04-15) | AR / capture spatiale |
| [0003](0003-relocation-strategy.md) | Relocalisation ARWorldMap + fallback manual replace | Accepted (2026-04-29) | AR / persistance session |
| [0004](0004-firebase-auth.md) | Firebase Auth comme provider d'authentification | Accepted (2026-01-20) | Authentification |
| [0005](0005-self-authz-pattern.md) | Self-authz via token uid (pas d'uid dans l'URL) | Accepted (2026-05-10) | Sécurité backend |
| [0006](0006-ar-quality-adaptive.md) | Stratégie adaptative de qualité AR (`environmentTexturing` + thermal observer) | Accepted (2026-05-12) | AR / perf / thermal |
| [0007](0007-roles-and-entitlements.md) | Rôles (RBAC) séparés des niveaux d'abonnement (entitlements) | Accepted (2026-09-01) | Sécurité backend / autorisation |

## Pourquoi des ADRs

Les ADRs servent trois publics :

- **Les nouveaux contributeurs** : comprendre les choix existants évite de les remettre en question sans raison ou, à l'inverse, de les contourner par méconnaissance.
- **Les revues d'architecture** : un ADR documenté est plus rapide à challenger qu'une décision tacite.
- **L'examinateur externe (jury Epitech)** : la présence d'ADRs démontre la maturité d'architecte et la capacité à expliciter les compromis.

Tous les ADRs de ce dépôt sont volontairement courts (une page maximum) afin d'être effectivement lus et maintenus.
