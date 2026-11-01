# Rendu des vignettes du catalogue

Les vignettes du catalogue sont rendues par un **job en conteneur**, hors de
tout environnement Apple. Elles l'étaient auparavant depuis l'app, écran par
écran, par un écran d'administration — une opération manuelle qu'il fallait
rejouer à chaque changement de modèle.

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
