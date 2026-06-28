# ADR 0005 — Self-authz via token uid (pas d'uid dans l'URL)

- **Statut** : Accepted
- **Date** : 2026-05-10
- **Décideurs** : Équipe Arbore

## Contexte

Lorsqu'un utilisateur édite ses propres données (nom, photo, jardins, consentements), le backend doit garantir qu'il **n'agit que sur ses propres ressources**. Le risque à éviter : qu'un utilisateur authentifié A puisse modifier les données d'un utilisateur B en spécifiant l'`uid` de B dans la requête (par exemple via une URL `PATCH /users/{uid}` où l'`uid` serait un paramètre de chemin).

Au moment de concevoir le nouvel endpoint `PATCH /users/me` (issue #138), deux options se présentaient :

1. **`PATCH /users/{uid}`** — l'`uid` cible vient de l'URL. Le handler doit comparer cet `uid` au `tokenUID` extrait du middleware et renvoyer `403` si différent.
2. **`PATCH /users/me`** — pas d'`uid` dans l'URL. Le handler utilise directement l'`uid` extrait du token. Toute requête est implicitement self-only.

Le codebase héritait déjà d'endpoints en variante 1 (`POST /users/:uid/photo`, `GET /users/:uid/photo`), qui implémentent explicitement la vérification `tokenUID == uidParam` et renvoient `403 Forbidden` en cas de mismatch.

## Décision

**Tout nouvel endpoint sur les ressources de l'utilisateur courant doit utiliser le pattern `/users/me`**, **`/gardens`** (sans filtre d'`uid` dans l'URL), ou tout autre chemin qui ne **mentionne pas l'`uid`** dans l'URL.

L'`uid` est systématiquement extrait du **token Firebase** par le middleware `FirebaseAuthMiddleware` et posé dans le contexte Gin via `c.Set("uid", ...)`. Les handlers lisent uniquement cette source.

Les endpoints hérités qui acceptent un `uid` dans l'URL (`/users/:uid/photo`) restent en place pour ne pas casser les clients existants, mais ne sont **plus la cible** pour de nouvelles features. Leur consolidation (migration vers `/users/me/photo`) sera tracée dans une issue séparée si une refonte API est planifiée.

L'`uid` envoyé dans le body d'une requête est **explicitement ignoré** et écrasé par le `tokenUID` (cf. `createUser` et `createGarden` dans `main.go`).

## Conséquences

### Positives

- **Surface d'attaque réduite** : un utilisateur ne peut pas tenter d'agir au nom d'un autre, même s'il forge manuellement une requête HTTP. La cible de la requête est intrinsèquement self.
- **Simplicité du handler** : pas de comparaison `tokenUID == uidParam`, pas de risque d'oublier la vérification dans un nouveau handler.
- **Pattern cohérent** avec les conventions REST modernes (`/users/me` est l'idiome reconnu pour « l'utilisateur courant »).
- **Lisibilité côté client** : les appels iOS deviennent `NetworkManager.shared.request(endpoint: "/users/me", method: .PATCH, body: ...)` sans avoir à concaténer l'`uid` dans l'URL.

### Négatives

- **Asymétrie temporaire** dans l'API : les endpoints hérités utilisent encore `/users/:uid/photo`, ce qui crée une incohérence visible pour un nouvel arrivant qui lit le code. Cette incohérence est tolérée le temps d'une refonte future.
- **Impossibilité d'agir sur un autre utilisateur** sans introduire un endpoint admin dédié. Cela impose à l'avenir, si la feature de modération devient nécessaire, de créer une route séparée `/admin/users/:uid` avec une autorisation différente (rôle admin vérifié via une claim Firebase custom).

### Neutres

- Les **endpoints de lecture publique** (`GET /plants`, `GET /models/thumbnails/:filename`) ne sont pas concernés par ce pattern puisqu'ils ne portent pas d'`uid`. Ils restent en l'état.
- Les **handlers en cascade** (par exemple `deleteUser` qui supprime gardens puis consents puis le user) bénéficient également du pattern : l'`uid` est lu une seule fois en tête du handler et tous les filtres `bson.M{"uid": uid}` en bénéficient.

## Application concrète

| Endpoint | Pattern | Notes |
|---|---|---|
| `PATCH /users/me` | ✅ self-authz | Introduit par #138. Modèle pour tout nouvel endpoint. |
| `GET /users/:uid` | ⚠️ hérité | Vérifie `tokenUID == uidParam` puis renvoie 403 si différent. |
| `POST /users/:uid/photo` | ⚠️ hérité | Idem. |
| `GET /users/:uid/photo` | ⚠️ hérité | Idem. |
| `POST /users` | ✅ self-authz | Le `uid` du body est ignoré, le `tokenUID` est utilisé. |
| `DELETE /users` | ✅ self-authz | Pas d'`uid` dans l'URL. |
| `GET /gardens` | ✅ self-authz | Filtre implicite `bson.M{"uid": tokenUID}`. |
| `POST /gardens` | ✅ self-authz | `garden.UID = tokenUID` forcé. |
| `PUT /gardens/:id` | ✅ self-authz | Filtre `bson.M{"_id": id, "uid": tokenUID}` garantit l'ownership. |
| `DELETE /gardens/:id` | ✅ self-authz | Idem. |
| `POST /consents` | ✅ self-authz | `consent.UID = tokenUID` forcé. |
| `GET /consents` | ✅ self-authz | Filtre par `uid`. |

## Alternatives considérées

- **Header `X-User-Id` géré par le client** — écarté car équivalent à mettre l'`uid` dans l'URL : trivial à falsifier.
- **Signed URL avec scope `users/{uid}`** — écarté car plus complexe à implémenter qu'un middleware token classique pour un gain de sécurité minime.
- **Custom claims Firebase avec rôle** — pas nécessaire pour la self-authz, mais sera utile pour introduire un rôle admin si la modération devient un besoin.

## Liens

- [Issue #138 — PATCH /users/me](https://github.com/ArboreTeam/Arbore/issues/138)
- [Issue #110 — Backend n'enforce pas la vérification email du token Firebase](https://github.com/ArboreTeam/Arbore/issues/110)
- ADR 0004 — Firebase Auth (qui fournit le `uid` injecté dans le contexte)
- [OWASP — Broken Object Level Authorization](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/)
