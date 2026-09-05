# Audit des données botaniques

## Référence actuelle

Audit en lecture seule de la collection de production `arbore.plants`, réalisé le 23 juillet 2026 :

- 124 plantes au catalogue ;
- 0 profil `botanicalProfile` ;
- 0 plante certifiable sur les contraintes critiques ;
- 0 valeur vérifiée sur 1 860 valeurs possibles (124 plantes × 15 champs).

Le moteur doit donc afficher au mieux **Probablement compatible** tant que les profils ne sont pas renseignés. Les anciens textes et `PlantFlags` restent des indices faibles et ne permettent jamais d'afficher **Adaptée**.

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
