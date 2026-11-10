# De la collecte à la plante servie

Cette page décrit la chaîne **de bout en bout** : comment une plante passe d'une
entrée de collecte à un modèle 3D posable en réalité augmentée, avec ses
données et sa vignette, sur l'environnement de développement.

Chaque segment a sa page détaillée ; celle-ci dit **l'ordre, les dépendances et
ce qui bloque quoi**. Elle existe parce que ces informations n'étaient nulle
part : il fallait interroger le serveur pour reconstituer l'enchaînement.

```
collecte → corpus de recherche → enrichissement par agents → traduction
                                          ↓
                           file de l'atelier → ouvrier GPU
                                          ↓
                                  REVUE HUMAINE
                                          ↓
                            coupe · USDZ · LOD (CPU)
                                          ↓
                              import Mongo → vignettes
                                          ↓
                                  déploiement dev
```

**Une règle traverse toute la chaîne** : une valeur vient d'une source nommée et
datée, ou elle n'existe pas. Jamais d'une prose, jamais d'une devinette. C'est
l'objet de #792, et une valeur absente se dit `unknown` — elle ne se
comble pas.

---

## 1 · Collecte

L'entrée de la chaîne produit, par plante, **une image de référence** et **un
jeu d'attributs structurés**. Ce sont les deux seules choses dont l'aval a
besoin.

L'image sert deux fois : elle alimente le générateur 3D, et c'est elle que
l'utilisateur voit dans le catalogue avant qu'une vignette ne soit rendue.

Les attributs utiles, dans l'ordre de ce qu'ils débloquent :

| attribut | ce qu'il permet |
|---|---|
| nom et **binôme latin** | la clé de tout le reste : l'appariement avec les bases horticoles |
| **hauteur adulte** | la pose à la bonne échelle en AR, et le gabarit `size` |
| exposition | le filtre lumière et la pose automatique selon la luminosité |
| typologie (port, usages) | `kinds` et `goals`, en valeurs closes |
| période de floraison | le trait `flowering`, y compris son `no` explicite |
| distance de plantation | la densité de pose en extérieur |

**Deux pièges mesurés à la collecte**, qui coûtent plus tard :

- **une image trop petite ne reconstruit pas.** Sous 400 px de côté, le
  générateur invente plus qu'il ne reconstruit : mesuré sur une vignette de
  167×200 qui a produit trois plantes flottantes. Les images utilisables font
  760×760 ;
- **un nom tronqué casse l'appariement en silence.** Un nom de 64 caractères
  face à un modèle qui en attend 65 ne lève aucune erreur : la plante et son
  modèle ne se retrouvent simplement jamais.

La conversion des attributs en valeurs structurées se fait **ici, à la
frontière** — « 20 à 30 cm » devient `{minimum: 20, maximum: 30}` une fois,
avec sa provenance attachée. Voir
[l'audit des données botaniques](botanical-data-audit.md) pour pourquoi cette
conversion n'a sa place nulle part ailleurs.

## 2 · Enrichissement par agents

La collecte ne donne pas tout. Trois familles de données viennent de **bases
horticoles externes**, interrogées par des agents de recherche :

| axe | source d'autorité |
|---|---|
| toxicité animaux / enfants | base toxicologique nommée, verdict en valeur close |
| couleurs (fleur **et** feuillage) | NC State Extension Gardener Plant Toolbox, Missouri Botanical Garden |
| intervalle d'arrosage | extensions universitaires (Clemson, Iowa State, UAEX) |
| hauteur adulte manquante | NC State, MOBOT |

### La méthode, et ce qu'elle a coûté d'apprendre

**Indexer, pas interroger au mot-clé.** Le `sitemap` de NC State donne 18 196
slugs de taxons, souvent au niveau cultivar : le récupérer et le parcourir
localement vaut mieux que des recherches successives.

**Le cultivar décide, pas l'espèce.** *Photinia* × *fraseri* n'est pas rouge,
'Red Robin' l'est. *Thuja occidentalis* monte à 15 m, 'Smaragd' s'arrête à 4.
Chercher au niveau de l'espèce quand le cultivar est connu donne une réponse
fausse avec l'air d'être juste.

**La moitié du travail est de refuser.** Sur le lot couleur, 28 groupes
mentionnaient « silver » ou « bronze » sur leur page sans que la couleur soit
sur la face visible : face inférieure, nervure, couleur d'automne, écorce, ou
un autre cultivar que celui de la fiche.

### Trois pièges techniques à ne pas redécouvrir

1. **Trois fiches MOBOT rendent un CAPTCHA, pas une 404.** Le HTML contient
   « Complete the puzzle to continue » et se parse en **zéro champ**, donc en
   « la base est muette ». Sans garde-fou, on conclut à une absence sur des
   taxons que la base documente. Taxonid 276162, 276164, 276174.
2. **Le Plant Finder de MOBOT a deux points d'entrée et un seul marche.**
   `PlantFinderListResults.aspx?basic=<q>` rend les résultats ;
   `PlantFinderSearchResults.aspx` rend un 500 systématique. Et la recherche
   n'accepte qu'un ou deux mots.
3. **RHS est une application monopage.** Son HTML ne contient aucun nom de
   plante et son API rend 404 : inexploitable sans navigateur.

### Un plafond qui n'est pas un manque

Les bases sérieuses **refusent de publier un calendrier d'arrosage**, et c'est
leur position, pas un trou. Clemson HGIC, verbatim : « A common question from
gardeners is "How often should I water my plants?" **There is no pat answer to
this question.** » Mesuré : 320 fiches de culture RHS sondées, 22 existent,
**3 seulement** donnent un intervalle en jours.

Les valeurs viennent donc de **classes d'arrosage que les sources définissent
elles-mêmes** — arbres et arbustes, vivaces, cactées, orchidées, aromatiques —
et pas de verdicts par espèce. D'où la fiabilité `low` dominante sur cet axe :
elle dit exactement « source nommée, taxon non nommé ».

### Écrire sans se perdre

Plusieurs agents écrivent dans les mêmes fichiers. Le motif qui tient :

- **relire juste avant d'écrire**, ne poser que sa propre clé, relire après ;
- **ne jamais écraser** une valeur déjà posée ;
- **vérifier par hachage** que le bloc de traductions n'a pas bougé.

Ce dernier point n'est pas décoratif : ces fichiers portent 2,8 millions de
caractères de traduction qu'une écriture maladroite perdrait.

## 3 · Traduction

Les fiches sont rédigées en anglais, puis traduites en français, espagnol et
allemand **par agents**, jamais par un service de traduction automatique.

La raison est de fond : une fiche de plante porte des noms d'espèces, des
unités et des verdicts de toxicité. Une traduction automatique les reformule
sans savoir lesquels sont des termes fermés, et un verdict reformulé n'est plus
un verdict.

**Un champ traduit ne décide jamais rien.** C'est l'acquis de #792 :
les filtres, les scores et les verdicts lisent des valeurs closes, identiques
dans toutes les langues. Une plante non traduite dans la langue du lecteur doit
être filtrée **exactement comme** une plante traduite.

## 4 · L'atelier et l'ouvrier

Voir [l'atelier 3D](atelier-3d.md) pour le détail. Les trois propriétés à
retenir ici :

**Le sens du contrôle est inversé.** L'ouvrier GPU n'a pas d'API d'exécution :
l'atelier tient une file, et l'ouvrier vient y puiser. Rien ne pousse.

**L'artefact coûteux est produit une fois.** Le maillage du GPU est stable ;
tout l'aval est du CPU rejouable. Le jour où le retrait de pot s'améliore, on
le repasse sans régénérer.

**Un portillon qualité rejette avant de dépenser.** Une forme dégénérée — une
« dalle » — rend le remaillage pathologique : mesuré, trois essais à 3060,
4077 et 2123 secondes, tous rejetés ensuite. Un essai sain du même lot : 405
secondes. Le portillon mesure donc la planarité **sur le maillage brut, avant
tout texturage**.

## 5 · La revue humaine

**C'est la seule intervention humaine de la chaîne, et elle répond à deux
questions d'un coup** : la plante est-elle valide, et quelle coupe de pot
garder ?

Les aperçus et les candidats de coupe sont produits **avant** la revue
précisément pour ça. Une plante invalidée retourne en file avec une graine
neuve ; une plante validée part vers l'aval CPU.

C'est le goulot réel de la chaîne : le GPU produit plus vite qu'un humain ne
tranche.

## 6 · Coupe, USDZ et niveaux de détail

Du CPU, rejouable. Trois sorties :

- le maillage **coupé** (sans son pot d'origine), pour qu'un cache-pot
  utilisateur puisse être posé dessous ;
- la conversion en **USDZ**, le format que SceneKit sait lire ;
- les **niveaux de détail**, un modèle léger et un lourd, échangés selon la
  distance.

Un piège connu : SceneKit exige une liaison **directe** des textures dans le
USDZ. Un fichier produit par un aller-retour glTF donne des plantes grises.

## 7 · Import en base

Par [`appliquer-ops-mongo.py`](../../../data/generator/appliquer-ops-mongo.py),
jamais à la main. Ses garde-fous, tous nés d'un incident :

- **`--base` est obligatoire et sans valeur par défaut**, pour qu'une
  étourderie ne vise jamais la production ;
- **sans `--appliquer`, le script ne fait que compter** ce qu'il ferait ;
- **l'URI ne passe pas par la ligne de commande**, pour ne pas apparaître dans
  l'historique ni dans `ps` ;
- **une opération dont le filtre ne trouve rien est signalée**, pas
  silencieusement ignorée : c'est le symptôme d'un catalogue qui a bougé ;
- **le script est rejouable.**

### Ne jamais écraser

Un import qui écrase appauvrit en prétendant enrichir. Mesuré : lors de
l'import du corpus vers les fiches servies, **146 valeurs ont été conservées**
parce qu'elles existaient déjà et étaient mieux renseignées que la source.

### Un champ qui décrit n'est pas un champ qui tranche

`environments` (intérieur / extérieur) a été importé puis **retiré**. La raison
mérite d'être retenue : c'est un **classement commercial**, pas un fait
botanique, et le moteur lui donnait le pouvoir du **conflit critique**, son
verdict le plus sévère. Sur un balcon, il excluait d'un coup 75 plantes sur
123, dont des succulentes qui y vivent très bien.

Avant d'importer un champ, demander : **décrit-il la plante, ou décide-t-il à
sa place ?**

## 8 · Vignettes

Voir [le rendu des vignettes](vignettes-rendu.md). Deux choses :

**Après l'import, jamais avant** : une vignette est nommée d'après la fiche, et
le script la vise par son `_id`.

**Un ouvrier ne sert qu'une file**, celle de son environnement. Deux ouvriers
puisant dans la même file produisent des empreintes fausses.

## 9 · Déploiement

Voir [les environnements](environnements.md). Le résumé :

```sh
cd <racine> && ARBORE_ENV=dev ARBORE_DEPLOY_BRANCH=dev ./deploy.sh
```

**Trois pièges, tous rencontrés en vrai :**

- **`ARBORE_DEPLOY_BRANCH=dev` est obligatoire.** Sans lui le script refuse,
  parce que son défaut est `main` ;
- **pas de `sudo`.** Le symptôme visible a disparu, pas la raison : sous
  `sudo`, `$HOME` vaut `/root`, la clé de déchiffrement est introuvable, et le
  déploiement **s'annonce terminé en tournant sur les anciens secrets** ;
- **attendre la publication des images.** Sinon le script se replie
  silencieusement sur une construction locale, et ce qui tourne n'est plus ce
  que l'intégration a produit.

**La seule preuve qu'un déploiement a eu lieu est le commit servi :**

```sh
curl -s https://<api>/health | jq -r .commit
```

Pas la sortie du script. Un workflow nommé « Deploy » a laissé croire pendant
des semaines que la production suivait sa branche, alors qu'elle avait quinze
commits de retard dont un correctif de sécurité.

---

## Ce qui bloque quoi

| pour obtenir | il faut d'abord |
|---|---|
| un modèle 3D | une image d'au moins 400 px de côté |
| une pose à la bonne échelle | la **hauteur adulte** |
| le gabarit `size` | la hauteur adulte (il en dérive) |
| une plante proposable au questionnaire | sa **toxicité établie** sur l'axe demandé |
| des scores qui se distinguent | plusieurs axes renseignés, pas un seul |
| une vignette | la fiche en base |
| un USDZ servi | la revue humaine |

La dernière ligne est la plus coûteuse : **tout l'aval attend un humain.**
