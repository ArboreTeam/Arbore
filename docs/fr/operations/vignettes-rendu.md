# Rendu des vignettes du catalogue

Les vignettes du catalogue sont rendues par un **job en conteneur**, hors de
tout environnement Apple. Elles l'étaient auparavant depuis l'app, écran par
écran, par un écran de debug — une opération manuelle qu'il fallait rejouer à
chaque changement de modèle.

Cet écran, son renderer RealityKit et la suite de tests qui le pilotait depuis
le simulateur **ont été retirés** de l'app (#696). L'app ne rend plus de
vignettes : elle les affiche, les met en cache et refuse les anciennes. Le
rendu n'a plus qu'un seul chemin, et c'est celui décrit ici.

## Pourquoi Blender

61 des 123 modèles servis n'existent qu'en USDZ. Un moteur ne lisant que le
glTF exigerait une conversion dont on ne dispose pas sous Linux. Blender
importe l'USD nativement.

La version est **épinglée dans l'image** (4.2 LTS), et non installée par
`ops/`. Installée par la distribution, la reproductibilité serait celle de
l'OS, pas la nôtre : une vignette doit se re-rendre à l'identique dans six
mois. `ops/` reste la source de vérité de ce qui vit **hors** des conteneurs ;
ce qui vit dedans se déclare dans l'image.

## Lancer le job

```sh
docker compose --profile outils run --rm vignettes
docker compose --profile outils run --rm vignettes --plantes <id>,<id>
```

Le service est sous profil : `docker compose up -d` ne le démarre **jamais**.
C'est un job, pas un service.

Il ne monte aucun volume et ne parle qu'à l'API. La prod sert ses assets
depuis `r2` et dev depuis `filesystem` : un montage de répertoire ne marcherait
pas sur la prod. Et c'est le backend qui recalcule `versions.thumbnail` sur les
octets qu'il vient d'écrire — publier une empreinte qui ment devient
impossible.

Rendu seul, sans publication :

```sh
docker run --rm --entrypoint blender arbore-vignettes \
  --background --python /app/rendre.py -- \
  --modele plante.usdz --pot cachepot.usdz --pose '<json>' \
  --sortie vignette.png
```

## Ce que l'app vérifie, et qui fait rejeter une vignette

`PlantThumbnailCache.isLegacyThumbnail` enchaîne quatre contrôles. Une
vignette qui en déclenche un est **téléchargée, examinée, refusée**, et les
cartes gardent l'ancienne image — **sans que rien ne le signale**. C'est
exactement ce qui est arrivé le 30 octobre 2026 à 123 fichiers par ailleurs
irréprochables.

| Contrôle | Rejette quand |
|---|---|
| `hasCurrentDesignMarker` | moins de 3 coins sur 4 à `(94, 28, 186)`, tolérance **5** |
| `isLegacyDarkThumbnail` | ≥ 8 points opaques dont ≥ 7 sous 55 de clarté |
| `hasLegacyWhiteWallDarkFloor` | ≥ 2 des 5 points hauts au-dessus de **225** de clarté |
| `hasTopBackdropSeam` | bord > 185 **et** bord − intérieur > 10, en haut ou en bas |

Deux conséquences pratiques :

**Le fond ne peut pas être aussi clair que celui de l'app.** `#F0EEEA`, le
fond de l'app, mesure 238 de clarté — au-dessus du seuil de 225. Le reprendre
ferait rejeter **tout le catalogue en silence**. Le plafond est écrit dans
`rendre.py` (`CIEL_CLARTE_MAX = 215`) et le rendu s'arrête avec un message
plutôt que de produire 123 fichiers refusés.

**Le contrôle du job doit être au moins aussi strict que l'app.** Un contrôle
plus large laisse passer, en silence, ce que l'app refusera.
`coins_marques` échantillonne les mêmes quatre coins au même retrait de 1,75 %
et applique la même tolérance de 5.

## Réglages non évidents

Aucun n'est un réglage de goût ; chacun corrige un défaut mesuré.

| Réglage | Pourquoi |
|---|---|
| `view_transform = "Standard"` | Blender 4.2 applique **AgX** par défaut, qui désature. Le feuillage sortait vert pâle. SceneKit n'applique aucun tonemapping. |
| Marqueur en `Non-Color` | L'image est lue et réécrite telle quelle. Convertir la couleur en linéaire en supposant que l'écriture reconvertira donne `(29, 3, 125)` : les 4 coins sont refusés. |
| `use_raytracing = False` | Activé, la pelouse déteint sur le pot blanc par rayonnement indirect. Physiquement juste, inacceptable pour un catalogue. |
| `use_shadow_jitter = True` + `shadow_ray_count = 4` + `shadow_step_count = 16` | Sans eux l'ombre est mouchetée : la pénombre est approchée par un flou de la carte d'ombre, et un feuillage fin s'y résout en escalier. |
| Teinte du sol | Le sol est un **décor** : sa clarté est choisie, pas le résultat d'un éclairage physique. L'obtenir en montant les lampes brûle le pot blanc — 2,62 % de pixels saturés contre 0,05 % sur une vignette servie. |
| Mur **émissif** | Sa couleur ne dépend ni des lampes ni de leur distance. Éclairé, il prendrait un dégradé variant avec la taille du sujet : deux fiches voisines n'auraient pas le même fond. |

## Le cadrage est un port, pas une approximation

`cadrer()` reprend littéralement `PlantThumbnailFraming.fit`, profondeur
comprise — c'est elle qui, une fois la caméra inclinée de 8°, fait sortir du
cadre les plantes larges. Recalculer « à peu près » donnerait des vignettes qui
ne se superposent pas aux anciennes : la plante changerait de taille d'une
fiche à l'autre selon celle qui a été régénérée.

Une différence assumée avec le moteur iOS : celui-ci rend le modèle **complet**,
dont le bas EST le fond de son pot. Le job compose une plante servie **sans
pot** avec un cachepot, et les racines descendent plus bas que lui. C'est donc
le fond du **pot** qui touche le sol, pas la boîte englobante — sinon le pot
flotte de cinq centimètres.

## Pièges rencontrés

- **`blender --version | head -1` rend le code de sortie de `head`**, toujours
  0. Une bibliothèque manquante passait le build et n'apparaissait qu'à la
  première exécution. Le `Dockerfile` contrôle désormais les liens avec `ldd`,
  sans tube.
- **Reparenter les maillages détache l'Xform racine**, qui porte la conversion
  Y-up → Z-up de l'importateur USD. Le pot se couche et sa hauteur se mesure
  `0,05865` — son rayon. On reparente les **racines**.
- **Une silhouette à pans n'est pas forcément un autre modèle.** Le cachepot
  paraissait carré en projection orthographique sous un éclairage frontal ; en
  perspective il est rond. Vérifié : ce n'est pas une affaire de subdivision,
  `import_subdiv=True` ne change rien.

## Mesures

Relevées le 2026-10-31 sur `SERVI_Chamaedorea_potless.usdz` (49 Mo) :

```
import USD        0,35 s
rendu 64 éch.     8 min 20   (sous émulation x86 sur un Mac ARM)
sortie            720 x 900, ~580 ko
écrêtage          0,05 %  (identique à la vignette servie)
fond              204 de clarté, plat au pixel près
```

Le temps de rendu est **à remesurer sur le VPS**, qui est nativement x86 :
sous émulation il ne veut rien dire en absolu. Le rapport, lui, vaut : passer
l'ombre en qualité a fait passer le rendu de 4 min 47 à 8 min 20.

## Comment le job s'authentifie

Par **deux clés**, et aucune session Firebase.

```
X-API-Key              ARBORE_API_KEY        choisit la base (prod ou test)
X-Arbore-Internal-Key  ARBORE_INTERNAL_KEY   ouvre les routes /internal/*
```

Trois routes, et rien de plus :

| Route | Pourquoi |
| --- | --- |
| `GET /internal/plants` | savoir quelles plantes rendre |
| `GET /internal/models/:filename` | télécharger le modèle USDZ |
| `POST /internal/models/thumbnails/:plantId` | déposer la vignette rendue |

### Pourquoi pas un compte de service

La première version visait les routes de l'app, sous `protected` : clé d'API
**puis** session Firebase. Un robot ne peut pas tenir de session Firebase, donc
la seule voie était un **compte de service ayant le rôle administrateur** — un
compte humain détourné, avec son mot de passe à conserver dans les secrets, son
jeton à rafraîchir, son UID dans `ARBORE_ADMIN_UIDS`, et le droit d'écrire tout
le catalogue. Pour déposer des images.

Une session **anonyme** ne résout rien : elle suffirait à lire, jamais à
publier, puisque son UID change à chaque ouverture et ne peut donc pas figurer
dans `ARBORE_ADMIN_UIDS`.

Les routes `/internal/*` donnent exactement les trois gestes nécessaires. Elles
ne confèrent **aucun rôle**, n'ouvrent aucune route de compte, et exigent les
deux clés **ensemble** : la clé d'API seule, celle que porte l'app iOS, n'y
donne pas accès.

### Clé absente : la porte se ferme

`ARBORE_INTERNAL_KEY` non renseignée, les routes internes répondent **503
`INTERNAL_ROUTES_DISABLED`**, quoi qu'on leur présente. Une instance qui ne
sert pas de robot n'a donc rien à configurer, et la surface n'existe pas chez
elle — c'est le cas de la prod aujourd'hui.

Un secret non renseigné doit **fermer** la porte, jamais l'ouvrir. Le piège est
précis : `ConstantTimeCompare(fourni, configuré)` jugerait un en-tête vide égal
à une clé vide, et n'importe qui entrerait. Un test le fixe nommément.

503 plutôt que 404, parce qu'un 404 serait indiscernable de celui qu'un hôte mal
apparié renvoie déjà — et on a déjà cherché deux fois la même panne.

Le handler `GET /models/:filename` est **monté deux fois**, sous `protected` et
sous `/internal`, depuis un seul corps (`servePlantModel`). Deux copies auraient
voulu dire deux définitions des contrôles de chemin à garder d'accord.

## Piloter depuis l'atelier

L'atelier expose une page `Vignettes` qui montre ce que chaque environnement
**sert**, et permet de le refaire. Le conteneur web n'a pas accès à Docker, et
c'est très bien ainsi : il **dépose** dans une file, un **ouvrier** consomme —
le motif déjà en place pour les maillages.

```
atelier  --[POST /api/generator/vignettes]-->  file
                                                |
                     vignettes-ouvrier  <-------+  (--surveiller)
                              |
                              +--> rend, contrôle,
                              |    POST /internal/models/thumbnails/<id>
                              +--> livre ou déclare l'échec
```

### Démarrer l'ouvrier

```sh
docker compose --profile vignettes up -d vignettes-ouvrier
```

Il lui faut `ATELIER_BASE`, `ATELIER_CLE` et `ARBORE_ENV_NOM`.

**Un ouvrier ne sert qu'UN environnement.** En veille il ne porte **aucune**
clé de backend : l'atelier joint l'adresse de l'API et ses deux clés à la
tâche qu'il remet. `ARBORE_ENV_NOM` décide seulement de la file où il puise, et
`prendre` filtre sur ce nom — sans ce filtre, un ouvrier de dev réserverait une
tâche de prod, la bloquant vingt minutes.

Un ouvrier branché sur dev n'a donc, à aucun instant, de quoi écrire en
production. Ce n'est pas une consigne qu'on pourrait oublier de suivre : il ne
reçoit jamais le secret.

L'ouvrier est plafonné à 2 cœurs. Un rendu Blender prend tout ce qu'on lui
laisse, et une passe de catalogue dure des heures : sans plafond il affame le
backend qui partage la machine.

### Déclarer les environnements

`VIGNETTES_ENVIRONNEMENTS`, un tableau JSON, de préférence monté par
`VIGNETTES_ENVIRONNEMENTS_PATH` — une variable d'environnement se lit avec
`docker inspect`, un fichier monté non.

```json
[{ "nom": "dev",
   "api": "https://api-dev.arbore.app",
   "apiInterne": "http://backend:8080",
   "cle": "…", "interne": "…" }]
```

### Deux adresses, et il faut les garder distinctes

`api` est l'adresse **publique**. Elle sert à bâtir les URL d'images, que c'est
le **navigateur** qui charge — lui ne joint pas `http://backend:8080`.

`apiInterne` est celle des appels `/internal/*`, faits par le serveur et par
l'ouvrier. Vide, elle retombe sur `api`.

Les confondre mettait **Cloudflare dans le chemin d'un robot interne**. Mesuré
le 2026-11-02 sur dev, mêmes clés et même URL :

```
curl/8.5.0          -> 200
Python-urllib/3.11  -> 403
```

L'ouvrier prenait donc un **403 à chaque tâche**. Déguiser son agent aurait
contourné une règle de bot en se faisant passer pour autre chose, et la règle
peut changer demain. Le trafic d'un robot qui tourne sur la **même machine** que
le backend n'a aucune raison de sortir : `http://backend:8080` ne quitte pas le
pont Docker, évite le CDN, et épargne 2,6 Mo de téléchargement et un envoi par
plante — fois 123.

L'ouvrier annonce par ailleurs un agent qui le nomme. Ce n'est pas la parade,
puisqu'il ne traverse plus de CDN ; mais un robot doit se nommer, et
« Python-urllib » ne dit rien de qui appelle.

`cle` est la clé d'API de l'environnement, `interne` sa clé de routes internes.
Les **deux** sont nécessaires, et aucune ne quitte le serveur — jamais de
`NEXT_PUBLIC_`.

Une entrée sans `interne` reste **chargée**, avec une clé vide, et l'aperçu le
dit en clair. La rejeter en ferait un « environnement inconnu », diagnostic
bien plus difficile à relier à sa cause.

Les **images**, elles, ne demandent aucun secret :
`GET /models/thumbnails/:filename` est une route publique du backend.

### Ce que la page ne peut pas faire

**Comparer la même plante entre deux environnements.** La page montre un
environnement à la fois, avec ses propres fiches. Voir #434.

> ⚠️ **Le motif invoqué ici était faux, et la conclusion reste provisoire.**
>
> On lisait : « les catalogues de dev et de prod comptent 123 fiches chacun et
> n'ont **aucun** identifiant en commun ». Contredit le 2026-11-02 : la liste
> des noms de vignettes, triée et hachée sur les deux machines, est
> **identique**.
>
> ```
> ancien VPS (prod vivante) : 1457d95aee2ac202f468f335f43c29a6   123 png
> nouveau VPS (dev)         : 1457d95aee2ac202f468f335f43c29a6   123 png
> ```
>
> Ce que cela prouve exactement : les **fichiers** sont le même jeu. Que les
> deux **bases** emploient les mêmes identifiants reste à confirmer — les
> fichiers ont pu être copiés en bloc lors de la préparation du nouveau VPS.
>
> La page continue donc de montrer un environnement à la fois, mais par
> prudence et non par impossibilité démontrée. Ce point décide si dev et prod
> peuvent partager un répertoire de vignettes : à trancher avant la bascule de
> #652.

> La base de dev se lit dans `MONGODB_DB`, et **non** dans la base par défaut
> de `MONGODB_URI` — celle-ci pointe sur `arbore_test`, une troisième base de
> 143 fiches que plus personne ne sert. Interroger l'URI sans tenir compte de
> `MONGODB_DB`, c'est mesurer le mauvais catalogue.

### La file est séparée, et elle doit le rester

Les tâches de vignettes vivent dans `etat.vignettes`, **pas** dans
`etat.taches`. `prendre()` rend la première tâche `en_attente` de `taches`
sans filtrer : une tâche de vignette posée là serait réservée par l'ouvrier
Colab, qui échouerait dessus.

Le piège inverse est silencieux. `lire()` reconstruit l'état à partir d'une
liste explicite de clés et **jette tout le reste**, puis `ecrire()` réécrit
l'objet reconstruit. Une clé `vignettes` absente de cette liste serait effacée
au premier dépôt de maillage — donc par l'activité normale du Colab. La clé
est déclarée dans `lire()` **et** dans `VIDE`, et un test le prouve : la
retirer fait tomber sept tests.

L'expiration des vignettes vaut 20 min, et non les 30 des maillages : celles-là
sont dimensionnées sur la mort d'une session Colab et un appel CUDA bloquant.
Et c'est **une tâche par plante** — un lot unique couvrant le catalogue
dépasserait l'expiration et serait remis en attente alors qu'il tourne encore,
mettant deux ouvriers sur le même travail.
