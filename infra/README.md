# `infra/` — déclaration des ressources cloud

Ce répertoire contient ce que `ops/` ne peut pas couvrir.

`ops/` + `deploy.sh` configurent une machine **qui existe déjà** : paquets,
crontab, unités systemd, nginx, secrets. Rien là-dedans ne crée le bucket R2,
l'enregistrement DNS ou l'utilisateur Atlas dont un environnement a besoin.

Or le §3 de [#401](https://github.com/ArboreTeam/Arbore/issues/401) déclare que
le domaine, la base Mongo et le jeu de modèles **varient par environnement**.
Sans ce répertoire, ouvrir un environnement de dev signifie créer à la main un
deuxième bucket, un deuxième enregistrement DNS, un deuxième utilisateur Atlas —
non versionnés, non documentés. C'est la configuration volatile du §2, déplacée
dans des tableaux de bord, hors de portée de `docs-drift-check.sh` comme elle
l'était du dépôt.

## Périmètre actuel

| Ressource | État |
|---|---|
| DNS `api.arbore.app`, `web.arbore.app` | déclaré (par environnement) |
| DNS apex, `www`, MX × 2, SPF, apple-domain, DKIM | déclaré (zone, production seule) |
| Bucket R2 `arbore-assets` | déclaré |
| Atlas (cluster, users, IP allowlist) | pas encore — déclarer l'allowlist *est* la façon de répondre à la question restée ouverte |
| Règles de pare-feu Cloudflare, TLS Full strict | pas encore |
| VPS Epitech | hors de portée : non provisionnable par API, et retiré fin février |

Les neuf enregistrements de la zone sont déclarés, pas seulement les deux du
service. En laisser sept dehors aurait fait de ce répertoire une demi-mesure :
la messagerie iCloud et le site vitrine sont exactement le genre de
configuration que personne ne documente et qui casse en silence.

**Séparation** — `dns.tf` porte ce qui varie par environnement, `dns_zone.tf`
ce qui appartient au domaine. Un environnement de dev ne redéclare pas la
messagerie : `manage_zone_records` vaut `false` par défaut, `true` en production
seulement.

## Démarrage

```bash
cd infra
cp envs/prod.tfvars.example      envs/prod.tfvars
cp envs/prod.backend.hcl.example envs/prod.backend.hcl
# renseigner les deux fichiers (ils ne sont pas versionnés)

export TF_VAR_cloudflare_api_token="$(...)"   # jamais en fichier ni en argv
terraform init -backend-config=envs/prod.backend.hcl
terraform plan -var-file=envs/prod.tfvars
```

Le jeton a besoin de `Zone:DNS:Edit` et `Workers R2 Storage:Edit`, rien de plus.
Une « Global API Key » donnerait à la CI le droit de supprimer la zone.

## Avant le premier `apply`

Les blocs d'import de `imports.tf` sont **renseignés** (identifiants relevés le
2026-09-07). Le premier `plan` doit annoncer **zéro changement** — c'est le test
qui prouve que la déclaration décrit fidèlement l'existant.

> Un plan qui annonce `destroy` ou `replace` ne doit jamais être appliqué.
> Sur les enregistrements de messagerie en particulier : une erreur n'y produit
> aucune erreur visible, le courrier cesse simplement d'arriver.

Les commentaires Cloudflare sont **volontairement absents** des ressources : les
enregistrements existants n'en ont pas, et en ajouter ferait sortir le plan à
non-zéro, ce qui priverait ce test de son sens. Les ajouter est un changement
délibéré, à faire séparément une fois la fidélité prouvée.

## Règles de tenue

- **`.terraform.lock.hcl` est commité.** Équivalent de `go.sum` : sans lui, deux
  exécutions résolvent des versions de provider différentes et produisent des
  plans différents. Même leçon que l'étiquette `latest` corrigée en #426.
- **Le state n'est jamais dans git.** Il contient les clés R2 et Atlas en clair.
  Il vit dans R2 via le backend S3, verrouillé par `use_lockfile`.
- **Pas d'`apply` depuis un poste.** `plan` en PR, `apply` au merge.
- **Détection de dérive planifiée** : `terraform plan -detailed-exitcode` en
  cron, code 2 = la réalité s'écarte de la déclaration. C'est la réponse
  automatisée au mode d'échec de [#341](https://github.com/ArboreTeam/Arbore/issues/341)
  et [#160](https://github.com/ArboreTeam/Arbore/issues/160) — une modification
  manuelle qui survit des mois parce que rien ne la compare à la référence.
- **`prevent_destroy` sur ce qui porte des données** : bucket R2, cluster Atlas.
