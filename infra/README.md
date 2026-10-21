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
| DNS `generator.arbore.app` | déclaré, adopté le 2026-10-21 · suit `generator_origin_ip` |
| DNS apex, `www`, MX × 2, SPF, apple-domain, DKIM | déclaré (zone, production seule) |
| Bucket R2 `arbore-assets` | déclaré |
| Atlas (cluster, users, IP allowlist) | pas encore — déclarer l'allowlist *est* la façon de répondre à la question restée ouverte |
| Règles de pare-feu Cloudflare, TLS Full strict | pas encore |
| VPS Epitech | hors de portée : non provisionnable par API, et retiré fin février |

> **`generator.arbore.app` est resté hors de ce répertoire du 2026-09-07 au
> 2026-10-21**, alors qu'il servait en production. Il est servi par le même
> conteneur que `web.arbore.app`, distingué par `server_name` dans nginx.
>
> Ce que l'oubli coûtait : changer `origin_ip` aurait déplacé `api` et `web` en
> **laissant `generator` sur l'ancienne machine**, et le plan n'aurait rien
> signalé. Avec l'ancienne éteinte, l'atelier 3D tombait.
>
> La leçon vaut au-delà de ce cas : **un plan à zéro changement ne prouve que la
> fidélité de ce qui est déclaré.** Il ne voit pas ce qui manque. Le plan de
> #427 était exact, et il déclarait neuf enregistrements sur dix.
>
> C'est la raison la plus concrète de poser la détection de dérive planifiée des
> règles de tenue : `terraform plan -detailed-exitcode` compare la réalité à la
> déclaration, mais seul un inventaire de la zone compare la déclaration à la
> réalité.

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

## L'`apply`, déclenché à la main

Les règles de tenue disent « `apply` au merge ». Ce workflow ne le fait pas, et
c'est délibéré : **un apply au merge applique sans que personne n'ait lu le
plan**. Sur les enregistrements de messagerie, une erreur ne produit aucune
erreur visible — le courrier cesse simplement d'arriver. Sur `api` ou `web`,
elle coupe le service.

L'apply est donc un `workflow_dispatch`. Il tourne dans la CI, avec les bons
identifiants et sans poste dans la boucle — ce que la règle voulait — mais il
demande un geste humain, ce que « au merge » ne donnait pas.

### Comment le déclencher

Actions → **🏗️ Terraform** → *Run workflow*, puis :

| champ | valeur |
|---|---|
| `appliquer` | taper `appliquer`. Laissé vide, le workflow ne fait que planifier. |
| `autoriser_destruction` | **à laisser décoché**, sauf destruction voulue et relue. |

```sh
gh workflow run terraform.yml -f appliquer=appliquer
```

### Les trois garde-fous

1. **Déclenchement humain.** Aucun push, aucun merge ne lance un apply.
2. **Mot de confirmation.** Un `workflow_dispatch` lancé par curiosité planifie,
   et n'applique rien.
3. **Refus par défaut sur une destruction.** Un plan qui détruit **arrête** le
   job, sauf autorisation explicite. La décision se prend dans le shell et non
   dans une expression `if:` : seule la chaîne exacte `true` lève le garde-fou,
   tout le reste refuse — y compris une valeur absente ou inattendue.

### Ce qui est appliqué est ce qui a été montré

Le job calcule son plan, l'affiche, puis applique **ce fichier de plan**. Pas un
plan recalculé entre l'affichage et l'exécution, qui pourrait différer si la
zone a bougé entre-temps.

> `environment: infra-prod` est déclaré sur le job. Y poser des relecteurs
> requis ajoute une approbation humaine avant tout apply, sans toucher au
> workflow.

## Trois adresses d'origine, et pourquoi

| variable | enregistrements | sert |
|---|---|---|
| `origin_ip` | `api`, `web` | l'app mobile de l'App Store |
| `dev_origin_ip` | `api-dev` | le développement, via TestFlight |
| `generator_origin_ip` | `generator` | l'atelier 3D |

Les deux dernières sont vides par défaut : tout suit alors `origin_ip`, ce qui
reste le cas normal hors migration.

**L'atelier a sa propre variable parce qu'il n'est pas une surface
d'utilisateur.** L'app mobile ne l'appelle pas. Il doit vivre là où sont les
modèles qu'il produit, sinon chaque livraison demande un transfert à la main
entre deux machines.

Le déplacer ne déplace aucune donnée de base : son état est un fichier,
`/data/generator/etat.json`, et son code n'accède pas à Mongo — seul le disque
qu'il lit change.

> C'est la troisième occurrence du motif `var.x != "" ? var.x : var.origin_ip`.
> Si une quatrième apparaît, mieux vaudra une seule variable `map` qu'une par
> enregistrement.

## Basculer dev seul, pour éprouver une machine neuve

`dev_origin_ip` détache `api-dev` de la production. Vide, dev suit `origin_ip` —
c'est le cas normal et le défaut.

```hcl
# envs/prod.ci.tfvars — versionné, donc le changement est relu en PR
origin_ip     = "79.137.92.154"   # api + web : machine en service
dev_origin_ip = "162.19.13.82"    # api-dev seul : machine neuve
```

La PR qui porte ce diff reçoit son plan en commentaire. Il doit montrer
**exactement une ressource, sans destruction** :

| ressource | action |
|---|---|
| `cloudflare_dns_record.api_dev[0]` | update |

> **S'il propose autre chose** — en particulier une ligne sur `api`, `web` ou un
> enregistrement MX — **ne pas appliquer** : le state a dérivé, ou le mauvais
> backend est initialisé.

Une fois le plan relu, déclencher l'apply à la main (voir plus haut) :

```sh
gh workflow run terraform.yml -f appliquer=appliquer
```

Puis vérifier, depuis n'importe où :

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://api-dev.arbore.app/health
```

| code | ce que ça dit |
|---|---|
| `200` | la chaîne complète fonctionne contre la machine neuve |
| `521` / `522` | Cloudflare n'atteint pas l'origine — pare-feu ou nginx |
| `526` | Cloudflare refuse le certificat d'origine |

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
- **Pas d'`apply` depuis un poste.** `plan` en PR, `apply` par
  `workflow_dispatch` — voir plus haut. « Au merge » a été écarté : il
  appliquerait sans que personne n'ait lu le plan.
- **Détection de dérive planifiée** : `terraform plan -detailed-exitcode` en
  cron, code 2 = la réalité s'écarte de la déclaration. C'est la réponse
  automatisée au mode d'échec de [#341](https://github.com/ArboreTeam/Arbore/issues/341)
  et [#160](https://github.com/ArboreTeam/Arbore/issues/160) — une modification
  manuelle qui survit des mois parce que rien ne la compare à la référence.
- **`prevent_destroy` sur ce qui porte des données** : bucket R2, cluster Atlas.
