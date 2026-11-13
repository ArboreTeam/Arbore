# Environnements : prod, dev, et comment viser l'un ou l'autre

Ce document s'adresse à **qui développe l'app iOS** et veut travailler contre le
backend de développement plutôt que contre la production.

Pour la mécanique serveur (deux piles Docker, nginx, déploiement), voir
[`../architecture/05-infrastructure.md`](../architecture/05-infrastructure.md).
Pour le provisionnement, [`vps-bootstrap.md`](vps-bootstrap.md).

---

## Les deux environnements

|          | branche | adresse              | base de données | déployé            |
|----------|---------|----------------------|-----------------|--------------------|
| **prod** | `main`  | `api.arbore.app`     | `arbore`        | manuellement       |
| **dev**  | `dev`   | `api-dev.arbore.app` | `arbore_dev`    | manuellement       |

Casser le dev n'a aucun effet sur les bêta-testeurs. C'est sa raison d'être.

### Les deux environnements sont sur la même machine, dans deux checkouts

Relevé le 2026-11-04, **après** la bascule DNS de #652 :

| | machine | chemin | utilisateur |
|---|---|---|---|
| **prod** | VPS Debian 12, `162.19.13.82` | `/home/debian/Arbore-prod` (`main`) | `debian` |
| **dev** | la même machine | `/home/debian/Arbore` (`dev`) | `debian` |

Les quatre noms — `api`, `web`, `generator`, `api-dev` — résolvent désormais
sur cette machine. L'ancien VPS Fedora est **toujours allumé au 2026-11-13**,
conservé comme repli quelques jours encore : les enregistrements sont proxifiés
par Cloudflare, donc y revenir est un changement d'adresse d'origine, immédiat
et sans redéploiement. Il ne reçoit plus de trafic et son crontab a été retiré.

> **Asymétrie de nommage assumée.** La production est dans `Arbore-prod` et dev
> dans `Arbore`, l'inverse de l'ancienne machine. `deploy.sh` tire son étiquette
> d'image de `git rev-parse HEAD` et son garde-fou exige `main` pour prod : un
> checkout ne peut être que sur une branche à la fois. Le checkout `dev` était
> déjà en service, et rien de ce qui marche ne bouge pendant une migration.

**Et le cloisonnement vient de là.** Deux checkouts séparés le donnent
gratuitement, puisque les chemins par défaut de `docker-compose.yml` sont
**relatifs au fichier compose**.

C'est une propriété à ne pas confondre avec une garantie. Entre le 2026-10-21
et le 2026-11-02, la machine neuve n'a tenu **qu'un seul** checkout pour deux
piles compose (`arbore-prod` et `arbore-dev`) : les mêmes défauts les faisaient
converger vers les mêmes répertoires, et les deux backends ont partagé leur
répertoire de vignettes **en écriture**. Ce qui protège aujourd'hui est une
disposition de disque, pas une barrière.

#### Ce qui est cloisonné, et ce qui ne l'est pas

Relevé par `docker inspect` des quatre conteneurs, le 2026-11-03.

| Montage | prod | dev | état |
|---|---|---|---|
| `/app/thumbnails` (rw) | `arbore-data/thumbnails-prod` | `arbore-data/thumbnails-dev` | ✅ |
| `/app/uploads/community` (rw) | `arbore-data/uploads-community-prod` | `arbore-data/uploads-community-dev` | ✅ |
| `/app/photos` (ro) | `arbore-data/photos-prod` | `arbore-data/photos-dev` | ✅ |
| `/app/models` (ro) | `arbore-data/models-prod` | `arbore-data/models-dev` | ✅ |
| `/run/secrets/*` (ro) | `arbore-data/secrets/` | **le même** | 🤝 assumé |
| `/data/generator` (rw) | checkout | **le même** | 🤝 un seul atelier |

**Les montages en écriture sont cloisonnés**, sauf `/data/generator` — et
celui-là n'est pas un cloisonnement à faire mais un atelier qui ne doit tourner
que sur **une** pile. Le code le désactive là où ses clés ne sont pas posées,
donc une seule pile y écrit.

**Les modèles sont cloisonnés depuis le 2026-11-05**, et la mesure a rendu
l'opération bien moins chère que prévu. Le répertoire partagé portait 6,7 Go,
mais chaque catalogue n'en nomme qu'une partie :

```
au cloisonnement, 2026-11-05
prod   123 legers (0,43 Go) + 123 heavy (4,06 Go)  =  4,49 Go
dev    123 legers (2,36 Go) +  72 heavy (2,47 Go)  =  4,83 Go
```

Seul **l'utile** a été copié, pas les 6,7 Go : le cloisonnement a donc été
l'occasion de ne pas dupliquer les 1,9 Go de poids mort de #734. Chaque fichier
a été vérifié par empreinte, zéro écart.

L'asymétrie des poids était instructive — les légers de dev pesaient cinq fois
ceux de prod, parce que ce sont les **Trellis 2.0**, 41,6 Mo pièce contre 3,7 Mo
pour l'ancienne génération. Les deux environnements lisaient le même répertoire
pour des usages inverses.

**Le catalogue a doublé depuis**, et la prod a reçu les nouveaux maillages : les
deux côtés pèsent maintenant la même chose, et l'asymétrie a disparu. Mesuré le
2026-11-13 :

```
prod   275 legers (4,96 Go) +  72 heavy (2,47 Go)  =  7,43 Go
dev    279 legers (4,81 Go) +  72 heavy (2,47 Go)  =  7,28 Go
```

Les quatre fiches de plus côté dev sont des maillages en cours de validation,
pas encore importés en production.

**Le revers est assumé** : avant, un modèle déposé dans `arbore-data/models`
apparaissait des deux côtés sans rien faire. Désormais il faut le poser dans les
deux. C'est précisément ce qui rend le cloisonnement utile, et ce qui le rend
contraignant.

Les photos, elles, avaient été cloisonnées tout de suite parce que le répertoire
est **vide des deux côtés** — rien à copier, rien à casser.

**Les secrets lus sont communs à dessein** : le projet Firebase est partagé, et
#434 le liste comme partage accepté. Ce qui est cloisonné, c'est l'**écriture** :
`apply_secrets()` écrit dans `arbore-data/secrets-<env>` pour tout
environnement non primaire, `arbore-data/secrets` restant celui de la prod.
Sans cela, ajouter un chiffré dev.enc.json pour donner à dev son propre projet
Firebase ferait **écraser le compte de service de la prod par un déploiement de
dev** — et le job de réconciliation (#393) tourne chaque dimanche avec
`--apply`.

#### Le contrôle au déploiement

`deploy.sh` vérifie les **huit** montages à chaque `docker compose up`, avec
deux sévérités :

- **bloquant** pour un montage en écriture partagé — le déploiement s'arrête.
  Un avertissement se perdrait dans la sortie, et c'est exactement ce qui est
  arrivé à celui des secrets (#690) ;
- **signalé** pour un montage en lecture partagé — la ligne est affichée à
  chaque déploiement, pour que le partage reste une décision visible et non un
  oubli.

Le reste du suivi est dans #434.

---

## Les trois configurations de build iOS

| configuration | backend appelé | usage                                        |
|---------------|----------------|----------------------------------------------|
| `Debug`       | **production** | débogage courant, contre les données réelles |
| `Dev`         | **dev**        | tester une feature backend pas encore promue |
| `Release`     | production     | build TestFlight                             |

**`Debug` vise la production, et c'est délibéré.** C'est ce qu'on veut la
plupart du temps : reproduire un bug remonté par un bêta-testeur suppose ses
données. Faire basculer `Debug` sur le dev aurait rendu ce cas courant
impossible sans reconfiguration.

D'où une troisième configuration plutôt que deux : le choix de l'environnement
devient explicite, au lieu d'être un effet de bord de « je débogue ou je livre ».

### Où c'est câblé

```
ArboreUi/Dev.xcconfig            configuration Dev — hôte, protocole
  └── #include? Secrets.dev.xcconfig    clé d'API (gitignoré, absent du dépôt)

ArboreUi/Debug.xcconfig          configurations Debug et Release
ArboreUi/Release.xcconfig
  └── #include? Secrets.xcconfig        idem, pour la production
```

Le `#include?` avec point d'interrogation est un **include optionnel** : si le
fichier de secrets manque, le build passe quand même, avec une clé vide. C'est
ce qui permet à la CI de compiler sans secret — mais c'est aussi pourquoi un
fichier oublié se manifeste par un `401` à l'exécution, pas par une erreur de
compilation.

---

## Basculer sur le dev

**1. Récupérez `ArboreUi/Secrets.dev.xcconfig`.**

Il porte la clé d'API du backend de dev, donc il n'est pas dans le dépôt
(`.gitignore`). Deux façons de l'obtenir :

- demandez-le à un mainteneur ;
- ou, si vous avez la clé age `dev`, générez-le :

  ```sh
  cp ArboreUi/Secrets.dev.xcconfig.example ArboreUi/Secrets.dev.xcconfig
  SOPS_AGE_KEY_FILE=~/.config/sops/age/arbore-dev.txt \
    sops --decrypt ops/secrets/dev.enc.env | grep '^ARBORE_API_KEY='
  ```

  puis reportez la valeur dans `ARBORE_API_KEY`.

**2. Posez le fichier dans `ArboreUi/`.**

**3. Dans Xcode, sélectionnez le schéma « ArboreUi Dev ».**

**4. Lancez.** Pour revenir en production, reprenez le schéma « ArboreUi ».

### Vérifier contre quoi vous tapez

```sh
curl https://api.arbore.app/health
curl https://api-dev.arbore.app/health
```

Chacun renvoie le commit qu'il fait tourner. Deux commits différents = le dev
est en avance sur la prod, ce qui est l'état normal quand une feature est en
cours.

---

## Contribuer : `dev` n'accepte plus de push direct

Depuis le 2026-09-08, la branche `dev` est protégée. Toute modification passe
par une **pull request**, y compris pour les administrateurs.

```sh
git checkout dev && git pull
git checkout -b feat/ma-feature
# … commits …
git push -u origin feat/ma-feature
gh pr create --base dev
```

| Règle | Valeur |
|---|---|
| Pull request | obligatoire |
| Approbations requises | **0** — vous fusionnez votre propre PR |
| Checks requis | `build_summary`, `security` |
| Push direct, force-push, suppression | refusés |

**Zéro approbation** est délibéré : à deux sur le dépôt, exiger une revue
bloquerait le travail en solo. C'est la PR qui devient obligatoire, pas la
validation par un tiers.

Ces deux checks sont les seuls qui ne peuvent **jamais** être ignorés :
`build_summary` a `if: always()` et agrège les quatre jobs de build ;
`security` n'a aucune condition de chemin, donc il tourne sur toute PR. Les
autres jobs sont conditionnés au contenu de la PR et seraient `skipped` — donc
considérés comme satisfaits — sur une PR de documentation ou d'iOS.

> **Pourquoi c'est appliqué aux administrateurs.** La première configuration
> laissait `enforce_admins: false`. Un push direct passait alors quand même,
> avec pour seule trace un `remote: Bypassed rule violations`. Une règle
> franchissable informe ; elle ne protège pas.

Le lendemain, le check `security` a bloqué une PR sans rapport, sur une
[RCE non authentifiée dans Next.js](https://github.com/advisories/GHSA-2xp9-vwfh-vxw4)
publiée entre-temps. Sans cette configuration, la PR aurait été fusionnée.

`main` reste moins stricte : sa protection sert surtout à interdire le push
direct, et une PR promue depuis `dev` a déjà franchi le contrôle en amont.

---

## Déployer un environnement

Le déploiement est **manuel**, par choix : personne ne pousse en production sans
le savoir.

```sh
# production — checkout `main`, environnement primaire
cd /home/debian/Arbore-prod && ./deploy.sh

# développement — checkout `dev`
cd /home/debian/Arbore && ARBORE_ENV=dev ARBORE_DEPLOY_BRANCH=dev ./deploy.sh
```

Les deux checkouts sont sur la **même machine** depuis le 2026-11-04. Cette page
a donné l'ancienne machine (`/home/fedora/Arbore`) comme cible de production
jusqu'au 2026-11-13 : la commande y marchait encore, et ne déployait plus rien
de ce que les utilisateurs atteignent.

Trois pièges, tous rencontrés en vrai :

**`ARBORE_DEPLOY_BRANCH=dev` est obligatoire pour le dev.** Sans lui le script
refuse : `Checkout sur 'dev', attendu 'main' — déploiement refusé`. Ce garde-fou
(#384) existe parce qu'un checkout laissé sur une branche de travail ferait
déployer cette branche sans rien signaler. Le défaut est `main`, et la
production ne définit donc pas la variable.

**Ne pas lancer `deploy.sh` avec `sudo`.** Le script gère lui-même l'élévation
pour Docker : l'utilisateur n'a pas besoin d'être dans le groupe `docker`.

> ⚠️ **Le symptôme décrit ici a disparu, pas la raison.** Cet avertissement
> annonçait un `Permission denied (publickey)` sur le `git pull`, quand le
> remote était en SSH. Il est passé en **HTTPS public** : sous `sudo`, le pull
> **réussit** désormais. L'avertissement est devenu silencieux, et il a été
> ignoré toute la journée du 2026-11-02.
>
> Les deux conséquences réelles, mesurées ce jour-là :
>
> | | |
> |---|---|
> | `$HOME` vaut `/root` | la clé age est introuvable, `apply_secrets` **avertit puis rend 0** — le déploiement s'annonce « terminé » en tournant sur les **anciens** secrets |
> | les fichiers sont écrits par root | **167 entrées sur 1021** dans `.git`, et le premier `git pull` fait à la main échoue |
>
> Vérifié sans `sudo` : secrets déchiffrés, images tirées, santé à 200, et
> **0 entrée root** dans `.git`.
>
> Depuis #716, le script tolère l'invocation sous `sudo` — il retrouve
> l'utilisateur réel par `SUDO_USER` et travaille sous son identité. C'est un
> filet, pas une permission : lancez-le sans.

**Attendre la publication des images.** `deploy.sh` tire l'image étiquetée
`sha-<commit>` ; si le workflow de publication n'a pas fini, le tirage échoue et
le script se replie sur un build local — lent, et l'image qui tourne n'est alors
plus celle que la CI a produite. Vérifier avant de déployer :

```sh
gh api "repos/ArboreTeam/Arbore/actions/runs?head_sha=$(git rev-parse origin/main)" \
  --jq '.workflow_runs[] | select(.name|test("Build")) | .conclusion'
```

`gh run list --commit <sha>` renvoie parfois des résultats périmés, y compris des
workflows supprimés. L'appel direct à l'API ci-dessus est fiable.

---

## Ce qui diffère en dev

**Sentry est éteint.** Sans DSN, le SDK ne démarre pas : les plantages de test
ne viennent pas polluer les rapports de production. `Secrets.dev.xcconfig`
laisse donc les trois variables `SENTRY_DSN_*` vides — c'est voulu, ne les
remplissez pas.

**Les modèles 3D sont lus sur le disque**, pas sur R2. Le dev n'a pas les
identifiants du bucket : les lui donner aurait signifié qu'une clé age de dev
ouvre l'écriture sur le stockage de production.

**Le projet Firebase est partagé avec la production.** C'est une décision, pas
une étape manquante : un projet par environnement obligerait à dupliquer les
comptes, les règles de sécurité et les certificats Apple à chaque environnement,
pour un bénéfice faible à notre échelle.

> ⚠️ **Conséquence à retenir.** Un compte créé en dev existe aussi côté
> production, et une suppression de compte en dev supprime l'identité Firebase
> pour de bon. Prévenez avant de tester les parcours de suppression.

---

## Références

- Chantier d'ensemble : [#401](https://github.com/ArboreTeam/Arbore/issues/401)
- Environnement de dev : [#434](https://github.com/ArboreTeam/Arbore/issues/434)
- Constantes en dur restantes : [#456](https://github.com/ArboreTeam/Arbore/issues/456)
