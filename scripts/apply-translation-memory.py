#!/usr/bin/env python3
"""Réinjecte une traduction rédigée à la main dans les fiches du catalogue. (#489)

## Pourquoi ce script existe à côté de translate-plant-catalog.py

L'espagnol a consommé 456 000 des 500 000 caractères du quota DeepL gratuit.
L'allemand en demandait 428 000 de plus : il ne restait rien. Le catalogue est
pourtant livré en quatre langues, et un germanophone voyait de l'anglais.

L'allemand a donc été rédigé à la main, chaîne par chaîne, et déposé dans une
mémoire de traduction — `scripts/translations/<lang>.json`, un simple objet
`{ chaîne anglaise: chaîne traduite }`. Ce script fait le reste du travail de
`translate-plant-catalog.py` : reconstruire la structure, appliquer la même
règle du tout-ou-rien, et produire le même fichier d'opérations.

Séparer les deux garde chaque script honnête sur sa source. L'un appelle un
service et paie un quota ; l'autre ne fait que relire ce qu'un humain a écrit.

## La règle qui gouverne l'écriture : tout ou rien

Inchangée, et pour la même raison. `PlantTranslation` déclare `description` et
`plantType` NON optionnels, et `translations` est décodé d'un bloc. Une
traduction partielle ne dégrade pas l'affichage : elle rend la fiche entière
indécodable, et la plante disparaît de l'app.

Une chaîne absente de la mémoire suffit donc à faire refuser la fiche — jamais
à la laisser à moitié traduite.

## care.difficulty n'est pas de la prose

`Plant.careDifficulty(locale:)` reconnaît ce champ par mots-clés, et le binaire
livré aux testeurs porte une liste figée. La valeur est donc réécrite depuis
l'anglais, canoniquement, quoi qu'en dise la mémoire (#485).
"""

from __future__ import annotations
import argparse, json, sys

# Les libellés que `careDifficulty(locale:)` sait reconnaître. Identiques à
# ceux de translate-plant-catalog.py : les deux chemins doivent produire la
# même valeur pour la même fiche.
DIFFICULTE = {
    "easy":     {"es": "Fácil",      "de": "Einfach"},
    "moderate": {"es": "Intermedio", "de": "Mittel"},
    "hard":     {"es": "Difícil",    "de": "Anspruchsvoll"},
}


def collecter(o, acc=None):
    """Toutes les chaînes de l'objet, dans l'ordre du parcours."""
    acc = [] if acc is None else acc
    if isinstance(o, str):
        acc.append(o)
    elif isinstance(o, list):
        for v in o:
            collecter(v, acc)
    elif isinstance(o, dict):
        for v in o.values():
            collecter(v, acc)
    return acc


def reconstruire(source, memoire):
    """Copie la structure en remplaçant chaque chaîne par sa traduction.

    Les chaînes vides ou blanches sont recopiées telles quelles : elles ne
    portent rien à traduire, et exiger qu'elles figurent dans la mémoire ferait
    refuser des fiches pour rien.
    """
    if isinstance(source, str):
        return source if not source.strip() else memoire[source]
    if isinstance(source, list):
        return [reconstruire(v, memoire) for v in source]
    if isinstance(source, dict):
        return {k: reconstruire(v, memoire) for k, v in source.items()}
    return source


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plants", required=True, help="export JSON : _id, name, langues, en")
    ap.add_argument("--lang", required=True, choices=sorted(DIFFICULTE["easy"]),
                    help="langue à produire")
    ap.add_argument("--memoire", required=True,
                    help="JSON { chaîne anglaise: chaîne traduite }")
    ap.add_argument("--out", help="fichier d'opérations ; sans lui, simulation seule")
    a = ap.parse_args()

    plants = json.load(open(a.plants, encoding="utf-8"))
    memoire = json.load(open(a.memoire, encoding="utf-8"))
    a_faire = [p for p in plants if a.lang not in p["langues"] and p.get("en")]

    attendues = {s for p in a_faire for s in collecter(p["en"]) if s.strip()}
    absentes = attendues - memoire.keys()
    print(f"  fiches à traiter   : {len(a_faire)}", file=sys.stderr)
    print(f"  chaînes attendues  : {len(attendues)}", file=sys.stderr)
    print(f"  mémoire            : {len(memoire)} entrées", file=sys.stderr)
    print(f"  absentes           : {len(absentes)}", file=sys.stderr)
    for s in list(absentes)[:5]:
        print(f"    · {s[:90]}", file=sys.stderr)

    ops, refusees = [], []
    for p in a_faire:
        chaines = [s for s in collecter(p["en"]) if s.strip()]
        if any(not memoire.get(s) for s in chaines):
            refusees.append(p["name"])
            continue
        traduite = reconstruire(p["en"], memoire)
        if not traduite.get("description") or not traduite.get("plantType"):
            refusees.append(p["name"])
            continue

        # Rétablir le libellé canonique de la difficulté (cf. DIFFICULTE).
        src = ((p["en"].get("care") or {}).get("difficulty") or "").strip().lower()
        if src:
            canon = DIFFICULTE.get(src, {}).get(a.lang)
            if not canon:
                refusees.append(f"{p['name']} (difficulté source inconnue : {src!r})")
                continue
            traduite.setdefault("care", {})["difficulty"] = canon
        ops.append({"_id": p["_id"], "name": p["name"], "traduction": traduite})

    print(f"  fiches complètes   : {len(ops)}", file=sys.stderr)
    if refusees:
        print(f"  REFUSÉES (partielles, non écrites) : {len(refusees)}", file=sys.stderr)
        for n in refusees[:10]:
            print(f"    · {n}", file=sys.stderr)

    if not a.out:
        print("  (simulation — aucun fichier produit)", file=sys.stderr)
        return 0

    json.dump({"lang": a.lang, "ops": ops}, open(a.out, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"  → {a.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
