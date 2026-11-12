#!/usr/bin/env python3
"""Porte la toxicité rédigée vers le profil botanique du catalogue. (#809)

Comme les autres scripts de catalogue, il n'ouvre aucune base : il lit les
fiches rédigées et **émet des opérations**, que `appliquer-ops-mongo.py`
applique après relecture.

## Ce qu'il répare

Les 126 fiches insérées le 2026-11-11 portent chacune un bloc `_meta.toxicity`
rédigé sur sources nommées — 654 sources, médiane 5 par fiche. Ce bloc n'a
jamais été transporté : `botanicalProfile.petToxicity` était présent sur 113
des 123 fiches préexistantes et sur **0** des nouvelles.

Conséquence mesurée : 126 plantes servies **sans verdict de toxicité**, dont
des plantes réellement toxiques. Le client n'affiche alors rien plutôt qu'une
fausse innocuité (`Plant.verdict` ne retient du drapeau de repli que son
`true`), donc le défaut n'est pas dangereux — il est muet.

## La traduction des deux booléens vers le vocabulaire fermé

Le bloc rédigé porte DEUX booléens, et c'est leur croisement qui décide :

| `toxic` | `toxicityEstablished` | verdict | pourquoi |
|---|---|---|---|
| `true`  | peu importe | `toxic`   | le drapeau se lève par prudence |
| `false` | `true`      | `safe`    | une source nommée affirme l'innocuité |
| `false` | `false`     | `unknown` | rien d'établi — surtout pas « sûr » |

`toxicityEstablished` existe précisément pour cette ligne-là. Sans lui, « aucune
base n'a d'entrée » et « l'ASPCA dit non toxique » s'écrasaient sur le même
`false`, et **31 des 126 fiches seraient entrées au catalogue comme prouvées
sûres**. C'est la régression #778/#781, et `unknown` est la valeur qu'aucun
booléen ne savait dire.

## Pourquoi le verdict enfant n'est pas déduit de `toxicTo`

`toxicTo` ne liste `humans` que sur une partie des fiches. L'absence d'une
espèce dans cette liste n'établit pas son innocuité pour elle : une plante
toxique reste `toxic` pour l'enfant aussi, et seule une innocuité établie
donne `safe`. Déduire `safe` d'une liste muette serait exactement l'erreur que
`toxicityEstablished` existe pour empêcher.

## Pourquoi ce script n'écrit PAS `flags`

`PlantFlags` ne sait dire que oui ou non. Y poser `toxicToPets: false` sur une
fiche dont la toxicité est inconnue réintroduirait le défaut que #778 a retiré
des données et que #792 a retiré du client. Le fait, lui, sait dire `unknown` :
on ne renseigne que le fait.

  python3 scripts/verser-toxicite.py --nouvelles <rép> [--out ops.json]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

# Vocabulaire fermé de `PlantToxicityFact.Value`, repris de
# `verdictsToxiciteValides` dans ArboreBackend/plant_traits.go. Une valeur hors
# vocabulaire est refusée à l'écriture côté serveur.
VERDICTS = ("safe", "toxic", "irritant", "unknown")

# Version courante de `PlantBotanicalProfile`, cf. VersionSchemaBotanique.
SCHEMA = 1

# Ce qui fait d'une source une source DE TOXICITÉ. Les fiches citent aussi des
# sources de culture ou de taille, qui n'établissent rien ici.
RX_TOXICITE = re.compile(
    r"aspca|toxic|poison|irritant|non-?toxic|dermatit|sap\b|ingest", re.I)


def source_toxicite(sources: list[str]) -> str | None:
    """Rend la source qui établit la toxicité, ou None s'il n'y en a pas.

    L'ordre des sources est celui de la rédaction, du plus au moins autoritaire ;
    on retient donc la PREMIÈRE qui parle de toxicité plutôt que la plus longue.
    """
    for s in sources or []:
        if isinstance(s, str) and RX_TOXICITE.search(s):
            return s
    return None


def nom_de_source(source: str) -> str:
    """Le nom de la base, c'est-à-dire ce qui précède la première virgule.

    Les sources sont rédigées « <base>, <ce qu'elle établit> ». Garder la phrase
    entière ferait un `sourceName` de trois lignes dans chaque fiche servie.
    """
    return source.split(",")[0].strip()[:120]


def verdict(toxicite: dict) -> str:
    """Le verdict, depuis le croisement des deux booléens. Voir le tableau."""
    if toxicite.get("toxic"):
        return "toxic"
    return "safe" if toxicite.get("toxicityEstablished") else "unknown"


def detail(toxicite: dict, pour_enfant: bool) -> str:
    """Le texte affiché sous le verdict, pris de la rédaction et non réécrit."""
    bouts = []
    cibles = toxicite.get("toxicTo") or []
    if cibles and not pour_enfant:
        bouts.append("toxic to " + ", ".join(str(c) for c in cibles))
    principe = (toxicite.get("toxicPrinciple") or "").strip()
    if principe:
        bouts.append(principe)
    signes = (toxicite.get("signs") or "").strip()
    if signes and signes.lower() not in principe.lower():
        bouts.append(signes)
    return " ".join(bouts).strip()


def fait(toxicite: dict, source: str | None, date: str,
         pour_enfant: bool) -> tuple[dict | None, str | None]:
    """Rend (le fait, None) ou (None, motif de refus)."""
    v = verdict(toxicite)
    if v not in VERDICTS:
        return None, f"verdict {v!r} hors vocabulaire"
    # Le refus central : `safe` est une AFFIRMATION d'innocuité. Sans source
    # nommée, elle n'a rien pour la soutenir et ne doit pas être servie.
    if v == "safe" and not source:
        return None, "verdict « safe » sans source de toxicité nommée"
    f: dict[str, Any] = {"value": v}
    d = detail(toxicite, pour_enfant)
    if d:
        f["detail"] = d[:900]
    if source:
        f["evidence"] = {
            "sourceName": nom_de_source(source),
            "reviewedAt": date,
            # Rédigée sur source nommée, mais sans URL vérifiable dans la
            # fiche : on ne prétend pas à mieux que `medium`.
            "reliability": "medium",
        }
    return f, None


def operations(nouvelles: Path, date: str) -> tuple[list[dict], list[tuple[str, str]]]:
    """Opérations à appliquer, et les fiches refusées avec leur motif."""
    poser, refus = [], []
    for f in sorted(nouvelles.glob("*.json")):
        if f.name.startswith("_") or f.suffix != ".json":
            continue
        try:
            d = json.loads(f.read_text("utf-8"))
        except ValueError as e:
            refus.append((f.stem, f"JSON illisible : {e}"))
            continue
        meta = d.get("_meta") or {}
        tox = meta.get("toxicity") or {}
        if "toxic" not in tox or "toxicityEstablished" not in tox:
            refus.append((f.stem, "_meta.toxicity incomplet"))
            continue
        src = source_toxicite(meta.get("sources") or [])
        animal, motif_a = fait(tox, src, date, pour_enfant=False)
        enfant, motif_e = fait(tox, src, date, pour_enfant=True)
        if motif_a or motif_e:
            refus.append((f.stem, motif_a or motif_e or ""))
            continue
        poser.append({
            "modelURL": f"{f.stem}_potless.usdz",
            "set": {
                "botanicalProfile.petToxicity": animal,
                "botanicalProfile.childToxicity": enfant,
                "botanicalProfile.schemaVersion": SCHEMA,
            },
        })
    return poser, refus


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--nouvelles", required=True, type=Path,
                    help="répertoire des blocs rédactionnels <clé>.json")
    ap.add_argument("--date", default="2026-11-12",
                    help="date de relecture portée par l'evidence")
    ap.add_argument("--out")
    a = ap.parse_args()

    poser, refus = operations(a.nouvelles, a.date)

    compte: dict[str, int] = {}
    for o in poser:
        v = o["set"]["botanicalProfile.petToxicity"]["value"]
        compte[v] = compte.get(v, 0) + 1
    sans_preuve = sum(
        1 for o in poser if "evidence" not in o["set"]["botanicalProfile.petToxicity"])

    print(f"  fiches à renseigner   : {len(poser)}", file=sys.stderr)
    print(f"  verdicts              : {compte}", file=sys.stderr)
    print(f"  dont sans evidence    : {sans_preuve} "
          f"(toutes « unknown » ou « toxic », jamais « safe »)", file=sys.stderr)
    print(f"  refusées              : {len(refus)}", file=sys.stderr)
    for cle, motif in refus[:15]:
        print(f"      {cle} — {motif}", file=sys.stderr)

    if a.out:
        Path(a.out).write_text(
            json.dumps({"plantes": poser}, ensure_ascii=False, indent=1),
            encoding="utf-8")
        print(f"  écrit : {a.out}", file=sys.stderr)
    return 1 if refus else 0


if __name__ == "__main__":
    sys.exit(main())
