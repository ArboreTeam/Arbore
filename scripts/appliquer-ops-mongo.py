#!/usr/bin/env python3
"""Applique à une base les opérations produites par les scripts de catalogue.

Séparé de la préparation, et volontairement : la préparation se relit sans
risque, l'écriture non. Ce script ne décide de rien — il applique un fichier
d'opérations déjà produit et relu.

## Les quatre sections, et comment chacune vise sa cible

| section | vise | par |
|---|---|---|
| `plantes` | collection `plants` | `modelURL` — seule valeur que l'atelier, le disque et le catalogue partagent |
| `nouvelles` | collection `plants` | **rien** : ce sont des fiches qui n'existent pas encore |
| `vignettes` | collection `plants` | `_id` — une vignette est nommée d'après la fiche |
| `pots` | collection `pots` | `name` pour une entrée complète, `modelURL` pour une mise à jour |

Une entrée qui porte un champ `set` **met à jour** ; une entrée sans `set` est
un document complet, **inséré ou remplacé**. C'est ce qui permet au même script
de poser la bibliothèque de pots et, plus tard, d'y écrire une empreinte.

## Pourquoi `nouvelles` est une section à part, et non un `upsert`

Mesuré le 2026-11-11 : 206 modèles `_potless` servis en dev contre **123 fiches
au catalogue**, donc 153 modèles que rien n'affiche. Il fallait pouvoir créer
des fiches, et ce script ne savait que mettre à jour.

Un `upsert` sur la section `plantes` aurait suffi techniquement. Il a été
écarté : sa cible est `modelURL`, et un `modelURL` mal orthographié aurait créé
une fiche fantôme au lieu de signaler une plante introuvable — exactement le
signal que le garde-fou « plantes introuvables » existe pour donner. Créer et
mettre à jour sont deux gestes, ils restent deux sections.

## Garde-fous

  - `--base` est obligatoire et doit être nommée explicitement. Aucun défaut,
    pour qu'une étourderie ne vise jamais la production.
  - sans `--appliquer`, le script ne fait que compter ce qu'il ferait.
  - l'URI ne transite jamais par la ligne de commande : elle est lue dans
    `MONGODB_URI`, pour ne pas apparaître dans l'historique ni dans `ps`.
  - une opération dont le filtre ne trouve rien est signalée, pas silencieusement
    ignorée : c'est le symptôme d'un catalogue qui a bougé.
  - le script est **rejouable**. Pour les plantes, le filtre vise l'ancien
    `modelURL` ; une plante déjà basculée ne s'y reconnaît plus, alors on la
    retrouve par son nouveau nom et on lui réapplique la mise à jour. Sans ça,
    une passe ultérieure qui ajoute un champ n'atteindrait jamais les plantes
    de la première passe.

## Garde-fous propres à l'insertion

  - **un document qui porte un `_id` le garde.** C'est ce qui rend la
    promotion d'un environnement à l'autre possible sans re-rendre les
    vignettes, dont le nom de fichier EST cet identifiant. Voir
    `avec_identifiant`.
  - **une fiche dont le `modelURL` existe déjà n'est jamais insérée**, ni
    remplacée. Elle est comptée à part. Insérer un doublon donnerait deux
    fiches pour une plante, dont une sans vignette et sans historique.
  - **`--modeles` fait vérifier que le fichier du modèle est sur le disque**
    avant d'écrire la fiche qui le désigne. L'ordre n'est pas négociable :
    déployer les USDZ, puis écrire en base. L'inverse publie une fiche qui
    pointe vers un 404.
  - **`imageURLs` est posé après l'insertion**, pas avant : l'URL contient
    l'`_id`, que Mongo génère. C'est la seule raison pour laquelle cette
    section écrit en deux temps.
  - un champ obligatoire manquant fait **refuser la fiche**, pas planter le
    lot : les autres passent et le compte rendu nomme les recalées.
  - **une traduction mal typée fait refuser la fiche.** Voir `ecarts_de_forme`.

  MONGODB_URI=... python3 scripts/appliquer-ops-mongo.py \\
      --ops ops.json --base arbore_dev [--appliquer] \\
      [--modeles /chemin/vers/models-dev]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Champs sans lesquels une fiche n'est pas servable. `imageURLs` n'en est pas :
# il se remplit après l'insertion, l'URL portant l'identifiant.
CHAMPS_REQUIS = ("name", "type", "description", "modelURL", "translations",
                 "botanicalProfile")

# Gabarit de l'image de catalogue, relevé sur les 123 fiches servies : une
# seule URL par fiche, toutes identiques à l'identifiant près.
#
# Elle désigne `api.arbore.app` y compris dans `arbore_dev`. C'est l'état
# constaté, repris tel quel pour ne pas introduire une seconde convention au
# milieu du catalogue ; `--images-base` permet d'en changer sciemment.
IMAGES_BASE = "https://api.arbore.app"
IMAGES_VERSION = "v22"

# Forme de `translations.<langue>`, relevée sur les structures Go qui la
# décodent (`LanguageData` et ses sept sous-structures, ArboreBackend/main.go).
# `l` vaut liste de chaînes, `s` vaut chaîne.
#
# Ce tableau est une COPIE d'un contrat qui vit ailleurs, ce qui est un défaut
# assumé : le seul moyen de ne pas le copier serait de lire le source Go depuis
# un script Python, ce qui coûterait plus qu'il ne rapporte. Les champs n'ont
# pas changé depuis l'origine du catalogue.
FORME_LANGUE: dict[str, dict[str, str]] = {
    "": {"description": "s", "plantType": "s"},
    "sun": {"lightType": "s", "durationPerDay": "s", "orientation": "s",
            "windowDistance": "s", "recommendedRooms": "l", "tips": "l"},
    "water": {"frequency": "s", "amount": "s", "method": "s", "humidity": "s",
              "signsLack": "s", "signsExcess": "s", "recommendedWater": "s"},
    "soilAndPot": {"substrate": "s", "drainage": "s", "potSize": "s",
                   "repotFrequency": "s", "repotSigns": "s"},
    "health": {"commonProblems": "l", "symptomsAndCauses": "l", "pests": "l",
               "treatments": "l", "prevention": "l"},
    "lifeCycle": {"growth": "s", "flowering": "s", "dormancy": "s",
                  "fertilizer": "s", "pruning": "s"},
    "care": {"difficulty": "s", "weekly": "l", "monthly": "l", "yearly": "l",
             "extraTips": "l"},
}


def ecarts_de_forme(doc: dict) -> list[str]:
    """Nomme les champs de `translations` dont le TYPE casserait le décodage Go.

    ## Pourquoi ce contrôle existe, et pourquoi il est à cet endroit

    Le 2026-11-11, 126 fiches ont été insérées avec `health.symptomsAndCauses`,
    `treatments` et `prevention` en chaînes alors que `HealthInfo` les déclare
    en `[]string`. `GET /internal/plants` a aussitôt rendu 500 pour TOUT le
    catalogue : `cursor.All` décode le curseur entier, donc une seule fiche mal
    typée rend les 249 autres inservables — et le rendu des vignettes, qui lit
    ce catalogue, s'arrête avec lui.

    C'est la raison d'être du garde-fou, et la raison de sa place : ici, au
    moment d'écrire. Un tel écart ne se voit pas à la relecture d'un JSON, ne
    casse rien à l'insertion, et ne se manifeste qu'au prochain appel du
    catalogue, sous la forme d'un message qui ne nomme aucune fiche.

    ## Ce qu'il refuse, et ce qu'il laisse passer

    **Seul un mauvais type est refusé.** Un champ absent ou `null` est laissé
    passer : Go lui donne sa valeur zéro et le décodage réussit. Un champ en
    trop l'est aussi, Go l'ignore. Refuser l'un ou l'autre écarterait des
    fiches parfaitement servables, et ce contrôle n'a pas à devenir un second
    schéma rédactionnel — il ne répond que de ce qui casse.

    Rend la liste des écarts, chacun nommé `langue.champ` pour qu'on sache quoi
    corriger sans relire la fiche.
    """
    attendu = {"l": list, "s": str}
    ecarts: list[str] = []
    for langue, bloc in (doc.get("translations") or {}).items():
        if not isinstance(bloc, dict):
            ecarts.append(f"{langue} n'est pas un objet")
            continue
        for section, champs in FORME_LANGUE.items():
            source = bloc if section == "" else bloc.get(section)
            if source is None:
                continue  # section absente : valeur zéro côté Go, pas un écart
            if not isinstance(source, dict):
                ecarts.append(f"{langue}.{section} n'est pas un objet")
                continue
            for champ, genre in champs.items():
                v = source.get(champ)
                if v is None:
                    continue
                if not isinstance(v, attendu[genre]):
                    ou = f"{langue}.{champ}" if section == "" else f"{langue}.{section}.{champ}"
                    veut = "liste" if genre == "l" else "chaîne"
                    ecarts.append(f"{ou} est {type(v).__name__}, attendu {veut}")
                elif genre == "l" and not all(isinstance(x, str) for x in v):
                    ou = f"{langue}.{section}.{champ}" if section else f"{langue}.{champ}"
                    ecarts.append(f"{ou} contient un élément non-chaîne")
    return ecarts


def cibler_plantes(plants, ops: list[dict]) -> tuple[list[tuple[dict, dict]], list[str], int]:
    """Associe chaque opération au filtre qui la trouve réellement."""
    a_faire, introuvables, rejouees = [], [], 0
    for o in ops:
        if plants.find_one({"modelURL": o["modelURL"]}, {"_id": 1}):
            a_faire.append(({"modelURL": o["modelURL"]}, o["set"]))
            continue
        # Déjà basculée : le filtre vise l'ancien nom, elle porte le nouveau.
        nouveau = o["set"].get("modelURL")
        if nouveau and plants.find_one({"modelURL": nouveau}, {"_id": 1}):
            a_faire.append(({"modelURL": nouveau}, o["set"]))
            rejouees += 1
            continue
        introuvables.append(o["modelURL"])
    return a_faire, introuvables, rejouees


def avec_identifiant(doc: dict, ObjectId) -> dict:
    """Rend le document prêt à insérer, son `_id` converti s'il en porte un.

    ## Pourquoi un document peut arriver avec son identifiant

    Promouvoir une fiche de `arbore_dev` vers `arbore` exige de **garder son
    `_id`** : le fichier de vignette est nommé d'après lui, et `imageURLs` le
    contient. Laisser Mongo en générer un neuf obligerait à re-rendre les 151
    vignettes au lieu de copier 82 Mo de PNG déjà calculés.

    Ce n'est pas une liberté nouvelle, c'est l'invariant du catalogue : les
    deux bases emploient déjà les mêmes identifiants pour une même plante —
    relevé le 2026-11-05, les 51 `_id` de dev existaient tous en prod. Préserver
    l'`_id` maintient cet invariant ; le laisser dériver le casserait.

    L'identifiant voyage en Extended JSON (`{"$oid": "..."}`), la forme que
    `json` sait écrire et que Mongo attend de retrouver en ObjectId.
    """
    d = dict(doc)
    brut = d.get("_id")
    if isinstance(brut, dict) and "$oid" in brut:
        d["_id"] = ObjectId(brut["$oid"])
    elif isinstance(brut, str):
        d["_id"] = ObjectId(brut)
    return d


def trier_nouvelles(plants, docs: list[dict], modeles: Path | None):
    """Sépare ce qui s'insère de ce qui ne doit pas l'être.

    Rend (à_insérer, déjà_au_catalogue, refusées) où `refusées` porte le motif,
    pour qu'une fiche écartée le soit avec sa raison et non par omission.
    """
    a_inserer, deja, refusees = [], [], []
    vus: set[str] = set()
    for d in docs:
        url = d.get("modelURL")
        if not url:
            refusees.append(("(sans modelURL)", "modelURL absent"))
            continue
        manquants = [c for c in CHAMPS_REQUIS if not d.get(c)]
        if manquants:
            refusees.append((url, f"champs manquants : {', '.join(manquants)}"))
            continue
        # Avant le doublon et avant le disque : une fiche mal typée n'a pas à
        # être départagée, elle est irrecevable quoi qu'en dise le reste.
        ecarts = ecarts_de_forme(d)
        if ecarts:
            refusees.append((url, "traduction mal typée — " + " ; ".join(ecarts[:3])
                             + (f" (+{len(ecarts) - 3})" if len(ecarts) > 3 else "")))
            continue
        # Un doublon à l'intérieur du MÊME fichier d'opérations : il ne serait
        # pas vu par la requête, les deux insertions ayant lieu après.
        if url in vus:
            refusees.append((url, "présent deux fois dans le fichier d'opérations"))
            continue
        if plants.find_one({"modelURL": url}, {"_id": 1}):
            deja.append(url)
            continue
        if modeles is not None and not (modeles / url).exists():
            refusees.append((url, "modèle absent du disque — déployer les USDZ d'abord"))
            continue
        vus.add(url)
        a_inserer.append(d)
    return a_inserer, deja, refusees


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", required=True)
    ap.add_argument("--base", required=True, help="nom de la base, à nommer explicitement")
    ap.add_argument("--appliquer", action="store_true", help="sans ce drapeau, rien n'est écrit")
    ap.add_argument("--modeles", type=Path,
                    help="répertoire des USDZ servis ; vérifie qu'une fiche insérée "
                         "ne pointe pas vers un fichier absent")
    ap.add_argument("--images-base", default=IMAGES_BASE,
                    help=f"hôte des images de catalogue (défaut : {IMAGES_BASE})")
    args = ap.parse_args()

    uri = os.environ.get("MONGODB_URI", "").strip()
    if not uri:
        print("MONGODB_URI absente de l'environnement", file=sys.stderr)
        return 2

    from pymongo import MongoClient  # importé tard : absent des machines sans ce besoin
    from bson import ObjectId

    ops = json.load(open(args.ops, encoding="utf-8"))
    db = MongoClient(uri)[args.base]
    plants, pots = db["plants"], db["pots"]

    a_faire, introuvables, rejouees = cibler_plantes(plants, ops.get("plantes") or [])

    vignettes, sans_fiche = [], []
    for v in ops.get("vignettes") or []:
        try:
            oid = ObjectId(v["id"])
        except Exception:  # noqa: BLE001
            sans_fiche.append(v["id"])
            continue
        if plants.find_one({"_id": oid}, {"_id": 1}):
            vignettes.append(({"_id": oid}, v["set"]))
        else:
            # Une vignette servie dont plus aucune fiche ne porte l'identifiant.
            sans_fiche.append(v["id"])

    entrees_pots = ops.get("pots") or []
    a_inserer, deja, refusees = trier_nouvelles(
        plants, ops.get("nouvelles") or [], args.modeles)

    print(f"  plantes à écrire       : {len(a_faire)}", file=sys.stderr)
    print(f"  dont déjà basculées    : {rejouees}", file=sys.stderr)
    print(f"  plantes introuvables   : {len(introuvables)} {introuvables[:5]}", file=sys.stderr)
    print(f"  fiches à créer         : {len(a_inserer)}", file=sys.stderr)
    print(f"  dont déjà au catalogue : {len(deja)} {deja[:5]}", file=sys.stderr)
    print(f"  fiches refusées        : {len(refusees)}", file=sys.stderr)
    for url, motif in refusees[:10]:
        print(f"      {url} — {motif}", file=sys.stderr)
    print(f"  vignettes à écrire     : {len(vignettes)}", file=sys.stderr)
    print(f"  vignettes sans fiche   : {len(sans_fiche)} {sans_fiche[:5]}", file=sys.stderr)
    print(f"  pots                   : {len(entrees_pots)}", file=sys.stderr)
    if a_inserer and args.modeles is None:
        print("  ⚠️  sans --modeles, rien ne garantit que les USDZ désignés "
              "sont déployés", file=sys.stderr)

    if not args.appliquer:
        print("  — simulation, rien n'a été écrit (ajouter --appliquer)", file=sys.stderr)
        return 0

    for filtre, maj in a_faire + vignettes:
        plants.update_one(filtre, {"$set": maj})
    for p in entrees_pots:
        if "set" in p:
            pots.update_one({"modelURL": p["modelURL"]}, {"$set": p["set"]})
        else:
            pots.update_one({"name": p["name"]}, {"$set": p}, upsert=True)

    # Les fiches une par une, et non en lot : une insertion groupée s'arrête à
    # la première qui échoue, laissant la moitié du lot écrite sans qu'on sache
    # laquelle. Ici chaque échec est nommé et les autres passent.
    crees, echecs, gardes = [], [], 0
    for d in a_inserer:
        doc = avec_identifiant(d, ObjectId)
        if "_id" in doc:
            gardes += 1
        try:
            oid = plants.insert_one(doc).inserted_id
        except Exception as e:  # noqa: BLE001
            echecs.append((d.get("modelURL"), str(e)[:120]))
            continue
        # Seconde moitié du geste : l'image de catalogue porte l'identifiant,
        # qui n'existait pas avant cette ligne.
        plants.update_one({"_id": oid}, {"$set": {"imageURLs": [
            f"{args.images_base.rstrip('/')}/models/thumbnails/{oid}.png"
            f"?v={IMAGES_VERSION}"]}})
        crees.append((d["modelURL"], str(oid)))

    print(f"  écrit dans {args.base} : {len(a_faire)} plantes, {len(crees)} fiches créées, "
          f"{len(vignettes)} vignettes, {len(entrees_pots)} pots", file=sys.stderr)
    if gardes:
        print(f"  dont {gardes} avec leur identifiant d'origine conservé "
              f"(les vignettes déjà rendues restent valables)", file=sys.stderr)
    for url, err in echecs:
        print(f"      ÉCHEC {url} — {err}", file=sys.stderr)
    if crees:
        print("  identifiants créés (à donner au rendu des vignettes) :", file=sys.stderr)
        for url, oid in crees:
            print(f"      {oid}  {url}", file=sys.stderr)
    return 1 if echecs else 0


if __name__ == "__main__":
    sys.exit(main())
