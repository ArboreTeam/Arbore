#!/usr/bin/env python3
"""Renseigne `botanicalProfile.petToxicity` depuis la liste ASPCA. (#489)

## Pourquoi l'ASPCA plutôt qu'une API

La toxicité est une donnée de sécurité : elle mérite sa source faisant autorité.
Trefle et Perenual citent tous deux l'ASPCA — passer par eux ajoute un
intermédiaire sans ajouter d'autorité, et impose une correspondance de noms
approximative qu'aucun des deux ne garantit. À 124 fiches, le volume ne justifie
pas cette prise de risque.

## Ce que le script écrit, et ce qu'il n'écrit pas

Il écrit `botanicalProfile.petToxicity`, un fait accompagné de sa provenance
(`PlantDataEvidence`) : source, URL, date de relevé.

Il n'écrit **PAS** dans `flags`. Créer un objet `flags` partiel rendrait
`plant.flags != nil` côté client, et le wizard traiterait alors les onze autres
booléens — laissés à `false` — comme faisant autorité. Une plante deviendrait
« non tolérante à l'ombre » du seul fait qu'on a renseigné sa toxicité.

Il n'écrit **PAS** `childToxicity`. L'ASPCA couvre chiens, chats et chevaux :
elle ne dit rien des enfants. Déduire l'un de l'autre serait inventer.

## Correspondance des noms

Deux cas seulement sont retenus, et la distinction est essentielle :

  - **espèce exacte** — `hosta plantaginea` ↔ `Hosta plantaginea` ;
  - **genre entier** — une entrée ASPCA en `spp.` / `species` vise le genre,
    donc s'applique à toutes ses espèces : `rhododendron spp` couvre
    *Rhododendron obtusum*.

Une entrée nommant une AUTRE espèce du même genre n'est pas retenue :
`hydrangea arborescens` ne dit rien de *Hydrangea macrophylla*. Transférer un
verdict entre espèces sœurs serait une erreur de sécurité.

## Absence n'est pas innocuité

La liste ASPCA compte environ 470 plantes notables, pas un référentiel exhaustif.
Une espèce absente reste donc **inconnue** — jamais « non toxique ». C'est
pourquoi rien n'est écrit dans ce cas : un champ vide se lit comme une question
ouverte, une valeur fausse se lit comme une réponse.

## Usage

    python3 scripts/enrich-pet-toxicity.py --aspca aspca.json --plants plants.json
    python3 scripts/enrich-pet-toxicity.py … --out updates.json

La sortie est un fichier d'opérations à appliquer par `mongosh`. Le script ne
touche à aucune base : il produit, on relit, on applique.
"""
import argparse, json, re, sys
from datetime import date

SOURCE_NAME = "ASPCA Animal Poison Control"
SOURCE_URL = "https://www.aspca.org/pet-care/aspca-poison-control/toxic-and-non-toxic-plants"
GENRE_ENTIER = {"spp", "species", "sp"}


def normalise(nom: str) -> str:
    """Nom scientifique comparable : minuscules, sans auteur ni cultivar."""
    n = nom.lower().strip()
    n = re.sub(r"\(.*?\)", " ", n)
    n = re.sub(r"['\"].*?['\"]", " ", n)
    n = re.sub(r"[^a-z× ]", " ", n)
    return re.sub(r"\s+", " ", n).strip()


def index_genre(aspca: dict) -> dict:
    """Entrées valant pour un genre entier, indexées par genre."""
    out = {}
    for cle, val in aspca.items():
        mots = cle.split()
        if len(mots) == 2 and mots[1] in GENRE_ENTIER:
            out[mots[0]] = (cle, val)
    return out


def verdict(nom: str, aspca: dict, genres: dict):
    """(clé ASPCA, entrée, précision) ou (None, None, None)."""
    n = normalise(nom)
    mots = n.split()
    espece = " ".join(mots[:2]) if len(mots) >= 2 else n

    if n in aspca:
        return n, aspca[n], "espèce"
    if espece in aspca:
        return espece, aspca[espece], "espèce"
    if mots and mots[0] in genres:
        cle, val = genres[mots[0]]
        return cle, val, "genre"
    return None, None, None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--aspca", required=True, help="JSON produit par aspca_collect.py")
    ap.add_argument("--plants", required=True, help="catalogue JSON (réponse de /plants)")
    ap.add_argument("--out", help="fichier d'opérations ; défaut : affichage seul")
    args = ap.parse_args()

    aspca = json.load(open(args.aspca))
    brut = json.load(open(args.plants))
    plants = brut if isinstance(brut, list) else brut.get("plants", [])
    genres = index_genre(aspca)

    aujourdhui = date.today().isoformat()
    operations, inconnues = [], []

    for p in plants:
        cle, entree, precision = verdict(p["name"], aspca, genres)
        if not entree:
            inconnues.append(p["name"])
            continue

        toxique = bool(entree["toxicTo"])
        if toxique:
            valeur = "toxic to " + ", ".join(entree["toxicTo"])
        elif entree["safeFor"]:
            valeur = "non-toxic"
        else:
            inconnues.append(p["name"])
            continue

        operations.append({
            "id": p["id"],
            "name": p["name"],
            "match": cle,
            "precision": precision,
            "petToxicity": {
                "value": valeur,
                "evidence": {
                    "sourceName": SOURCE_NAME,
                    "sourceURL": SOURCE_URL,
                    "reviewedAt": aujourdhui,
                    # « genre » signale un verdict valant pour tout le genre :
                    # exact au sens de l'ASPCA, mais moins précis qu'une espèce.
                    "reliability": "authoritative" if precision == "espèce" else "authoritative-genus",
                },
            },
        })

    toxiques = sum(1 for o in operations if o["petToxicity"]["value"] != "non-toxic")
    print(f"  fiches            : {len(plants)}", file=sys.stderr)
    print(f"  verdicts obtenus  : {len(operations)}  ({toxiques} toxiques)", file=sys.stderr)
    print(f"  restent inconnues : {len(inconnues)}", file=sys.stderr)

    if args.out:
        with open(args.out, "w") as f:
            json.dump(operations, f, ensure_ascii=False, indent=1)
        print(f"  écrit             : {args.out}", file=sys.stderr)
    else:
        for o in operations[:10]:
            print(f"    {o['name'][:38]:40} {o['petToxicity']['value']}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
