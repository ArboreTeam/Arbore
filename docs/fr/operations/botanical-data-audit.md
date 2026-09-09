# Audit des données botaniques

## Référence actuelle

Audit de la collection de production `arbore.plants`, relevé le 9 septembre 2026 :

```
124 plantes au catalogue
123 portent désormais un botanicalProfile
  0 plante certifiable sur les contraintes critiques
  0 valeur vérifiée sur 1 860 possibles
```

Quatre champs ont été renseignés le 9 septembre (#489) :

| Champ | Couverture | Provenance |
|---|---|---|
| `petToxicity` | 38/124 | ASPCA, source nommée et datée |
| `directSunHours` | 121/124 | dérivé de `sun.durationPerDay` |
| `wateringIntervalDays` | 107/124 | dérivé de `water.frequency` |
| `drainage` | 110/124 | dérivé de `soilAndPot.substrate` |

**« 0 valeur vérifiée » reste exact, et ce n'est pas une contradiction.** L'audit
n'accepte que `reliability: high`, réservée par ce document à une relecture par
un horticulteur ou un botaniste — étape 5 du plan de remplissage. Aucune de ces
valeurs n'a été relue par un humain.

Le vocabulaire employé le dit :

| Valeur | Signification |
|---|---|
| `high` | relue par un humain compétent — **aucune à ce jour** |
| `authoritative` | source faisant autorité, collectée automatiquement (ASPCA) |
| `authoritative-genus` | idem, mais le verdict vaut pour le genre, pas l'espèce |
| `derived` | transcrite depuis la prose de la fiche |

> ⚠️ **Une nuance à trancher.** L'étape 3 du plan demande de « compléter les
> champs **sans déduire** une valeur absente depuis le texte ». Les trois champs
> `derived` transcrivent un nombre explicitement écrit — « 6–8 h / jour » devient
> `{minimum: 6, maximum: 8}` — plutôt qu'ils ne l'infèrent. La frontière est
> mince et mérite d'être arbitrée : ces valeurs peuvent être conservées comme
> indices, ou retirées si la règle doit être stricte.

Le moteur doit donc toujours afficher au mieux **Probablement compatible**. Les
anciens textes et `PlantFlags` restent des indices faibles et ne permettent
jamais d'afficher **Adaptée**.

## Ce que les filtres consomment déjà

Indépendamment de la certification, deux filtres iOS lisent ces données :

- **sécurité** (#488) — `botanicalProfile.petToxicity` d'abord, `flags.toxicToPets`
  ensuite. Une toxicité **non établie exclut** la plante quand l'utilisateur
  demande des plantes sûres : 40 fiches sur 124 subsistent alors ;
- **difficulté** (#485) — `care.difficulty`, jamais renseigné à ce jour, puis
  `flags.easyCare`. Ici l'inconnu **n'exclut pas**.

Les deux règles diffèrent délibérément : masquer une plante inoffensive prive
d'un choix, en proposer une toxique rompt une promesse.

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
7. Étendre ensuite le protocole aux 124 plantes et planifier une revue périodique.

L'IA peut préparer des brouillons et rapprocher des sources, mais elle ne doit ni inventer une valeur ni attribuer elle-même la fiabilité `high`.
