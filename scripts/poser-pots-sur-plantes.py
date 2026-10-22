#!/usr/bin/env python3
"""Prépare la pose du pot sur les plantes recoupées. (#609 étape 4 et 6, #623)

## Ce que ce script transporte

L'atelier 3D produit des plantes **sans leur pot** et mesure, au passage, le
socle sur lequel le pot vient se poser : son centre, son rayon, la hauteur de sa
lèvre. Cette mesure vit dans `etat.json`, enfouie sous la tâche qui l'a produite
— `taches[].resultat.candidats_pot[].socle` — alors que le catalogue en a besoin
sur la fiche de la plante.

Ce script fait le pont. Il ne touche à rien : il lit `etat.json` et **émet des
opérations**, comme les autres scripts de catalogue du dépôt, pour que
l'écriture reste un geste séparé, relu et daté.

## Pourquoi la clé est `modelURL` et non l'identifiant de la plante

L'atelier nomme ses plantes par le fichier de leur modèle (`Aglaonema_Mix`), le
catalogue par un ObjectID. Faire la jointure ici demanderait un export du
catalogue, donc un accès à la base au moment de la préparation — exactement ce
qu'on cherche à éviter. `modelURL` est la seule valeur que les deux côtés
partagent déjà, et elle est unique.

## Pourquoi le modèle recoupé change de nom

Le modèle recoupé ne remplace pas l'ancien, il se pose à côté, avec le suffixe
`_potless`. Trois raisons, dans l'ordre d'importance :

  - le cache iOS est indexé par **nom de fichier** et `Documents/Models/`
    survit aux mises à jour (#294). Écraser un fichier sous le même nom
    n'atteindrait aucun téléphone l'ayant déjà téléchargé — c'est ce qui s'est
    passé avec #292, où les testeurs gardaient le gris jusqu'à réinstallation ;
  - `GardenLocalStore` persiste `modelURLString` dans chaque jardin enregistré.
    L'ancien fichier doit rester servi, sinon les jardins déjà créés cassent ;
  - l'opération devient purement additive : aucun modèle en service n'est
    touché, et un retour en arrière se fait en remettant l'ancien `modelURL`.

## La hauteur, et ce qu'elle mesure

`hauteurCm` est relevée **depuis la terre**, pas depuis le bas du pot — « le pot
change, la plante non, et c'est la plante qu'on pose » (`web/lib/generator/
depot.ts`). C'est exactement la sémantique d'un maillage recoupé, donc elle se
porte telle quelle en `heightMeters`.

Vérifié sur les 4 plantes qui portent `hauteur_vegetal` ET un maillage sur le
disque : la boîte englobante du recoupé vaut la hauteur depuis la terre à
**×1,00**. Le client peut donc mettre à l'échelle sur sa boîte englobante.

Réserve, à ne pas oublier : une plante retombante descend **sous** la ligne de
terre, sa boîte est donc plus haute que `heightMeters` et la mettre à l'échelle
sur la boîte la rapetisserait. `potBase.groundY` est ce qui permettrait de le
corriger — il manque sur 48 des 52. Aucune des 7 retombantes du lot ne porte la
mesure, donc l'écart n'est à ce jour **pas vérifiable**.

## Ce que le script ne fait pas

Il n'invente aucun socle, et il ne bascule **que** les plantes dont le socle est
posable. Une plante validée sans candidat retenu, ou dont le candidat ne porte
pas de socle, ressort dans `sans_socle` et **garde son modèle actuel** : la
basculer l'afficherait sans pot et sans possibilité d'en poser un, ce qui est
pire que son modèle d'origine, pot compris.

  python3 scripts/poser-pots-sur-plantes.py --etat etat.json [--out ops.json]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any

# Suffixe du modèle recoupé. Il nomme ce que le fichier EST — une variante sans
# pot — et non une version, pour ne pas entrer en collision avec le
# `modelVersion` qu'envisage #294.
SUFFIXE_RECOUPE = "_potless"

# Correspondance entre les noms de l'atelier et ceux de l'API. Les trois
# derniers champs du socle ne sont pas toujours mesurés.
CHAMPS_SOCLE = {
    "x": "x",
    "y": "y",
    "z": "z",
    "rayon": "radius",
    "y_terre": "groundY",
    "hauteur_vegetal": "plantHeight",
}


def socle_de_la_coupe(taches: list[dict], plante: str, coupe: str) -> dict | None:
    """Socle du candidat effectivement retenu par l'opérateur.

    Une plante peut avoir été relancée plusieurs fois sur des graines
    différentes, donc porter plusieurs tâches. Seul compte le candidat dont le
    fichier est celui que l'opérateur a choisi ; à égalité, le plus récent,
    parce qu'une relance remplace le maillage sur le disque.
    """
    trouves = []
    for t in taches:
        if t.get("plante") != plante:
            continue
        resultat = t.get("resultat")
        if not isinstance(resultat, dict):
            continue
        for c in resultat.get("candidats_pot") or []:
            if os.path.basename(c.get("fichier", "")) != coupe:
                continue
            socle = c.get("socle")
            if isinstance(socle, dict) and socle:
                trouves.append((t.get("pris") or t.get("depose") or 0, socle))
    if not trouves:
        return None
    return max(trouves, key=lambda x: x[0])[1]


def convertir_socle(socle: dict) -> dict[str, float]:
    """Traduit le socle de l'atelier vers le `potBase` de l'API.

    Les champs absents sont omis plutôt que mis à zéro : un zéro se confondrait
    avec une mesure, alors qu'une absence doit rester lisible côté base.
    """
    out: dict[str, float] = {}
    for source, cible in CHAMPS_SOCLE.items():
        v = socle.get(source)
        if isinstance(v, (int, float)):
            out[cible] = float(v)
    return out


def hauteur_metres(plante: dict) -> float | None:
    """Hauteur réelle en mètres, depuis la terre, ou None si non mesurée.

    L'atelier relève des centimètres ; l'AR raisonne en mètres, et c'est l'unité
    de la constante que ce champ remplace côté client.
    """
    cm = (plante.get("taille") or {}).get("hauteurCm")
    if not isinstance(cm, (int, float)) or cm <= 0:
        return None
    return round(float(cm) / 100.0, 4)


def operations(etat: dict) -> dict[str, Any]:
    """Opérations à appliquer, et ce qui n'a pas pu l'être."""
    plantes = etat.get("plantes") or {}
    taches = etat.get("taches") or []

    poser, sans_socle, sans_coupe = [], [], []
    for nom, p in sorted(plantes.items()):
        if p.get("verdict") != "validee":
            continue
        coupe = p.get("coupe")
        if not coupe:
            sans_coupe.append(nom)
            continue
        socle = socle_de_la_coupe(taches, nom, coupe)
        if not socle:
            sans_socle.append(nom)
            continue
        base = convertir_socle(socle)
        if "radius" not in base or base["radius"] <= 0:
            # Sans rayon, l'échelle du pot n'existe pas : le backend refuserait
            # de servir un pot de toute façon.
            sans_socle.append(nom)
            continue
        maj = {
            "modelURL": f"{nom}{SUFFIXE_RECOUPE}.usdz",
            "potless": True,
            "potBase": base,
        }
        hauteur = hauteur_metres(p)
        if hauteur is not None:
            maj["heightMeters"] = hauteur
        poser.append({
            # Le filtre porte sur le modèle ACTUEL de la plante ; la mise à
            # jour la fait pointer sur le recoupé, déposé à côté de lui.
            "modelURL": f"{nom}.usdz",
            "set": maj,
        })

    pots = []
    for fichier, pot in sorted((etat.get("pots") or {}).items()):
        rayon = pot.get("rayon")
        if not isinstance(rayon, (int, float)) or rayon <= 0:
            continue
        nom = os.path.splitext(fichier)[0]
        pots.append({
            "name": nom,
            "modelURL": f"{nom}.usdz",
            "rimRadius": float(rayon),
            "height": float(pot.get("hauteur") or 0.0),
            "default": False,  # posé ci-dessous sur le premier
        })
    if pots:
        pots[0]["default"] = True

    return {"plantes": poser, "pots": pots,
            "sans_socle": sans_socle, "sans_coupe": sans_coupe}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--etat", required=True, help="etat.json de l'atelier")
    ap.add_argument("--out", help="fichier d'opérations à écrire")
    args = ap.parse_args()

    etat = json.load(open(args.etat, encoding="utf-8"))
    ops = operations(etat)

    validees = sum(1 for p in (etat.get("plantes") or {}).values()
                   if p.get("verdict") == "validee")
    print(f"  validées              : {validees}", file=sys.stderr)
    print(f"  socle posable         : {len(ops['plantes'])}", file=sys.stderr)
    print(f"  validées sans coupe   : {len(ops['sans_coupe'])}", file=sys.stderr)
    print(f"  coupe mais sans socle : {len(ops['sans_socle'])}"
          f" {ops['sans_socle'][:5]}", file=sys.stderr)
    manquants = [c for c in ("groundY", "plantHeight")
                 if ops["plantes"] and any(c not in o["set"]["potBase"] for o in ops["plantes"])]
    for c in manquants:
        n = sum(1 for o in ops["plantes"] if c not in o["set"]["potBase"])
        print(f"  sans {c:12}     : {n}/{len(ops['plantes'])}", file=sys.stderr)
    print(f"  pots en bibliothèque  : {len(ops['pots'])}", file=sys.stderr)
    if ops["pots"]:
        print("  ATTENTION : le modèle USDZ de chaque pot reste à produire et à"
              " déployer avant que ces entrées ne servent à quoi que ce soit.",
              file=sys.stderr)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(ops, f, ensure_ascii=False, indent=1)
        print(f"  écrit : {args.out}", file=sys.stderr)
    else:
        json.dump(ops, sys.stdout, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
