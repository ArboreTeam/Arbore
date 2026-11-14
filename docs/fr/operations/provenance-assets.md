# Provenance des assets

Arbore affiche des photographies, des modèles 3D et des données botaniques qu'il
n'a pas tous produits. Cette page dit d'où vient chaque chose et sous quel
régime nous l'utilisons.

Elle existe parce que la question s'est posée au pire moment : en remplissant
**Content Rights** dans App Store Connect, un formulaire qui fait déclarer qu'on
détient les droits sur tout contenu tiers affiché. Aucune source écrite ne
permettait alors d'y répondre. Le dépôt est propriétaire, tous droits réservés,
et n'avait jamais consigné ce qu'il emprunte.

## Le tableau

| Asset | Où | Origine | Régime |
|---|---|---|---|
| Photographies des styles de jardin | `ArboreUi/ArboreUi/Assets/Assets.xcassets/StylesImages/` | **Unsplash** | licence Unsplash |
| Images du catalogue de plantes | catalogue | **Unsplash** | licence Unsplash |
| Modèles 3D des plantes (`.usdz`) | hors dépôt, servis par `GET /models/:filename` | **générés sous contrat payant** | détenus |
| Vignettes des plantes | rendues hors appareil par un job Blender, depuis les modèles 3D | dérivées de ce qui précède | détenues |
| Données de toxicité | `Plant.Flags.ToxicToPets` / `ToxicToChildren` | **ASPCA** | faits, attribués |
| Estimation climatique | `ArboreBackend/climate.go` | interne | champ `Attribution` |

## Ce que la licence Unsplash autorise, et ce qu'elle interdit

Elle accorde un usage **gratuit, y compris commercial, sans attribution ni
autorisation préalable**. C'est ce qui rend la déclaration App Store exacte :
nous détenons bien les droits nécessaires.

Deux limites, qu'Arbore ne franchit pas :

- **revendre les photographies telles quelles** — nous ne vendons rien ;
- **constituer un service concurrent d'Unsplash** en compilant ses photos.
  Illustrer quatre styles de jardin dans un questionnaire n'en est pas un.

Un point qui compte pour la suite : **`UNSPLASH_ACCESS_KEY` est mort depuis le
retrait de l'AiGenerator (#558)**. Les images sont *embarquées* dans le bundle
et dans le catalogue ; il n'y a plus aucun appel d'API au moment de l'exécution.
Aucune condition tierce ne peut donc changer dans notre dos sur du contenu déjà
livré.

## Les modèles 3D

Générés sous contrat payant à partir d'images, puis optimisés par nos soins
(`optimize_models.py`, et les correctifs de liaison de textures SceneKit). Ils ne
sont pas versionnés — trop volumineux — et sont déployés hors bande vers le
stockage objet, cf. [`stockage-assets.md`](stockage-assets.md).

## Les données de toxicité

Elles ne viennent **pas du texte des fiches** mais de drapeaux structurés, seuls
sourcés, et l'app affiche la source à l'utilisateur :

```go
// catalog_context.go
b.WriteString("- ⚠️ Toxique pour les animaux domestiques (source ASPCA)\n")
```

Ce sont des faits scientifiques attribués, pas une œuvre reprise. L'abstention y
est une décision et non un oubli (#489) : sans drapeau, on ne dit rien plutôt
que de rassurer à tort.

### Ce que cette affirmation couvre, et ce qu'elle ne couvre pas

Elle porte sur ce qui est **servi**. Relevé le 2026-11-14 sur `arbore` et
`arbore_dev` : 274 fiches, 542 verdicts, aucun document ne porte de champ de
prose repris d'une mise en forme externe, et les 24 verdicts sans source nommée
sont **tous `unknown`**. L'invariant tient des deux côtés.

Le corpus de recherche hors dépôt, lui, n'offre pas cette garantie. Il peut
porter des champs calqués sur la présentation d'une base externe — et sans
source renseignée. Tant qu'il n'est pas versé, le catalogue reste exempt ; mais
c'est le **versement** qui doit le vérifier, pas la relecture.

**Règle : sans source nommée, pas de prose.** Un verdict peut être posé sans
source — `toxic` et `unknown` n'affirment pas l'innocuité, ils n'ont rien à
soutenir, et retirer un avertissement faute de source rendrait le catalogue
moins sûr plutôt que plus honnête. Le `safe` sans source, lui, est refusé de
longue date : il AFFIRME.

Le détail, lui, n'est pas du même ordre. Composé de champs calqués sur la
présentation d'une base externe, il est une formulation et non un fait : le
servir sans dire d'où il vient, c'est reprendre une rédaction au lieu de citer.
`verser-toxicite.py` ne l'écrit donc plus qu'avec une source retenue, et
l'invariant se dit dans les deux sens — `detail` et `evidence` sont présents
ensemble ou absents ensemble.

Le garde vit à la frontière, comme celui qui existe sur le rapprochement des
noms (cf. [`botanical-data-audit.md`](botanical-data-audit.md)), et non à la
relecture.

Une reformulation attribuée reste un fait attribué ; une formulation reprise
sans source ne l'est plus. C'est l'attribution qui fait la différence, et elle
se vérifie à la frontière.

## Si un asset change

Toute image ou modèle ajouté doit apparaître dans le tableau ci-dessus **avant**
d'être livré. Une provenance qu'on ne peut plus reconstituer est une provenance
perdue : les fichiers ne portent pas leur origine, et la mémoire de l'équipe ne
tient pas six mois.

La déclaration **Content Rights** d'App Store Connect n'est pas révisée à chaque
version — elle vaut jusqu'à ce qu'on la change. Introduire un asset dont les
droits ne sont pas clairs la rendrait fausse sans qu'aucun écran ne prévienne.

## Voir aussi

- [`publication-app-store.md`](publication-app-store.md) — où cette déclaration se remplit
- [`stockage-assets.md`](stockage-assets.md) — comment les modèles 3D sont servis
- [`../../appstore-listing.md`](../../appstore-listing.md) — les réponses App Privacy
