#!/usr/bin/env python3
"""Traduit les fiches du catalogue vers une langue manquante, via DeepL. (#489)

## Le manque

97 des 124 fiches n'ont que `en` et `fr`. L'app est livrée en quatre langues :
un hispanophone ou un germanophone voit donc l'anglais, par le repli de
`PlantDetailView.translation(for:)` — `langue → en → n'importe laquelle`.

## Pourquoi traduire depuis l'ANGLAIS et non le français

L'anglais est l'original : la mémoire du projet indique que les fiches ont été
recherchées en anglais par un agent, puis traduites en français par DeepL.
Repartir du français serait traduire une traduction, et empiler les dérives.

C'est aussi 30 % moins cher — 453 000 caractères au lieu de 645 000 — parce que
l'anglais est plus compact. Sur un quota gratuit de 500 000 par mois, cet écart
décide de ce qui est faisable.

## La règle qui gouverne l'écriture : tout ou rien

`PlantTranslation` déclare `description` et `plantType` NON optionnels, et
`translations` est décodé d'un bloc. Une traduction partielle ne dégrade donc
pas l'affichage : elle rend la fiche entière indécodable, et la plante disparaît
de l'app.

Pire encore, une traduction *incomplète mais valide* serait un recul : le
lecteur verrait quelques champs en espagnol et « information indisponible » pour
le reste, là où le repli lui donnait de l'anglais complet.

Le script n'écrit donc une langue que si TOUS les champs de la source ont été
traduits. À la moindre défaillance, la fiche est laissée telle quelle et
signalée.

## Déduplication

Les chaînes identiques ne sont envoyées qu'une fois (facteur ×1,1 — les fiches
sont rédigées une à une, pas produites par gabarit). Modeste, mais gratuit.
"""

from __future__ import annotations
import argparse, json, sys, time, urllib.request, urllib.parse
from pathlib import Path

CIBLES = {"es": "ES", "de": "DE"}
LOT = 45          # DeepL accepte 50 textes par requête ; on garde de la marge.

# `care.difficulty` n'est PAS confié au traducteur.
#
# Ce champ n'est pas de la prose : `Plant.careDifficulty(locale:)` le reconnaît
# par mots-clés, et le binaire livré aux testeurs porte une liste figée. DeepL a
# rendu « Easy » par « Fácil », qui tombe juste — par chance. Rien ne garantit
# qu'il rende « Hard » par « Difícil » plutôt que « Duro », ni « Moderate » par
# « Mittel » plutôt que « Mäßig » : ces deux-là ne seraient pas reconnus, et le
# filtre par difficulté redeviendrait muet sur les fiches traduites.
#
# La valeur canonique est donc réécrite après coup, depuis l'anglais (#485).
DIFFICULTE = {
    "easy":     {"es": "Fácil",     "de": "Einfach"},
    "moderate": {"es": "Intermedio","de": "Mittel"},
    "hard":     {"es": "Difícil",   "de": "Anspruchsvoll"},
}


def cle_deepl() -> tuple[str, str]:
    f = Path(__file__).resolve().parent.parent / ".deepl_api"
    if not f.exists():
        sys.exit("  .deepl_api introuvable à la racine du dépôt")
    k = f.read_text().strip()
    hote = "api-free.deepl.com" if k.endswith(":fx") else "api.deepl.com"
    return k, hote


def quota(cle: str, hote: str) -> tuple[int, int]:
    req = urllib.request.Request(f"https://{hote}/v2/usage",
                                 headers={"Authorization": f"DeepL-Auth-Key {cle}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        d = json.load(r)
    return d["character_count"], d["character_limit"]


def collecter(o, chemin=(), acc=None):
    """Toutes les chaînes de l'objet, avec leur chemin."""
    acc = [] if acc is None else acc
    if isinstance(o, str):
        acc.append((chemin, o))
    elif isinstance(o, list):
        for i, v in enumerate(o):
            collecter(v, chemin + (i,), acc)
    elif isinstance(o, dict):
        for k, v in o.items():
            collecter(v, chemin + (k,), acc)
    return acc


def reconstruire(source, table):
    """Copie la structure en remplaçant chaque chaîne par sa traduction."""
    if isinstance(source, str):
        return table[source]
    if isinstance(source, list):
        return [reconstruire(v, table) for v in source]
    if isinstance(source, dict):
        return {k: reconstruire(v, table) for k, v in source.items()}
    return source


def traduire(textes: list[str], cible: str, cle: str, hote: str) -> list[str]:
    donnees = [("target_lang", cible), ("source_lang", "EN")]
    donnees += [("text", t) for t in textes]
    corps = urllib.parse.urlencode(donnees).encode()
    req = urllib.request.Request(
        f"https://{hote}/v2/translate", data=corps,
        headers={"Authorization": f"DeepL-Auth-Key {cle}",
                 "Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return [t["text"] for t in json.load(r)["translations"]]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plants", required=True, help="export JSON : _id, name, langues, en")
    ap.add_argument("--lang", required=True, choices=sorted(CIBLES), help="langue à produire")
    ap.add_argument("--limite", type=int, help="ne traiter que N fiches (validation)")
    ap.add_argument("--out", help="fichier de sortie ; sans lui, simulation seule")
    a = ap.parse_args()

    plants = json.load(open(a.plants, encoding="utf-8"))
    a_faire = [p for p in plants if a.lang not in p["langues"] and p.get("en")]
    if a.limite:
        a_faire = a_faire[:a.limite]

    uniques = {}
    for p in a_faire:
        for _, s in collecter(p["en"]):
            uniques[s] = None

    cout = sum(len(s) for s in uniques)
    print(f"  fiches à traduire  : {len(a_faire)}", file=sys.stderr)
    print(f"  chaînes uniques    : {len(uniques)}", file=sys.stderr)
    print(f"  caractères à payer : {cout}", file=sys.stderr)

    cle, hote = cle_deepl()
    utilise, plafond = quota(cle, hote)
    print(f"  quota DeepL        : {utilise} / {plafond}  (reste {plafond - utilise})",
          file=sys.stderr)
    if utilise + cout > plafond:
        print(f"  ⛔ DÉPASSEMENT de {utilise + cout - plafond} caractères", file=sys.stderr)
        if a.out:
            return 2

    if not a.out:
        print("  (simulation — aucun appel de traduction)", file=sys.stderr)
        return 0

    liste = list(uniques)
    for i in range(0, len(liste), LOT):
        lot = liste[i:i + LOT]
        for essai in range(4):
            try:
                for src, dst in zip(lot, traduire(lot, CIBLES[a.lang], cle, hote)):
                    uniques[src] = dst
                break
            except Exception as e:                       # réseau, 429, 5xx
                if essai == 3:
                    print(f"  ⛔ échec définitif sur le lot {i}: {e}", file=sys.stderr)
                    return 3
                time.sleep(2 ** essai)
        print(f"\r  traduit {min(i+LOT, len(liste))}/{len(liste)}", end="", file=sys.stderr)
    print(file=sys.stderr)

    # Tout ou rien : une fiche n'est écrite que si chacun de ses champs a une
    # traduction non vide.
    ops, refusees = [], []
    for p in a_faire:
        chaines = [s for _, s in collecter(p["en"])]
        if any(not uniques.get(s) for s in chaines):
            refusees.append(p["name"])
            continue
        traduite = reconstruire(p["en"], uniques)
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

    json.dump({"lang": a.lang, "ops": ops}, open(a.out, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"  → {a.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
