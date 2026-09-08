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

Les deux tournent **en même temps** sur le même VPS, sur des ports distincts,
depuis deux checkouts git séparés. Ils ne partagent ni la version, ni les
secrets, ni les données.

Casser le dev n'a aucun effet sur les bêta-testeurs. C'est sa raison d'être.

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
