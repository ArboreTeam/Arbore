#!/usr/bin/env python3
"""Pose les descriptions réécrites, dans les quatre langues à la fois. (#809)

Comme les autres scripts de catalogue, il n'ouvre aucune base : il émet des
opérations que `appliquer-ops-mongo.py` applique après relecture.

## Ce qu'il sert à réparer

Trois défauts, tous dans la description fournie par le producteur :

  - **elle manque**, et la fiche ne peut pas entrer au catalogue — 13 plantes
    dont le reste de la fiche est pourtant prêt ;
  - **elle décrit une autre plante** — un fusain présenté comme un genévrier,
    une escallonia comme un lierre des Canaries ;
  - **elle contredit le reste de la fiche** — deux plantes annoncées « à
    l'abri du soleil » quand les sources donnent le plein soleil. C'est le
    seul des trois qui donne un conseil de soin faux.

La réécriture se fait depuis le bloc anglais, qui est sourcé. Ce script ne la
juge pas : il la transporte.

## Les quatre champs sont écrits ensemble, et ce n'est pas un détail

Sur les 123 fiches servies, `description` à la racine **est** toujours
`translations.fr.description`. Écrire l'une sans l'autre laisserait deux textes
français concurrents pour la même plante — exactement ce que la règle « la
description française ne se traduit pas » existe pour empêcher.

  python3 scripts/verser-descriptions.py --descriptions <rép> \\
      [--seulement cle1,cle2] [--out ops.json]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

LANGUES = ("fr", "es", "de")
CADRATIN = "—"
POINT_DECIMAL = re.compile(r"\d\.\d")

# Bornes relevées sur les 123 descriptions servies : la médiane est à 366
# caractères, et la consigne de rédaction demande 300 à 600. On refuse large
# autour, pour n'attraper que l'accident — un champ vide, ou une fiche entière
# collée dans la description.
MINI, MAXI = 120, 1500


def ecarts(cle: str, bloc: dict) -> list[str]:
    """Nomme ce qui empêche de poser cette description. Vide = elle passe."""
    motifs = []
    for lg in LANGUES:
        t = bloc.get(lg)
        if not isinstance(t, str) or not t.strip():
            motifs.append(f"{lg} absent ou vide")
            continue
        t = t.strip()
        if len(t) < MINI:
            motifs.append(f"{lg} trop court ({len(t)} caractères)")
        if len(t) > MAXI:
            motifs.append(f"{lg} trop long ({len(t)} caractères)")
        if CADRATIN in t:
            motifs.append(f"{lg} contient un tiret cadratin")
        if m := POINT_DECIMAL.search(t):
            motifs.append(f"{lg} garde un point décimal anglais ({m.group()})")
        # Une description tronquée en plein mot est le défaut qui a été trouvé
        # sur la fiche du thym : elle doit finir sur une ponctuation forte.
        if t[-1] not in ".!?»\"'…)":
            motifs.append(f"{lg} ne se termine pas par une ponctuation")
    fr, es, de = (bloc.get(l) or "" for l in LANGUES)
    if fr and (fr == es or fr == de):
        motifs.append("une traduction est identique au français")
    return motifs


def operations(descriptions: Path, seulement: set[str] | None):
    """Rend (opérations, refusées avec motif, clés ignorées)."""
    poser, refus, hors = [], [], []
    for f in sorted(descriptions.glob("*.json")):
        if f.name.startswith("_"):
            continue
        if seulement is not None and f.stem not in seulement:
            hors.append(f.stem)
            continue
        try:
            bloc = json.loads(f.read_text("utf-8"))
        except ValueError as e:
            refus.append((f.stem, [f"JSON illisible : {e}"]))
            continue
        motifs = ecarts(f.stem, bloc)
        if motifs:
            refus.append((f.stem, motifs))
            continue
        fr = bloc["fr"].strip()
        set_ = {"description": fr}
        for lg in LANGUES:
            set_[f"translations.{lg}.description"] = bloc[lg].strip()
        poser.append({"modelURL": f"{f.stem}_potless.usdz", "set": set_})
    return poser, refus, hors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--descriptions", required=True, type=Path)
    ap.add_argument("--seulement",
                    help="liste de clés séparées par des virgules ; par défaut "
                         "toutes celles du répertoire")
    ap.add_argument("--out")
    a = ap.parse_args()

    seulement = set(a.seulement.split(",")) if a.seulement else None
    poser, refus, hors = operations(a.descriptions, seulement)

    print(f"  descriptions à poser : {len(poser)}", file=sys.stderr)
    print(f"  refusées             : {len(refus)}", file=sys.stderr)
    for cle, motifs in refus[:15]:
        print(f"      {cle} — {' ; '.join(motifs[:3])}", file=sys.stderr)
    if hors:
        print(f"  hors sélection       : {len(hors)}", file=sys.stderr)

    if a.out:
        Path(a.out).write_text(
            json.dumps({"plantes": poser}, ensure_ascii=False, indent=1),
            encoding="utf-8")
        print(f"  écrit : {a.out}", file=sys.stderr)
    return 1 if refus else 0


if __name__ == "__main__":
    sys.exit(main())
