# L'atelier 3D — comment on fabrique une plante

> Mesuré et vérifié le 2026-11-06. L'atelier existait depuis #609 sans
> document : son fonctionnement vivait dans des issues (#600, #609, #623, #638,
> #681, #682, #684), ce qui obligeait à le reconstituer de mémoire à chaque
> fois. Ce document le fixe.

## Ce que c'est

Une **route protégée de `web.arbore.app`**, pas un service de plus. TLS,
authentification et pare-feu d'origine verrouillé sur Cloudflare y sont déjà :
un service supplémentaire serait une surface d'attaque de plus, et un oubli de
plus le jour d'un durcissement.

Il sert à transformer une **image de plante** en **modèle 3D servi par l'app**,
avec une seule intervention humaine : la revue.

## Le sens du contrôle est inversé

**Colab tire le travail.** Il n'a aucune API d'exécution, et les contournements
par pilotage de navigateur cassent à la première évolution de l'interface.
L'atelier ne pousse donc jamais : il tient une file, et l'ouvrier vient y
puiser.

```
file de l'atelier → ouvrier GPU (Colab) → portillon qualité → relance, graine neuve ↺
                                                ↓ accepté
                            CPU : aperçus + candidats de coupe du pot
                                                ↓
                              REVUE HUMAINE : valider ? quelle coupe ?
                           ↙ invalidée                        ↘ validée
              retour en file, autre graine          CPU : coupe, conversion USDZ, LOD
```

Deux propriétés tiennent tout le reste :

- **une seule intervention humaine.** Les aperçus et les candidats de coupe
  sont produits *avant* la revue, pour que le même regard réponde aux deux
  questions ;
- **l'artefact coûteux est produit une fois.** Le GLB du GPU est stable ; tout
  l'aval est du CPU rejouable. Le jour où le retrait du pot s'améliore, on le
  repasse sans régénérer.

## Où vivent les choses

| | chemin | contenu |
| --- | --- | --- |
| plan de travail | `GENERATOR_DATA_HOST_PATH`, soit `data/generator` | tout l'état de l'atelier |
| état | `data/generator/etat.json` | `taches`, `plantes`, `pots`, `sources`, `empreintes`, `vignettes` |
| par plante | `data/generator/plantes/<Nom>/` | `<Nom>.glb`, `sanspot_*.glb`, `apercu_*.png` |
| coupes prêtes | `data/generator/sortie_light/` | un GLB par plante recoupée |
| modèles servis | `arbore-data/models-<env>/` | USDZ servis par le backend, `heavy/` pour les LOD lourds |

L'atelier vit sur la pile **dev**, pas sur la production : c'est là que les
itérations d'essai doivent avoir lieu. Un seul atelier existe, délibérément.

## Lire `etat.json` sans se tromper

C'est le piège principal, et il coûte cher.

### `verdict` — le jugement sur la PLANTE

`validee`, `invalidee`, `ecartee`, ou absent. Mesuré le 2026-11-06 sur 78
plantes : 67 validées, 7 invalidées, 2 écartées, 2 sans verdict.

### `coupe` — le jugement sur le RETRAIT DU POT

Porte le nom du fichier retenu, `sanspot_geometrie.glb` ou
`sanspot_couleur.glb`.

> ⚠️ **Son absence enregistre un REFUS, pas un oubli.** Les `sanspot_*.glb`
> qui restent sur le disque sont les tentatives **rejetées**. L'atelier les
> conserve.

Le 2026-11-06 j'ai conclu l'inverse : voyant trois plantes validées avec un
`sanspot_*.glb` sur le disque mais sans `coupe` déclarée, j'ai cru à un
désaccord entre le fichier et le disque, et je les ai annoncées comme « les
plus avancées du lot, il ne leur manque que la conversion ». Converties puis
ouvertes, elles montraient un pot intact et déchiré sur deux d'entre elles, et
un tronc amputé sur la troisième. **Seul `coupe` fait foi ; la présence d'un
fichier ne dit rien de sa qualité.**

### Les deux méthodes de coupe

| | ce qu'elle fait | retenue |
| --- | --- | --- |
| `sanspot_geometrie.glb` | sépare par la géométrie | **52 fois sur 58** |
| `sanspot_couleur.glb` | sépare par la couleur | 6 fois |

Vérifié sur un cas à deux candidats (Washingtonia) : `geometrie` conserve le
tronc, `couleur` l'a confondu avec le pot et l'a retiré. La répartition n'est
donc pas arbitraire.

## Les ouvriers de vignettes — un par FILE

À ne pas confondre avec l'ouvrier Colab, qui génère les maillages. Ceux-ci
rendent les **vignettes** du catalogue, sous Blender.

Un ouvrier ne sert **qu'une file**, celle de son `ARBORE_ENV_NOM` ; le code
refuse de démarrer sans elle. L'atelier, lui, en tient autant qu'il déclare
d'environnements dans `VIGNETTES_ENVIRONNEMENTS`.

```
ARBORE_PROFILS=vignettes,vignettes-prod

  arbore-dev-vignettes-ouvrier        ARBORE_ENV_NOM=dev
  arbore-dev-vignettes-ouvrier-prod   ARBORE_ENV_NOM=prod
```

Les deux vivent sur la pile qui porte l'**atelier**. C'est l'atelier qui
serait néfaste en double — deux `etat.json`, et la question « lequel dit
vrai ? » avait produit 54 empreintes fausses. Deux ouvriers puisant dans le
même atelier n'ont pas ce problème.

Détails de leur fonctionnement, du rattachement réseau qu'ils exigent et du
contrôle des empreintes : [`vignettes-rendu.md`](vignettes-rendu.md).

## De la coupe au catalogue

Une plante validée n'est pas pour autant livrable. Il lui faut, dans cet
ordre :

1. **une `taille`** — hauteur réelle de l'exemplaire, posée sur la page
   `/generator/tailles` et **non** pendant la revue des coupes : c'est une
   seconde intervention humaine, avec sa propre méthode (le pot sert de règle,
   la hauteur se mesure depuis la terre). Sans elle, pas de `heightMeters`,
   donc pas de pose à l'échelle. Voir
   [`chaine-plante.md`](chaine-plante.md) ;
2. **une `coupe` acceptée**, si l'on veut une plante sans pot ;
3. **la conversion GLB → USDZ** par
   `Plant3DGenerator/usdz_sans_reduction.py`, qui ne réduit rien (arbitrage du
   2026-10-22) et fait seulement ce qu'ARKit exige : reliure **directe** des
   textures contre le gris de #292, `subdivisionScheme = "none"`,
   `usdzip --arkitAsset`. Exige `usdcat` et `usdzip` ;
4. **un `potBase`** mesuré, sans quoi le backend ne sert aucun pot, par
   conception ;
5. **les opérations de catalogue** : `modelURL`, `potless`, `hasHeavy`,
   `heightMeters`, `versions.model` ;
6. **la vignette**, rendue et publiée par la route interne pour que le backend
   calcule lui-même son empreinte.

Le nommage du fichier produit suit la règle de #773, documentée dans
[`../3d-lod-architecture.md`](../3d-lod-architecture.md) : le nom dit ce que le
fichier **est**, `<Nom>.usdz` avec son pot, `<Nom>_potless.usdz` sans.

## Ce qu'exige une fiche plante

L'atelier ne produit que le maillage. La fiche, elle, porte bien davantage, et
son schéma est documenté dans
[`../architecture/04-data-model.md`](../architecture/04-data-model.md),
collection `plants`. En résumé de ce qu'il faut réunir par plante :

| | champ | remarque |
| --- | --- | --- |
| identité | `name`, `type`, `description`, `imageURLs` | |
| 4 langues | `translations` | `fr`, `en`, `es`, `de` ; chacune porte description, type, soleil, eau, sol et pot, santé, cycle de vie, entretien |
| recommandation | `flags` | 12 booléens qui alimentent le wizard |
| horticulture | `botanicalProfile` | 15 faits, **chacun avec sa provenance** (`sourceName`, `sourceURL`, `reviewedAt`, `reliability`) |
| 3D | `modelURL`, `potless`, `potBase`, `hasHeavy`, `heightMeters`, `versions` | |
| provenance | `source`, `sourceUrl` | |

> ⚠️ **La toxicité apparaît à deux endroits, et ils ne jouent pas le même
> rôle.** `flags.toxicToPets` et `flags.toxicToChildren` sont des booléens qui
> **filtrent** la recommandation du wizard ; `botanicalProfile.petToxicity` et
> `childToxicity` sont des faits **sourcés** qui s'affichent à l'utilisateur.
> Les premiers décident, les seconds expliquent. Une fiche qui n'aurait que les
> seconds laisserait le wizard recommander une plante toxique à un foyer avec
> animaux.

`PlantDataEvidence` existe pour que la provenance soit portée **par valeur** et
non par fiche : une fiche n'est pas vérifiée parce qu'un seul de ses champs a
une source.

## Chiffres mesurés, à ne pas réapprendre

| | |
| --- | --- |
| génération | ~0,3 unité de calcul par plante, catalogue complet sous 2 € |
| VRAM | **10,27 Go**, contre 24 annoncés par le README de TRELLIS |
| retrait du pot | **CPU seul**, quelques secondes |
| conversion USDZ | ~3,5 s par modèle, 4 modèles en 14 s |
| poids d'un TRELLIS | 35 à 60 Mo en USDZ, contre 2 à 7 Mo pour l'ancienne génération |
| rendu d'une vignette | 249 s par plante avec pot, mesuré sur 51 |

Trois pistes ont été **fermées par la mesure** et ne se rouvrent pas sans
élément neuf : la génération **multi-vue** (n'apporte pas d'information), le
**changement de moteur** (on quitterait un moteur MIT pour une pile non
commerciale), le **détecteur de pot froissé** (sept critères, aucun ne sépare).

## Voir aussi

- [`vignettes-rendu.md`](vignettes-rendu.md) — le rendu et la publication des vignettes
- [`../3d-lod-architecture.md`](../3d-lod-architecture.md) — LOD, nomenclature, cache par empreinte
- [`../architecture/04-data-model.md`](../architecture/04-data-model.md) — le schéma complet d'une fiche
- [`provenance-assets.md`](provenance-assets.md) — licences et provenance
