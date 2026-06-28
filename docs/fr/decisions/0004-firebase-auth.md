# ADR 0004 — Firebase Auth comme provider d'authentification

- **Statut** : Accepted
- **Date** : 2026-01-20
- **Décideurs** : Équipe Arbore

## Contexte

L'application doit gérer **l'authentification des utilisateurs** : signup, login email/mot de passe, login Google, reset de mot de passe, vérification d'email, suppression de compte. Côté backend, chaque requête utilisateur doit pouvoir être attribuée à un utilisateur authentifié et vérifié.

Plusieurs critères pèsent sur le choix d'un provider :

- **Vitesse de delivery** — le projet est sous échéance pédagogique (livraisons sprint après sprint).
- **Coût** — l'équipe étant étudiante, aucun budget significatif n'est disponible.
- **Conformité RGPD** — les données personnelles (email, nom) doivent être traitées avec un niveau de garantie suffisant.
- **Sécurité** — la chaîne d'auth doit résister aux attaques classiques (brute force, credential stuffing, session hijacking).
- **Multi-platform** — la doc cible iOS aujourd'hui, web (Next.js) demain.

## Décision

L'application utilise **Firebase Authentication** comme unique provider d'auth, avec deux méthodes activées :

- **Email + mot de passe** (avec envoi automatique d'un mail de vérification).
- **Google Sign-In** (via le SDK Google côté iOS).

Côté backend Go, chaque requête protégée est vérifiée par le middleware `FirebaseAuthMiddleware` qui consomme le **Firebase Admin SDK** pour valider le `Bearer` token JWT et en extraire l'`uid`. Cet `uid` devient l'identifiant fonctionnel utilisé dans toutes les collections Mongo.

Le mot de passe n'est **jamais transmis au backend** — Firebase Auth se charge intégralement de la chaîne signup/login/reset.

## Conséquences

### Positives

- L'équipe ne maintient **aucune logique d'authentification custom** : pas de hash de mot de passe, pas de session, pas de gestion du reset par token magique, pas d'OAuth flow à implémenter. Firebase fait tout cela.
- Les comptes Google sont gérés sans friction côté iOS — un seul SDK Google Sign-In suffit.
- Le **Firebase Admin SDK** côté Go fournit une vérification de token rapide et fiable (cache des clés publiques en interne).
- Le système est gratuit jusqu'à des volumes très significatifs (50 000 MAU pour le tier Spark, largement au-delà de l'usage attendu).
- L'envoi de mails de vérification, de reset, et la gestion des comptes vérifiés/non-vérifiés est intégrée nativement.
- La même infrastructure d'auth resservira pour le front web Next.js (issues #98-#109) sans duplication.

### Négatives

- **Vendor lock-in fort** : si Firebase devient payant ou indisponible, la migration vers un autre provider impliquerait de migrer tous les `uid` (qui sont des chaînes opaques Firebase) et de recréer un système d'auth équivalent.
- Les **données personnelles** (email) sont stockées chez Google. Cela impose un consentement RGPD explicite et la mention du sous-traitant dans la politique de confidentialité.
- Les **logs d'authentification** vivent dans la console Firebase et ne sont pas directement intégrés à notre observabilité côté backend.
- L'**email de vérification** envoyé par Firebase utilise les templates Firebase par défaut, peu personnalisables sans passer en Pay-as-you-go.

### Neutres

- Le découplage `uid Firebase` ↔ document Mongo (`users.uid`) impose une discipline applicative pour éviter les comptes orphelins (Firebase OK mais Mongo manquant ou inversement). Cette discipline est portée par `saveUserToBackendThrowing` côté iOS qui rollback Firebase si `POST /users` échoue (cf. issue #137 et l'ADR 0005).
- Le **ban d'utilisateur** est géré applicativement (flag `banned: true` dans Mongo, vérifié par le middleware Firebase via `CheckUserBannedFunc`). Cette approche évite de désactiver le compte côté Firebase ce qui empêcherait l'utilisateur de récupérer ses données via le flow RGPD.

## Alternatives considérées

- **Auth custom avec PostgreSQL + bcrypt** — écarté par coût initial (≥ 2 semaines de dev rien que pour avoir un MVP) et risque sécurité (cryptographie maison rarement bien faite la première fois).
- **AWS Cognito** — comparable en features à Firebase mais avec une expérience développeur historiquement plus complexe, surtout côté iOS où le SDK Firebase est très mature.
- **Supabase Auth** — open-source et auto-hébergeable, mais demande de gérer un PostgreSQL nous-mêmes et la doc iOS est moins fournie qu'Firebase.
- **Auth0** — solide mais payant au-delà de 7 000 utilisateurs (tier gratuit limité).
- **Apple Sign In + custom backend** — partiel : Apple Sign In ne couvre que les utilisateurs iCloud, il faudrait quand même une auth email/password pour les autres.

## Liens

- [Firebase Auth — Documentation](https://firebase.google.com/docs/auth)
- [Firebase Admin SDK Go](https://firebase.google.com/docs/admin/setup)
- [Issue #110 — Backend n'enforce pas la vérification email du token Firebase](https://github.com/ArboreTeam/Arbore/issues/110)
- [Issue #137 — Backend POST /users silently fails on signup → orphan Firebase user](https://github.com/ArboreTeam/Arbore/issues/137)
- ADR 0005 — Self-authz pattern (qui dépend de Firebase Admin)
