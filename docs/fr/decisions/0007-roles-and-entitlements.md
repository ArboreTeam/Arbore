# ADR 0007 — Rôles (RBAC) séparés des niveaux d'abonnement (entitlements)

- **Statut** : Accepted
- **Date** : 2026-09-01
- **Décideurs** : Équipe Arbore

## Contexte

Avant cette décision, l'autorisation reposait sur trois mécanismes disjoints : le booléen `users.banned`, le middleware `RequireAdmin()` lisant les custom claims Firebase avec repli sur `ARBORE_ADMIN_UIDS`, et un champ `tier` purement informatif servi par `GET /config` avec `membership.enforced = false`.

Trois besoins ont convergé : distinguer un utilisateur payant d'un utilisateur gratuit (prérequis de #4), permettre à terme un accès invité sans création de compte, et clarifier ce que recouvrent les notions d'administrateur et de compte de test.

La formulation initiale du besoin proposait un enum unique : `invited`, `free`, `premium`, `admin`, `test`. Deux constats relevés dans le code ont orienté la décision. D'une part la clé `ARBORE_API_KEY_TEST` ne contourne aucun rate limit — `rateLimitKey()` ne connaît que `uid:` et `ip:`, la clé ne fait que router vers la base de test. D'autre part aucun code du dépôt ne pose de custom claim Firebase, si bien que les administrateurs ne proviennent en pratique que de la variable d'environnement d'amorçage.

## Décision

**Deux axes d'autorisation distincts, jamais fusionnés en un enum unique.**

- `role` répond à « qu'as-tu le droit de faire ? » : `guest`, `member`, `admin`. `owner` et `support` sont réservés dans l'enum mais aucune route ne les distingue encore.
- `tier` répond à « qu'as-tu payé ? » : `free`, `premium`, accompagné de `tierSource` et `tierExpiresAt`.
- `banned` reste un troisième axe indépendant, inchangé.

Le rôle `guest` se déduit de `token.Firebase.SignInProvider == "anonymous"`, jamais d'un champ en base : un document Mongo est modifiable par son porteur, un claim signé par Firebase ne l'est pas.

**Aucun rôle `test` n'est créé.** Le besoin de quotas élargis pendant les tests est traité au niveau de l'environnement, via le sélecteur de base déjà présent en contexte, et non par un attribut porté par un compte.

Le profil d'autorisation est lu dans le `FindOne` que le middleware effectuait déjà pour le contrôle de bannissement, et déposé dans le contexte Gin.

## Conséquences

### Positives

- **Pas de produit cartésien.** Un administrateur peut être abonné, un invité pourra payer, sans que l'enum n'explose.
- **Aucun coût de lecture supplémentaire** : le `FindOne` par requête existait déjà. Lire le rôle en base plutôt que dans un claim évite aussi le délai de propagation d'une heure des custom claims.
- **Aucun backfill.** `NormalizeRole` et `NormalizeTier` replient toute valeur vide ou inconnue vers `member` / `free`, ce qui couvre l'intégralité des documents antérieurs.
- **Surface d'escalade fermée.** `POST /users` ne lie plus la structure `User` entière mais un payload restreint au seul `name`.
- **L'expiration d'abonnement est appliquée à la lecture**, sans dépendre du passage d'un job externe.

### Négatives

- **Deux champs à maintenir cohérents** entre MongoDB et les custom claims Firebase pour le rôle administrateur. La double source est assumée : le claim survit à une compromission de la base, c'est de la défense en profondeur.
- **Un changement de niveau en cours de fenêtre de quota** redonne un budget neuf, chaque classe ayant son propre compteur. Le sens de l'erreur est favorable au client qui vient de payer.
- **Les valeurs `guest` et `premium` restent inertes** tant qu'Anonymous Auth et la validation des reçus StoreKit ne sont pas branchées.

### Neutres

- Le repli par défaut est `member`, jamais `guest` : une lecture dégradée doit refuser l'accès aux routes d'administration, pas basculer un compte existant en accès invité.
- Le rôle `support`, réservé, n'est volontairement pas privilégié : c'est un accès en lecture, pas un accès d'administration.

## Alternatives considérées

- **Enum unique mêlant rôle et abonnement** — écarté : produit cartésien dès qu'un utilisateur cumule deux dimensions.
- **Rôle `test` contournant les rate limits** — écarté : un privilège porté par un compte est portable et exportable. Les identifiants d'un compte de test circulent par nature (plan de tests d'acceptation, jury), et le contournement porterait sur les routes qui appellent Gemini, donc qui coûtent de l'argent. La variante « clé pour se connecter, puis rôle qui contourne » est strictement moins sûre que l'existant : elle déplace le privilège de l'environnement vers le compte.
- **Identifiant d'invité propriétaire** — écarté au profit de Firebase Anonymous Auth. Un identifiant maison imposerait un chemin d'authentification parallèle au middleware existant, donc une seconde surface à sécuriser. Anonymous Auth fournit un uid et un token exploitables sans modification du middleware, et permet de lier ultérieurement le compte anonyme à un compte nominatif : l'invité qui s'inscrit conserve ses données.
- **Rôle porté uniquement par les custom claims Firebase** — écarté : le délai de propagation d'une heure rendrait toute rétrogradation lente, alors que la base est déjà lue à chaque requête.

## Liens

- [Issue #377 — Rôles utilisateur et tiers d'abonnement](https://github.com/ArboreTeam/Arbore/issues/377)
- [Issue #4 — Paiement : achat d'un abonnement](https://github.com/ArboreTeam/Arbore/issues/4)
- [Issue #336 — Monétisation : prérequis légaux et techniques](https://github.com/ArboreTeam/Arbore/issues/336)
- ADR 0004 — Firebase Auth (fournit le token dont le rôle `guest` est déduit)
- ADR 0005 — Self-authz via token uid (anticipait le besoin d'un rôle admin)
- [OWASP — Broken Function Level Authorization](https://owasp.org/API-Security/editions/2023/en/0xa5-broken-function-level-authorization/)
