#!/usr/bin/env python3
"""Dérive trois champs structurés de `botanicalProfile` depuis la prose. (#489)

## Le constat qui motive ce script

Les 124 fiches portent une description complète — soleil, eau, substrat — mais
uniquement **en prose**. `botanicalProfile`, le contrat que consomment les
filtres et le moteur de compatibilité, est vide à 0 %.

Le contenu existe donc ; c'est sa forme qui manque. Ces trois champs se
déduisent du texte présent, sans consulter aucune source extérieure :

    directSunHours        ← sun.durationPerDay       « 6–8 h / jour »
    wateringIntervalDays  ← water.frequency          « 1 fois par semaine »
    drainage              ← soilAndPot.substrate     « mélange bien drainant »

## Sur la fiabilité, et pourquoi elle est marquée « derived »

Une valeur extraite d'une prose vaut ce que vaut cette prose — laquelle a été
produite par un agent puis traduite (cf. #489). L'inscrire avec
`reliability: authoritative`, comme la toxicité ASPCA, serait mentir sur sa
provenance.

`evidence.reliability = "derived"` et `sourceName` nommant le champ d'origine :
un lecteur voit d'où vient la valeur et peut la contester.

## L'arrosage est saisonnier

Les fréquences sont écrites « 1 à 2 fois par semaine en été, 1 fois toutes les
2 semaines en hiver ». La première proposition PORTEUSE d'un intervalle est
retenue : elle décrit la période de croissance, celle où l'arrosage est une
contrainte réelle. Un intervalle hivernal moyenné avec l'estival ne décrirait
aucune des deux saisons.

Certaines fiches n'en portent aucun : « arrose quand les premiers centimètres
sont secs » est une condition, pas une périodicité. Elles restent sans valeur —
et le garde-fou du script refuse explicitement d'y lire « 2 à 3 jours », ce qui
confondrait une profondeur de sol avec une fréquence.

## Usage

    python3 scripts/derive-botanical-profile.py --plants plants.json          # mesure
    python3 scripts/derive-botanical-profile.py --plants plants.json --out ops.json
"""
import argparse, json, re, sys
from datetime import date

FIELD_SOURCE = {
    "directSunHours": "translations.<lang>.sun.durationPerDay",
    "wateringIntervalDays": "translations.<lang>.water.frequency",
    "drainage": "translations.<lang>.soilAndPot.substrate",
}


def _nombres(txt: str):
    """Les nombres d'un fragment, tirets typographiques compris."""
    return [float(n.replace(",", ".")) for n in re.findall(r"\d+(?:[.,]\d+)?", txt)]


def sun_hours(txt: str):
    """« 6–8 h / jour » → (6, 8).  « 4 h » → (4, 4)."""
    if not txt:
        return None
    m = re.search(r"(\d+)\s*[–\-—à]\s*(\d+)\s*h", txt, re.I)
    if m:
        return float(m.group(1)), float(m.group(2))
    m = re.search(r"(\d+)\s*h", txt, re.I)
    if m:
        return float(m.group(1)), float(m.group(1))
    return None


MOTS_NOMBRES = {"une": 1, "un": 1, "deux": 2, "trois": 3, "quatre": 4}


def _n(txt: str):
    """Un nombre écrit en chiffres ou en lettres."""
    txt = txt.strip().lower()
    if txt in MOTS_NOMBRES:
        return float(MOTS_NOMBRES[txt])
    try:
        return float(txt.replace(",", "."))
    except ValueError:
        return None


# Un nombre : chiffres ou mot.
NB = r"(\d+|une?|deux|trois|quatre)"
SEP = r"(?:[àa]|[–\-—])"


def _intervalle(frag: str):
    """Intervalle en jours pour UN fragment, ou None."""
    # Garde-fou : « les 2 à 3 premiers centimètres sont secs » décrit une
    # profondeur de sol, pas une périodicité. Confondre les deux donnerait
    # « arroser tous les 2 jours » à une plante qu'on arrose au toucher.
    if re.search(r"centim|\bcm\b|profondeur", frag, re.I):
        return None

    # « 1 à 2 fois par semaine » → 7/max .. 7/min
    m = re.search(NB + r"\s*" + SEP + r"\s*" + NB + r"\s*fois\s+par\s+semaine", frag, re.I)
    if m and (a := _n(m.group(1))) and (b := _n(m.group(2))):
        return round(7 / max(a, b), 1), round(7 / min(a, b), 1)

    # « une fois par semaine », « 2 fois par semaine »
    m = re.search(NB + r"\s*fois\s+par\s+semaine", frag, re.I)
    if m and (a := _n(m.group(1))):
        return round(7 / a, 1), round(7 / a, 1)

    # « toutes les 1–2 semaines » / « tous les 2 à 3 semaines »
    m = re.search(r"tou(?:te)?s\s+les\s+" + NB + r"\s*" + SEP + r"\s*" + NB + r"\s*semaines?", frag, re.I)
    if m and (a := _n(m.group(1))) and (b := _n(m.group(2))):
        return a * 7, b * 7

    m = re.search(r"tou(?:te)?s\s+les\s+" + NB + r"\s*semaines?", frag, re.I)
    if m and (a := _n(m.group(1))):
        return a * 7, a * 7

    # « tous les 10–15 jours »
    m = re.search(r"tou(?:te)?s\s+les\s+" + NB + r"\s*" + SEP + r"\s*" + NB + r"\s*jours?", frag, re.I)
    if m and (a := _n(m.group(1))) and (b := _n(m.group(2))):
        return a, b

    m = re.search(r"tou(?:te)?s\s+les\s+" + NB + r"\s*jours?", frag, re.I)
    if m and (a := _n(m.group(1))):
        return a, a

    return None


def watering_days(txt: str):
    """Intervalle en jours, depuis la première proposition qui en porte un.

    Les fréquences sont saisonnières — « 1 à 2 fois par semaine en été, 1 fois
    toutes les 2 semaines en hiver ». La première proposition PORTEUSE décrit la
    période de croissance, celle où l'arrosage est une contrainte réelle. Les
    propositions liminaires (« En gros », « Au printemps et en été ») sont donc
    traversées, pas bloquantes.

    Certaines fiches ne décrivent aucun intervalle : « arrose quand les premiers
    centimètres sont secs » est une condition, pas une périodicité. Elles
    restent sans valeur — c'est correct, et préférable à un chiffre inventé.
    """
    if not txt:
        return None
    for frag in re.split(r"[,;.]", txt):
        r = _intervalle(frag)
        if r:
            return r
    return None


# Les valeurs SONT celles qu'attend le client : `fast`, `normal`, `slow` — les
# `rawValue` de `GardenDrainageDTO`, comparés par ÉGALITÉ STRICTE dans
# `PlantCatalogContext.appendDrainageCriterion`.
#
# Écrire un libellé lisible (« well-drained ») serait pire que ne rien écrire :
# sans le champ, le moteur note simplement la donnée comme manquante ; avec une
# valeur qu'il ne reconnaît pas, il conclut à un CONFLIT de drainage sur chaque
# plante. Une valeur incomprise n'est pas neutre, elle est fausse.
#
# Ordonné du plus exigeant au plus tolérant : « très drainant » doit gagner sur
# « drainant », et « humide » ne doit pas capter « bien drainant mais maintenu
# humide ».
DRAINAGE_RULES = [
    # Substrats de cactées et sols sableux : l'eau doit filer.
    ("fast", ["très drainant", "parfaitement drainant", "très bien drain",
              "drainage excellent", "sableux", "cactus", "succulente"]),
    # Le « bien drainant » horticole ordinaire, majoritaire au catalogue.
    ("normal", ["bien drain", "drainant", "drainage"]),
    # Sols qui gardent l'eau.
    ("slow", ["retient l'humidité", "frais", "humifère", "reste humide"]),
]


def drainage(txt: str):
    if not txt:
        return None
    t = txt.lower()
    for valeur, cles in DRAINAGE_RULES:
        if any(c in t for c in cles):
            return valeur
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plants", required=True)
    ap.add_argument("--lang", default="fr")
    ap.add_argument("--out")
    args = ap.parse_args()

    brut = json.load(open(args.plants))
    plants = brut if isinstance(brut, list) else brut.get("plants", [])
    aujourdhui = date.today().isoformat()

    ops, compte = [], {k: 0 for k in FIELD_SOURCE}

    for p in plants:
        tr = p.get("translations", {}).get(args.lang, {})
        champs = {}

        def evidence(champ):
            return {
                "sourceName": "Dérivé de " + FIELD_SOURCE[champ].replace("<lang>", args.lang),
                "reviewedAt": aujourdhui,
                "reliability": "derived",
            }

        h = sun_hours((tr.get("sun") or {}).get("durationPerDay", ""))
        if h:
            champs["directSunHours"] = {"minimum": h[0], "maximum": h[1],
                                        "unit": "hours/day", "evidence": evidence("directSunHours")}

        w = watering_days((tr.get("water") or {}).get("frequency", ""))
        if w:
            champs["wateringIntervalDays"] = {"minimum": w[0], "maximum": w[1],
                                              "unit": "days", "evidence": evidence("wateringIntervalDays")}

        d = drainage((tr.get("soilAndPot") or {}).get("substrate", ""))
        if d:
            champs["drainage"] = {"value": d, "evidence": evidence("drainage")}

        for k in champs:
            compte[k] += 1
        if champs:
            ops.append({"id": p["id"], "name": p["name"], "fields": champs})

    total = len(plants)
    print(f"  fiches : {total}", file=sys.stderr)
    for k, n in compte.items():
        print(f"    {k:22} {n}/{total}  {round(100*n/total)}%", file=sys.stderr)

    if args.out:
        json.dump(ops, open(args.out, "w"), ensure_ascii=False, indent=1)
        print(f"  écrit : {args.out} ({len(ops)} fiches)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
