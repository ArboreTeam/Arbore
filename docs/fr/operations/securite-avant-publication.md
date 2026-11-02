# Sécurité avant publication

État de référence au 22 juillet 2026.

## Autorisation

Toutes les routes protégées exigent une clé API et un jeton Firebase valide. Le contrôle de santé et les miniatures restent publics ; la configuration publique exige uniquement la clé API. Les opérations qui modifient le catalogue (`POST /plants`), lancent une génération de fiche (`POST /plants/generate` et `/plants/generate-multiple`) ou déposent une miniature exigent en plus le rôle administrateur.

Le rôle provient en priorité des claims Firebase `admin: true` ou `role: admin`. `ARBORE_ADMIN_UIDS` est uniquement une liste d'amorçage ou de récupération. Elle ne doit contenir que des UID Firebase et doit être gérée comme un secret de production.

## Limites serveur

- API authentifiée : 120 requêtes par minute et par UID.
- Chat IA : 20 requêtes par minute et 100 par période de 24 heures.
- Diagnostic : 6 requêtes par minute et 20 par période de 24 heures.
- Génération administrateur : 5 requêtes par minute et 50 par période de 24 heures.
- Téléversements : 10 requêtes par minute.
- Corps JSON : 10 Mio maximum ; photo de profil : 5 Mio ; image de diagnostic : 6 Mio ; miniature : 8 Mio.
- Messages : 2 000 caractères ; historique du chat : 30 messages ; génération groupée : 10 plantes.
- Serveur HTTP : en-têtes 10 s, lecture 30 s, écriture 120 s, connexion inactive 120 s.

Le limiteur est conservé en mémoire par instance. Avant de multiplier les instances, le remplacer par un quota partagé (par exemple Redis ou le rate limiting Cloudflare), afin qu'un utilisateur ne puisse pas multiplier son quota en changeant d'instance.

## Suppression de compte

`DELETE /users` supprime les jardins, consentements, profil MongoDB, anciennes publications communautaires résiduelles et identité Firebase. Pour une connexion Apple, Arbore tente aussi de révoquer le jeton avant d'effacer le profil. Côté iOS, l'historique local du chatbot, les projets, routines, notifications et fichiers AR sont supprimés après confirmation du serveur.

La route est rejouable si Firebase échoue après les suppressions MongoDB. Le parcours complet doit néanmoins être testé avec des comptes temporaires e-mail, Google et Apple avant chaque soumission.

## Déploiement

1. Déployer les images construites avec les versions verrouillées du dépôt.
2. Vérifier que les ports des conteneurs restent liés à `127.0.0.1` et ne sont exposés que par le proxy TLS.
3. Vérifier les permissions `0600` du fichier `.env` et de ses sauvegardes.
4. Vérifier la présence de la clé privée Apple hors du dépôt et sa lisibilité uniquement par le service.
5. Tester `/health`, les refus `401`, `403`, `413` et `429`, puis une suppression complète de compte.
6. Publier la politique version 2.2 avant d'envoyer le build à Apple.

---

## Ce qui a changé depuis — addendum du 2026-11-03

Ce document est un **instantané daté**, et c'est un format utile : il dit ce
qui était vrai à une date, pas ce qui est vrai aujourd'hui. Deux faits l'ont
contredit depuis, relevés en auditant la codebase. Ils sont consignés ici
plutôt qu'intégrés au corps, pour ne pas abîmer l'instantané.

**Le dépôt de miniature n'exige plus toujours le rôle administrateur.** La
phrase « les opérations qui … déposent une miniature exigent en plus le rôle
administrateur » reste vraie de `POST /models/thumbnails/:plantId`. Mais #696 a
ajouté `POST /internal/models/thumbnails/:plantId`, qui exige **deux clés** —
`X-API-Key` et `X-Arbore-Internal-Key` — et **aucun rôle**.

Ce n'est pas un affaiblissement : la clé interne n'ouvre que trois gestes
(lister le catalogue, lire un modèle, déposer une vignette), n'accorde aucun
rôle, n'ouvre aucune route de compte, et la clé d'API seule ne suffit pas.
Absente, les routes répondent 503 — la production ne la porte pas. Détail dans
[`../architecture/03-components-backend.md`](../architecture/03-components-backend.md).

**Le plafond des dépôts de miniature est passé de 10 à 200 par minute.** La
ligne « Téléversements : 10 requêtes par minute » vaut toujours pour les photos
de profil (`uploadMinuteLimiter`). Les vignettes ont leur propre limiteur,
`vignettesParMinute = 200`, parce qu'une republication de catalogue doit passer
en une seule fois : à dix par minute elle s'arrêtait à la dixième et prenait
quarante-neuf refus de suite. Le plafond d'une route de lot se mesure à la
taille du lot.

Le reste des valeurs a été recontrôlé contre `main.go` le 2026-11-03 et tient :
300/min public, 120/min authentifié, 20 et 100 pour le chat, 6 et 20 pour le
diagnostic, 10 Mio de corps JSON, 5 Mio de photo de profil, 6 Mio d'image de
diagnostic, 8 Mio de miniature.
