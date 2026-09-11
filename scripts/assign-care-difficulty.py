#!/usr/bin/env python3
"""Renseigne `translations.<lang>.care.difficulty` sur les 124 fiches. (#485)

## Le défaut corrigé

`care.difficulty` n'existait sur aucune fiche. Le filtre du catalogue vidait donc
la liste, et le wizard se rabattait sur `flags.easyCare` — un booléen, alors que
l'interface propose trois niveaux. Le cran « intermédiaire » ne pouvait rien
renvoyer.

## Ce que « difficulté » veut dire ici, et ce qu'elle ne dit pas

Elle mesure **l'effort d'entretien courant**, pas l'adéquation au lieu.

La distinction est le cœur du barème. Une lavande exige un sol drainant — c'est
une condition de SITE, déjà portée par `botanicalProfile.drainage` et exploitée
par le moteur de compatibilité. La compter aussi comme une difficulté la
pénaliserait deux fois : une fois pour ne pas convenir à un sol lourd, une fois
pour être « exigeante ». Or plantée au bon endroit, elle ne demande rien.

Ce que la difficulté mesure, c'est ce que la plante réclame **une fois bien
placée** : rythme d'arrosage serré, humidité que l'air d'un logement ne fournit
pas, sensibilité aux ravageurs, intolérance à l'écart.

## Les trois niveaux

  facile        Supporte la négligence. Arrosage irrégulier, plage de lumière
                large, aucune exigence d'humidité. Un débutant la garde en vie.

  intermédiaire Une chose doit être faite juste, régulièrement — un rythme
                d'arrosage, un niveau de lumière — mais un oubli ne tue pas.

  exigeant      Réclame des conditions qu'un logement ou un jardin ordinaire ne
                fournit pas spontanément, ou meurt d'une seule erreur.

## Le vocabulaire n'est pas libre

`Plant.careDifficulty(locale:)` reconnaît la difficulté par mots-clés, et le
build 31 est DÉJÀ chez les testeurs. Les valeurs écrites doivent donc être
comprises par ce binaire-là : élargir la liste côté code n'aiderait pas les
installations existantes.

Vérifié caractère par caractère : « Difficult » et « Demanding » ne sont PAS
reconnus (les mots-clés sont « difficile », « dificil », « difícil », « hard »).
D'où « Hard » en anglais.

La valeur est aussi affichée telle quelle dans `PlantDetailView` : elle doit être
lisible, pas seulement reconnue.

## Provenance des verdicts

La majorité relève d'un consensus horticole que rien ne conteste — un
Zamioculcas supporte l'abandon, un Croton perd ses feuilles au moindre écart.

Les cas discutables ont été vérifiés auprès de la RHS et du Missouri Botanical
Garden, et portent la mention `verifie=` avec ce qui a été retenu. Le buis en est
l'exemple : arbuste facile il y a vingt ans, la RHS écrit aujourd'hui que la
pyrale et le dépérissement « peuvent le rendre impossible à cultiver dans
certaines régions ».
"""

from __future__ import annotations
import argparse, json, re, sys

LIBELLES = {
    "facile":        {"fr": "Facile",        "en": "Easy",     "es": "Fácil",     "de": "Einfach"},
    "intermediaire": {"fr": "Intermédiaire", "en": "Moderate", "es": "Intermedio","de": "Mittel"},
    "exigeant":      {"fr": "Exigeant",      "en": "Hard",     "es": "Difícil",   "de": "Anspruchsvoll"},
}

# taxon (premier mot du nom, minuscule) -> (niveau, justification)
VERDICTS: dict[str, tuple[str, str]] = {
    # --- Supporte la négligence -------------------------------------------
    "zamioculcas":  ("facile", "rhizomes tubéreux : survit à des semaines d'oubli et à la faible lumière"),
    "sansevieria":  ("facile", "succulente à port dressé, arrosage mensuel toléré, indifférente à l'humidité"),
    "pothos":       ("facile", "bouture facile, tolère la faible lumière et l'arrosage irrégulier"),
    "scindapsus":   ("facile", "même tolérance que le pothos dont il est proche"),
    "chlorophytum": ("facile", "plante de débutant par excellence, repart de ses stolons"),
    "aglaonema":    ("facile", "feuillage d'ombre, aucune exigence d'humidité"),
    "aglaonéma":    ("facile", "même taxon que l'aglaonema, orthographe accentuée du catalogue"),
    "dracaena":     ("facile", "tige lignifiée, réserve d'eau, tolère l'ombre et l'oubli"),
    "haworthia":    ("facile", "succulente compacte, arrosage espacé, lumière moyenne suffisante"),
    "echeveria":    ("facile", "succulente de rosette, ne demande que du soleil et peu d'eau"),
    "crassula":     ("facile", "arbre de jade : réserve d'eau dans les feuilles, très tolérant"),
    "sedum":        ("facile", "orpin rustique, supporte sécheresse, gel et sol pauvre"),
    "kalanchoe":    ("facile", "succulente fleurie, arrosage espacé"),
    "kalanchoé":    ("facile", "même taxon, orthographe accentuée du catalogue"),
    "cactus":       ("facile", "arrosage toutes les 2-3 semaines, l'oubli lui convient mieux que l'excès"),
    "composition":  ("facile", "composition de cactées : mêmes exigences que ses composants"),
    "agave":        ("facile", "succulente architecturale, sécheresse et plein soleil"),
    "beaucarnea":   ("facile", "pied d'éléphant : le caudex stocke l'eau, arrosage très espacé"),
    "ceropegia":    ("facile", "chaîne des cœurs, tubercules de réserve, tolère l'oubli"),
    "yucca":        ("facile", "tronc ligneux, sécheresse et plein soleil, rustique en extérieur"),
    "philodendron": ("facile", "aroïdée grimpante tolérante à l'ombre et à l'arrosage irrégulier"),
    "monstera":     ("facile", "vigoureuse, tolère la lumière indirecte et un arrosage hebdomadaire"),
    "syngonium":    ("facile", "aroïdée de croissance rapide, peu exigeante"),
    "tradescantia": ("facile", "misère : se bouture dans un verre d'eau, repart de rien"),
    "peperomia":    ("facile", "feuilles épaisses semi-succulentes, arrosage espacé"),
    "pilea":        ("facile", "plante à monnaie chinoise, arrosage hebdomadaire, lumière indirecte"),
    "pilea-peperomia": ("facile", "duo de deux genres également faciles"),
    "asparagus":    ("facile", "racines tubéreuses de réserve, repart même après dessèchement"),
    "chamaedorea":  ("facile", "palmier de montagne : le seul qui prospère en lumière faible"),
    "kentia":       ("facile", "palmier de salon réputé pour sa tolérance à l'ombre et à l'oubli"),
    "schefflera":   ("facile", "arbre parapluie, robuste, tolère une taille sévère"),
    "spathiphyllum":("facile", "signale sa soif en s'affaissant puis se relève : erreur réversible"),
    "dieffenbachia":("facile", "feuillage épais, tolère la lumière moyenne"),
    "ficus":        ("facile", "caoutchouc : robuste, seule la lumière compte vraiment"),
    "hoya":         ("facile", "feuilles cireuses de réserve, arrosage espacé, aime être à l'étroit"),
    "aucuba":       ("facile", "arbuste d'ombre rustique, indifférent au sol et à la sécheresse"),
    "festuca":      ("facile", "graminée bleue de sol sec et pauvre, aucun entretien"),
    "stipa":        ("facile", "cheveux d'ange : graminée de sol sec, un peignage annuel suffit"),
    "miscanthus":   ("facile", "graminée vivace robuste, une taille par an"),
    "achillea":     ("facile", "vivace de sol pauvre, résiste à la sécheresse"),
    "echinacea":    ("facile", "vivace de prairie, rustique et sobre"),
    "salvia":       ("facile", "sauge des bois : vivace rustique, une taille après floraison"),
    "gaura":        ("facile", "vivace légère, tolère sécheresse et sol pauvre"),
    "phormium":     ("facile", "lin de Nouvelle-Zélande, persistant robuste, aucun soin courant"),
    "ophiopogon":   ("facile", "couvre-sol persistant, indifférent, aucun entretien"),
    "fargesia":     ("facile", "bambou non traçant : pas de rhizomes à contenir, arrosage en pot"),
    "nandina":      ("facile", "bambou sacré, arbuste rustique sans ravageur notable"),
    "cupressus":    ("facile", "cyprès méditerranéen, sec et rustique une fois installé"),
    "pelargonium":  ("facile", "géranium de balcon : supporte la sécheresse, refleurit sans soin"),
    "washingtonia": ("facile", "palmier vigoureux, sécheresse et plein soleil"),
    "palmier":      ("facile", "Trachycarpus fortunei : le palmier le plus rustique, aucun soin courant"),
    "fougère":      ("facile", "fougère vivace d'extérieur : à l'ombre fraîche, elle se passe de soin"),
    "lavandula":    ("facile", "verifie=RHS « long-lived and hardy », sobre une fois installée ; "
                               "son exigence de drainage est une condition de site, portée par botanicalProfile.drainage"),
    "olea":         ("facile", "olivier : sobre et lent ; le gel est une contrainte de site, pas d'entretien"),
    "begonia":      ("facile", "bégonias de massif (Semperflorens, Dragon Wing, Boliviensis) : annuels "
                               "de plein air, floraison continue sans intervention"),

    # --- Une chose à faire juste, régulièrement ---------------------------
    "anthurium":    ("intermediaire", "fleurit et garde son feuillage si l'humidité et la lumière restent stables"),
    "phalaenopsis": ("intermediaire", "orchidée la plus tolérante, mais l'arrosage par trempage et le "
                                      "drainage ne pardonnent pas l'excès"),
    "pachira":      ("intermediaire", "verifie=Missouri Bot. Garden « moderate but even moisture » ; "
                                      "l'excès d'eau jaunit et fait tomber les feuilles basses"),
    "areca":        ("intermediaire", "brunit du bout des feuilles en air sec et attire l'araignée rouge"),
    "livistona":    ("intermediaire", "palmier lent exigeant lumière vive et arrosage régulier"),
    "cordyline":    ("intermediaire", "sensible à l'eau calcaire et à l'air sec, brunit facilement"),
    "strelitzia":   ("intermediaire", "oiseau de paradis : lumière vive indispensable, floraison lente à venir"),
    "hydrangea":    ("intermediaire", "hortensia : très gourmand en eau, flétrit en un jour de chaleur "
                                      "(arrosage relevé à 2-3 jours dans les données du catalogue)"),
    "acer":         ("intermediaire", "érable du Japon : feuillage brûlé par le soleil direct et le vent, "
                                      "demande un sol frais en permanence"),
    "hosta":        ("intermediaire", "facile en soi, mais les limaces imposent une surveillance de printemps"),
    "rhododendron":("intermediaire", "azalée : sol acide et frais en continu, souffre dès qu'il sèche"),
    "dahlia":       ("intermediaire", "arrosage soutenu, tuteurage, et arrachage des tubercules hors climat doux"),
    "alcea":        ("intermediaire", "rose trémière : la rouille est quasi systématique et demande un suivi"),
    "bougainvillea":("intermediaire", "floraison conditionnée à un stress hydrique maîtrisé et beaucoup de lumière"),
    "buxus":        ("exigeant", "verifie=RHS : pyrale du buis et dépérissement « peuvent le rendre "
                                 "impossible à cultiver dans certaines régions » — surveillance et "
                                 "traitements deviennent la norme, pas l'exception"),

    # --- Réclame ce qu'un logement ne fournit pas -------------------------
    "calathea":     ("exigeant", "verifie=RHS : « high humidity at all times », difficile à tenir en hiver ; "
                                 "les feuilles s'enroulent et brunissent en air sec"),
    "calathéa":     ("exigeant", "même taxon, orthographe accentuée du catalogue"),
    "maranta":      ("exigeant", "verifie=RHS : mêmes exigences d'humidité constante que le Calathea"),
    "alocasia":     ("exigeant", "dormance hivernale déroutante, araignée rouge, humidité élevée requise"),
    "oreilles":     ("exigeant", "Alocasia Calidora : même taxon, nom vernaculaire du catalogue"),
    "croton":       ("exigeant", "défolie au moindre changement de lieu, de température ou d'arrosage"),
    "nephrolepis":  ("exigeant", "fougère de Boston : brunit dès que l'air sèche, réclame une humidité soutenue"),
    "dicksonia":    ("exigeant", "fougère arborescente : stipe à humidifier, protection hivernale obligatoire"),
}

# Exceptions par fiche : quand le genre n'est pas homogène.
#
# Le verdict porte sur le taxon, ce qui suffit presque partout — un Sedum reste
# un Sedum. Mais certains genres abritent des espèces d'exigence différente, et
# les confondre trahirait l'utilisateur dans les deux sens.
OVERRIDES: dict[str, tuple[str, str]] = {
    "hoya linearis": ("intermediaire",
                      "feuilles fines et pendantes, sans la réserve d'eau cireuse des autres Hoya : "
                      "elle brunit en air sec et ne pardonne pas l'oubli, contrairement à H. bella"),
}


# Fiches à ignorer, avec la raison.
IGNOREES = {
    "plantes": "« Plantes Succulentes Faciles à Vivre 222 pages Éditions Eugen ULMER » "
               "n'est pas une plante mais un LIVRE, aspiré par erreur du catalogue botanic (#489)",
}


def taxon(nom: str) -> str:
    return re.sub(r"[«»'\"]", " ", nom).strip().split()[0].lower()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plants", required=True, help="export JSON de la collection plants")
    ap.add_argument("--out", help="fichier d'opérations ; défaut : résumé seul")
    a = ap.parse_args()

    plants = json.load(open(a.plants, encoding="utf-8"))
    ops, ignorees, inconnues = [], [], []

    for p in plants:
        t = taxon(p["name"])
        if t in IGNOREES:
            ignorees.append((p["name"], IGNOREES[t]))
            continue
        nom_bas = p["name"].lower()
        exception = next((v for k, v in OVERRIDES.items() if k in nom_bas), None)
        if exception:
            niveau, pourquoi = exception
        elif t in VERDICTS:
            niveau, pourquoi = VERDICTS[t]
        else:
            inconnues.append(p["name"])
            continue
        ops.append({
            "_id": p["_id"], "name": p["name"],
            "niveau": niveau, "pourquoi": pourquoi,
            "libelles": LIBELLES[niveau],
        })

    par_niveau = {n: sum(1 for o in ops if o["niveau"] == n) for n in LIBELLES}
    print(f"  fiches            : {len(plants)}", file=sys.stderr)
    print(f"  verdicts          : {len(ops)}", file=sys.stderr)
    for n, c in par_niveau.items():
        print(f"    {n:<14}: {c}", file=sys.stderr)
    print(f"  ignorées          : {len(ignorees)}", file=sys.stderr)
    for nom, raison in ignorees:
        print(f"    · {nom}\n      {raison}", file=sys.stderr)
    if inconnues:
        print(f"  SANS VERDICT      : {len(inconnues)}", file=sys.stderr)
        for nom in inconnues:
            print(f"    · {nom}", file=sys.stderr)

    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(ops, f, ensure_ascii=False, indent=1)
        print(f"  → {a.out}", file=sys.stderr)

    return 1 if inconnues else 0


if __name__ == "__main__":
    raise SystemExit(main())
