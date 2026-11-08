# Audit des données botaniques

## Référence actuelle

Relevé le 2026-11-08 sur le corpus de recherche (`BotanicScraper/data`), que la
production importe au fil des générations 3D :

```
1021 fiches portant un botanicalProfile
   0 erreur au validateur (BotanicScraper/valider-lot.py)
 144 fiches dans les quatre langues, 877 en anglais seul
```

| Champ | Couverture | Provenance |
|---|---|---|
| `petToxicity` · `childToxicity` | **1021** | base nommée et datée, verdict en valeur close |
| `environments` | **1021** | typologie fermée `usages` (#777) |
| `kinds` | 981 | typologie fermée `port` (#777) + genre |
| `easyCare` | 999 | `_meta.difficulty`, trois niveaux |
| `directSunHours` | 920 | champ « Exposition » de la fiche produit |
| `matureHeightCm` | 793 | champ « Hauteur adulte », normalisé en cm |
| `size` | 791 | seuils appliqués à `matureHeightCm` |
| `goals` | 656 | typologie fermée `usages` |
| `flowering` | 398 | champ « Période de floraison » |
| `droughtTolerance` | 320 | champ « Résistant au sec », **positif seulement** |
| `plantingDistanceCm` | 258 | champ « Distance de plantation » |
| `colors` | **0** | *aucune source close n'existe dans le corpus* |

**Aucune de ces valeurs n'est dérivée d'une prose.** Toutes viennent soit d'une
base toxicologique nommée, soit d'un champ structuré de la page produit, soit
d'une typologie fermée. C'est l'objet de #792, et une garde automatisée le
vérifie : un test ouvre les fichiers de remplissage et refuse tout accès à
`description`, `translations` ou `name`.

### Deux trous mesurés, à ne pas découvrir deux fois

**`colors` n'a aucune source**, nulle part. Le seul champ parlant de couleur est
`feuillage` — 461 fiches, 73 valeurs distinctes, en prose libre (« FEUILLAGE
PANACHÉ DE JAUNE »). Le filtre par couleur ne filtrera donc rien tant qu'une
source n'existe pas, ou tant qu'on ne l'assume pas.

**La fiabilité reste basse sur les axes horticoles.** Les champs tirés de la
page produit portent `reliability: "low"` : c'est un chiffre de marchand, bon
pour borner une poignée d'interface, pas pour certifier. Seule la toxicité
atteint `high`, parce qu'elle cite une base toxicologique.

## Ce que les filtres consomment déjà

Indépendamment de la certification, deux filtres iOS lisent ces données :

- **sécurité** (#488, #787) — `botanicalProfile.petToxicity` d'abord,
  `flags.toxicToPets` ensuite. Le repli a deux règles, et chacune a été violée
  avant #792 : **un fait présent décide même quand il dit `unknown`**, et le
  `false` d'un drapeau ne vaut pas une innocuité démontrée. Les deux politiques
  sont nommées — `.browsable` laisse voir l'indéterminé marqué, `.offerable`
  l'exclut ;
- **difficulté** (#485) — `botanicalProfile.easyCare` d'abord, renseigné sur
  **999 fiches sur 1021**, puis `care.difficulty`, puis `flags.easyCare`. Ici
  l'inconnu **n'exclut pas**.

Les deux règles diffèrent délibérément : masquer une plante inoffensive prive
d'un choix, en proposer une toxique rompt une promesse.

**Une difficulté d'entretien ne dépend pas de la langue du lecteur.** Cette page
décrivait `care.difficulty` comme lu « sous `translations.<langue>.care` », ce
qui est encore vrai du repli et constitue un défaut au même titre que le
`detail` de toxicité affiché en anglais par #790. La valeur close de `easyCare`
le ferme pour 999 fiches ; les 22 restantes le subissent encore.

## Lancer l'audit

L'outil [`scripts/audit_botanical_catalog.py`](../../../scripts/audit_botanical_catalog.py) accepte un export JSON de `GET /plants` :

```sh
python3 scripts/audit_botanical_catalog.py \
  --input plants.json \
  --csv botanical-audit.csv
```

Il peut aussi lire l'API protégée. Les secrets restent dans les variables d'environnement et ne doivent jamais être ajoutés au dépôt :

```sh
ARBORE_API_KEY="…" \
ARBORE_FIREBASE_TOKEN="…" \
python3 scripts/audit_botanical_catalog.py \
  --url https://api.arbore.app/plants \
  --csv botanical-audit.csv
```

Le rapport distingue :

- champ absent ;
- champ présent mais insuffisamment sourcé ;
- couverture vérifiée ;
- plante certifiable sur les champs critiques.

## Outils d'enrichissement

Deux scripts, à lancer dans cet ordre. Aucun n'écrit en base : ils produisent
un fichier d'opérations que l'on relit avant de l'appliquer par `mongosh`.

```sh
# 1. Collecter la liste ASPCA (toxicité chiens / chats / chevaux)
python3 scripts/collect-aspca-toxicity.py          # → aspca.json

# 2. Rapprocher le catalogue et produire les opérations
python3 scripts/enrich-pet-toxicity.py \
  --aspca aspca.json --plants plants.json --out ops.json
```

Le fichier de plantes attendu est un export de `GET /plants`, comme pour l'audit.

**Une règle inscrite dans ces scripts, à ne pas défaire :** le rapprochement des
noms ne retient que l'espèce exacte, ou une entrée ASPCA en `spp.` qui vise le
genre entier. Une entrée nommant une **autre** espèce du même genre est écartée
— `hydrangea arborescens` ne dit rien de *Hydrangea macrophylla*. Sans cette
règle, 72 fiches recevraient un verdict emprunté.

### Ne plus jamais dériver une valeur depuis la prose (#792)

Un troisième script vivait ici : `derive-botanical-profile.py`, qui tirait
soleil, arrosage et drainage de la **description** des fiches. **Il est
supprimé**, et cette page le recommandait — c'est-à-dire qu'elle prescrivait
exactement la pratique que #792 a fermée.

La règle qui l'accompagnait mérite d'être citée, parce qu'elle est le meilleur
argument contre la méthode qu'elle protégeait :

> « La dérivation refuse tout fragment mentionnant des centimètres : "arrose
> quand les 2 à 3 premiers centimètres sont secs" décrit une profondeur de sol,
> pas une périodicité. En tirer "tous les 2 à 3 jours" serait une erreur d'un
> facteur cinq, **invisible à la relecture**. »

Le garde-fou est juste, et le piège était réel. Mais une méthode dont il faut
énumérer les façons de se tromper n'est pas une source. Une valeur dérivée à la
lecture ne peut être ni relue, ni datée, ni contredite ; elle dépend en plus de
la langue affichée.

**Parser à l'entrée, stocker le résultat, ne jamais dériver à la lecture.** Le
scraper parse le HTML de botanic et convertit « 20 à 30 cm » en
`{minimum: 20, maximum: 30}` — une fois, à la frontière, avec la provenance
attachée. C'est là que le parsing a sa place, et nulle part ailleurs.

## Critères d'acceptation

Une valeur vérifiée possède :

- une source nommée ou une URL ;
- une date de revue ;
- une fiabilité `high`.

Les sept champs critiques suivis par l'audit sont : environnement intérieur/extérieur, température minimale, soleil direct, largeur adulte, volume minimal du pot et toxicité animaux/enfants. Les huit autres champs restent nécessaires pour une recommandation utile et explicable.

## Plan de remplissage

1. Identifier les 30 plantes les plus vues/placées et celles disponibles chez le premier partenaire.
2. Renseigner les noms scientifiques et éliminer les doublons ou entrées trop génériques avant toute recherche.
3. Compléter les 15 champs sans déduire une valeur absente depuis le texte marketing.
4. Attacher les preuves champ par champ, avec priorité aux bases botaniques reconnues, organismes publics et sources toxicologiques dédiées.
5. Faire relire le lot par un horticulteur ou botaniste ; la date de cette revue devient `reviewedAt`.
6. Relancer l'audit et n'autoriser **Adaptée** qu'après couverture critique complète.
7. Étendre ensuite le protocole aux 1021 fiches et planifier une revue périodique.

L'IA peut préparer des brouillons et rapprocher des sources, mais elle ne doit ni inventer une valeur ni attribuer elle-même la fiabilité `high`.
