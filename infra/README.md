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
| DNS `api-dev.arbore.app` | déclaré, sous `enable_dev_hostnames` |
| DNS **`generator.arbore.app`** | ⚠️ **pas déclaré** — voir ci-dessous |
| DNS apex, `www`, MX × 2, SPF, apple-domain, DKIM | déclaré (zone, production seule) |
| Bucket R2 `arbore-assets` | déclaré |
| Atlas (cluster, users, IP allowlist) | pas encore — déclarer l'allowlist *est* la façon de répondre à la question restée ouverte |
| Règles de pare-feu Cloudflare, TLS Full strict | pas encore |
| VPS Epitech | hors de portée : non provisionnable par API, et retiré fin février |

> ⚠️ **`generator.arbore.app` n'est pas dans ce répertoire.** Il n'est ni
> déclaré ni importé, alors qu'il sert en production — `generator.arbore.app`
> et `web.arbore.app` sont servis par le même conteneur, distingués par
> `server_name` dans nginx.
>
> Conséquence à connaître avant toute migration : changer `origin_ip`
> déplacerait `api` et `web`, et **laisserait `generator` sur l'ancienne
> machine**. L'adopter demande son identifiant d'enregistrement Cloudflare, à
> lire via l'API, puis un bloc `import` comme les autres. Suivi dans #652.

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

## Secrets à poser dans le dépôt

`plan` reste inerte tant que les cinq ne sont pas là : il l'annonce et sort en
succès, plutôt que d'échouer en rouge sur chaque PR.

| secret | sert à |
|---|---|
| `CLOUDFLARE_API_TOKEN` | API Cloudflare. Portée `Zone:DNS:Edit` + `Workers R2 Storage:Edit` |
| `CLOUDFLARE_ACCOUNT_ID` | identifiant de compte ; compose aussi l'endpoint R2 du state |
| `CLOUDFLARE_ZONE_ID` | identifiant de la zone `arbore.app` |
| `TFSTATE_S3_ACCESS_KEY` | lecture/écriture du bucket `arbore-tfstate` |
| `TFSTATE_S3_SECRET_KEY` | idem |

Ce sont des **secrets GitHub Actions**, pas des entrées de `ops/secrets/*.enc.env`.
Les deux canaux ne se croisent pas : les `.enc` sont déchiffrés *sur la machine*
par `apply_secrets`, avec la clé age locale, et aucun workflow ne contient
`sops`.

> Donner la clé age privée à la CI pour qu'elle lise les `.enc` échangerait un
> périmètre de 5 valeurs contre les 32 de `prod.enc.env` — URI Mongo, clés API,
> clés des fournisseurs d'IA. C'est la raison de ne pas le faire.

Le jeton R2 peut être restreint au seul bucket `arbore-tfstate` : le state vit
ailleurs que les assets. Il mérite la même méfiance que ce qu'il protège — le
state contient les clés R2 et Atlas en clair.

### Pourquoi `envs/prod.ci.tfvars` est versionné

`envs/prod.tfvars` est gitignoré, donc absent du runner, et un `plan` a besoin
de toutes les variables. `prod.ci.tfvars` porte celles qui ne sont pas
sensibles ; les trois autres arrivent par `TF_VAR_*`.

`origin_ip` y est délibérément. L'adresse de l'origine n'est pas le contrôle de
sécurité — le pare-feu l'est, et les enregistrements restent proxifiés. En
échange, toute bascule de machine devient un **diff relu en PR**.

## Ce que la CI publie, et ce qu'elle retient

Le dépôt est **public** : ses logs d'Actions et ses commentaires de PR le sont
aussi.

Le job `plan` ne publie donc que les **noms de ressources et les actions** —
déjà dans le dépôt. Jamais le diff de valeurs, qui porte les adresses IP et les
identifiants de zone.

> Le plan figé (`-out`) embarque les valeurs de **toutes** les variables, jeton
> compris : c'est ce qu'a appris `cc3aef8`, où le `.gitignore` couvrait le state
> mais pas les plans. Ici il ne quitte jamais le runner — aucun artefact, et il
> est supprimé dès le JSON extrait.

Un plan qui **détruit** une ressource déclenche un avertissement visible sans
faire échouer le job : c'est parfois voulu, jamais à appliquer sans l'avoir lu.

## Pourquoi il n'y a pas de job `apply`

Les règles de tenue disent « `apply` au merge ». Ce workflow n'en fait pas, et
c'est un choix à trancher plutôt qu'un oubli :

un apply automatique applique **sans que personne n'ait lu le plan**. Sur les
enregistrements de messagerie, une erreur ne produit aucune erreur visible — le
courrier cesse simplement d'arriver. Sur `api` ou `web`, elle coupe le service.

Trois options, par ordre de prudence décroissante :

1. **`workflow_dispatch` sur `main`**, déclenché à la main après avoir lu le
   plan de la PR. L'apply reste un geste humain, mais joué par la CI, donc avec
   les bons identifiants et sans poste dans la boucle.
2. **Au merge, derrière un environnement protégé** (`infra-prod`) avec
   relecteurs requis. Automatique, mais avec une approbation explicite.
3. **Au merge, sans garde.** Ce que disent les règles de tenue aujourd'hui.

Tant que rien n'est tranché, l'apply se fait à la main — contrairement à la
règle, et en le sachant.

## Basculer dev seul, pour éprouver une machine neuve

`dev_origin_ip` détache `api-dev` de la production. Vide, dev suit `origin_ip` —
c'est le cas normal et le défaut.

```hcl
# envs/prod.tfvars
origin_ip     = "79.137.92.154"   # api + web : machine en service
dev_origin_ip = "162.19.13.82"    # api-dev seul : machine neuve
```

```sh
terraform plan -var-file=envs/prod.tfvars    # doit montrer UN seul changement
terraform apply -var-file=envs/prod.tfvars
```

Le plan ne doit toucher que `cloudflare_dns_record.api_dev[0]`. **S'il propose
autre chose, ne pas appliquer** : le state a dérivé, ou le mauvais backend est
initialisé.

Ce que la bascule éprouve, et qu'un essai en local ne peut pas donner : le
proxy Cloudflare vers l'origine neuve, le certificat d'origine tel que
Cloudflare le valide en Full (strict), et le pare-feu d'origine vu depuis les
plages Cloudflare réelles — le tout sans déplacer un seul utilisateur.

Remettre `dev_origin_ip = ""` une fois la bascule complète faite, pour que dev
retourne suivre la production.

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
