#!/usr/bin/env python3
"""Assemble des fiches de catalogue COMPLÈTES, prêtes à insérer. (#609, #809)

## Ce que ce script fait, et pourquoi il existe

Un modèle 3D déployé ne sert à rien tant qu'aucune fiche ne pointe vers lui.
Mesuré le 2026-11-11 : 206 modèles `_potless` servis en dev, **123 fiches au
catalogue**, donc 153 modèles que rien n'affiche. Le goulot n'est plus la
chaîne 3D, il est là.

Une fiche se compose de morceaux produits par des chaînes différentes, et
aucun outil ne les réunissait :

| champ | d'où il vient |
|---|---|
| `name`, `type`, `description` | la **fiche source**, en français |
| `translations.en` | la **rédaction par agents** (`_nouvelles/<clé>.json`) |
| `botanicalProfile` | l'**enrichissement par agents** (`_*_a_appliquer.json`) |
| `modelURL` | l'**atelier 3D**, suffixe `_potless` (#773) |
| `imageURLs` | la vignette, donc l'`_id` — posé APRÈS l'insertion |

Comme les autres scripts de catalogue, il **n'ouvre aucune base** : il émet
des opérations, et l'écriture reste un geste séparé et relu.

## Pourquoi `description` vient de la fiche source et non de l'agent

Vérifié sur une fiche servie : `description` à la racine est **exactement**
`translations.fr.description`. C'est donc du français, et c'est ce que lit un
utilisateur francophone. Les agents rédigent en anglais ; prendre leur texte
le mettrait en français dans l'interface.

La description de la fiche source est bien plus courte — « Arbuste à feuillage
et fleurs décoratifs. » contre cinq phrases sourcées — mais elle est dans la
bonne langue, et elle est authentique. Le bloc anglais reste disponible pour
les lecteurs anglophones, et la version française rédigée viendra de la
traduction par agents, quand elle sera faite.

## Ce qu'il refuse de faire

- **Il n'invente pas de `translations.fr`.** Une fiche sans français sort avec
  `translations.en` seul, et le script le compte. Traduire automatiquement
  reformulerait des noms d'espèces et des verdicts de toxicité.
- **Il n'écrase rien.** Une plante qui a déjà une fiche n'est pas assemblée,
  elle est signalée. L'insertion est pour les absentes.
- **Il ne pose pas `imageURLs`.** L'URL contient l'`_id`, qui n'existe pas
  avant l'insertion. C'est une seconde passe, après le rendu de la vignette.

## Le piège de la toxicité, et le champ qui le désamorce

`flags.toxicToPets: false` signifie **PROUVÉ SÛR** dans ce catalogue (#778,
#781) : une source nommée affirme l'innocuité. Or le bloc rédactionnel force
un booléen, et deux situations s'y écrasaient — « l'ASPCA dit non-toxique » et
« l'ASPCA n'a pas d'entrée ». Importer la seconde comme la première
recommanderait une plante de toxicité inconnue à un foyer qui a demandé
l'inverse : c'est la régression #783, à l'identique.

D'où `_meta.toxicity.toxicityEstablished`. **Une fiche qui ne le porte pas
est refusée**, plutôt que supposée sûre.

    python3 scripts/assembler-fiches.py --nouvelles <dir> --corpus <dir> \\
        --base304 <f.json> --atelier <etat.json> [--out ops.json]
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path
from typing import Any

# Extraits du JSON embarqué dans la page source. On lit le JSON plutôt que le
# HTML rendu : le corps de page porte aussi les produits vendus en complément,
# et on a déjà pris un cache-pot d'une autre référence pour celui de la plante.
RX_DESC = re.compile(r'"unic_product_desc_web_long":\{[^}]*?"value":"((?:[^"\\]|\\.)*)"')
RX_CAT = re.compile(r'"@type":"ListItem","position":3,"name":"((?:[^"\\]|\\.)*)"')
RX_TITRE = re.compile(r"<title[^>]*>(.*?)</title>", re.S)

# Jetons de conditionnement à retirer du nom affiché : « Ø 17 cm », « pot de
# 5 L », « x H 90 cm ». Le nom d'une plante n'est pas son emballage.
RX_TAILLE = re.compile(
    r"(?:[-–,.]\s*)?(?:\b(?:le|la|en|son|sa)\s+)?"
    r"(?:\b(?:pot|coupe|suspension|jardini[eè]re|conteneur|godet|motte|panier)\b)?"
    r"\s*(?:\b(?:de|du|d[eé]co|diam\.?|diam[eè]tre)\b\s*)*"
    r"(?:[øo]\s*\.?\s*\d+(?:[.,]\d)?|\d+(?:[.,]\d)?\s*(?:l\b|litres?\b|cm\b))"
    r"(?:\s*[x×]\s*h?\s*\.?\s*\d+(?:[.,]\d)?\s*(?:cm\b)?)?\s*(?:cm\b)?",
    re.I,
)

AXES = ("traits", "axes", "colors", "arrosage", "mesures", "hauteurs")

# `environments` a été importé une fois, puis RETIRÉ, et il ne doit pas
# revenir par cette porte. C'est un classement commercial — intérieur /
# extérieur — et non un fait botanique, mais le moteur lui donnait le pouvoir
# du conflit critique, son verdict le plus sévère. Mesuré : sur un balcon, il
# excluait d'un coup 75 plantes sur 123, dont des succulentes qui y vivent
# très bien. Avant d'importer un champ, demander s'il DÉCRIT la plante ou
# s'il DÉCIDE à sa place.
# Version courante de `PlantBotanicalProfile`, cf. VersionSchemaBotanique dans
# ArboreBackend/plant_traits.go.
SCHEMA_BOTANIQUE = 1

AXES_EXCLUS = frozenset({"environments"})

# Nombre de champs « not determined » au-delà duquel la fiche est refusée.
# Trois, parce qu'un ou deux trous honnêtes sur trente et un champs restent
# une fiche utile, alors qu'une identité non tranchée les vide tous à la fois.
SEUIL_CREUX = 3


def _valeurs_texte(bloc) -> list[str]:
    """Toutes les chaînes d'un bloc rédactionnel, listes imbriquées comprises."""
    if isinstance(bloc, str):
        return [bloc]
    if isinstance(bloc, list):
        return [s for v in bloc for s in _valeurs_texte(v)]
    if isinstance(bloc, dict):
        return [s for v in bloc.values() for s in _valeurs_texte(v)]
    return []


def _decoder(valeur: str) -> str:
    """Rend le texte d'un champ JSON échappé deux fois, sans son balisage.

    Les échappements sont décodés par `json.loads`, qui les connaît, et NON par
    un aller-retour `encode().decode("unicode_escape")`.

    Ce détour-là mutile tout caractère non-ASCII : `encode()` rend les octets
    UTF-8, `unicode_escape` les relit en latin-1, et « é » (U+00E9, octets
    C3 A9) ressort en « Ã© ». Le dégât ne se voyait pas sur les champs tirés du
    JSON-LD, où les accents sont écrits `\\u00e9` et survivent au détour ; il
    frappait le `<title>`, qui les porte littéralement. Mesuré le 2026-11-11 :
    **77 des 126 fiches insérées en dev avaient un `name` corrompu**, « Abélia
    Panaché » servi « AbÃ©lia PanachÃ© », et le Ø des diamètres avec.

    `json.loads` échoue sur ce qui n'est pas une chaîne JSON — un `<title>` en
    HTML brut peut porter un guillemet nu. C'est voulu : on garde alors la
    valeur telle quelle, puisqu'elle n'avait rien à décoder.
    """
    try:
        valeur = json.loads(f'"{valeur}"')
    except ValueError:
        pass
    valeur = html.unescape(valeur)
    valeur = re.sub(r"<[^>]+>", " ", valeur)
    return re.sub(r"\s+", " ", valeur).strip()


# Ce qui reste d'un conditionnement une fois son chiffre retiré : « Le pot en
# terre », « de diamètre », « la coupe ». On ne peut pas l'enlever dans la
# même passe, le chiffre étant au milieu.
RX_RESTE = re.compile(
    r"(?:[-–,.]\s*)?\b(?:le|la|les|en|son|sa|de|du|d[eé]co)?\s*"
    r"\b(?:pot|coupe|suspension|jardini[eè]re|conteneur|godet|motte|panier)\b"
    r"(?:\s+\b(?:en|de|du)\b\s*\w+)?\s*(?:\bde\s+diam[eè]tre\b)?\s*$",
    re.I,
)
RX_QUEUE = re.compile(r"\s*(?:\bde\s+diam[eè]tre\b|[-–,.])\s*$", re.I)


def nom_affichable(titre: str) -> str:
    """Le nom de la plante, débarrassé de son conditionnement.

    La substitution rend une ESPACE et non le vide : « premium Ø 40 blanc »
    donnerait sinon « premiumblanc », le motif consommant l'espace qui le
    précède.

    Le premier retrait est celui de l'enseigne : une balise `<title>` de fiche
    produit suit le gabarit « <produit> | <enseigne> », et seule la partie
    gauche nomme la plante. On coupe au séparateur plutôt que sur un nom en
    dur, pour que le script ne dépende pas d'un fournisseur particulier.
    """
    n = re.sub(r"\s*\|\s*[^|]*$", "", titre) if "|" in titre else titre
    n = RX_TAILLE.sub(" ", n)
    n = re.sub(r"\s+", " ", n).strip()
    for _ in range(3):  # « Le pot en terre de diamètre » se pèle en plusieurs fois
        avant = n
        n = RX_QUEUE.sub("", RX_RESTE.sub("", n)).strip()
        if n == avant:
            break
    return re.sub(r"\s+", " ", n).strip(" .-–,")


def lire_source(dossier: Path) -> dict[str, str]:
    """Nom, type et description française, depuis la fiche source."""
    f = dossier / "raw.html"
    if not f.exists():
        return {}
    brut = f.read_text("utf-8", errors="ignore")
    out: dict[str, str] = {}
    if m := RX_TITRE.search(brut):
        out["titre"] = _decoder(m.group(1))
    if m := RX_DESC.search(brut):
        out["description"] = _decoder(m.group(1))
    if m := RX_CAT.search(brut):
        out["type"] = _decoder(m.group(1))
    return out


def profil_botanique(slug: str, axes: dict[str, dict]) -> dict[str, Any]:
    """Réunit les axes produits par les agents d'enrichissement."""
    profil: dict[str, Any] = {}
    for table in axes.values():
        for champ, valeur in (table.get(slug) or {}).items():
            if champ in AXES_EXCLUS:
                continue
            # Ne jamais écraser : le premier axe qui pose un champ le garde.
            # Les tables sont lues dans l'ordre de fiabilité décroissante.
            profil.setdefault(champ, valeur)
    return profil


def assembler(cle: str, redac: dict, slug: str | None, source: dict,
              axes: dict[str, dict],
              repli: dict | None = None) -> tuple[dict | None, str | None]:
    """Rend (document, None) ou (None, motif de refus).

    `repli` porte ce que la fiche source ne donne pas. Trois plantes du
    catalogue n'ont AUCUNE fiche source appariée : leur modèle 3D est déployé,
    leur fiche rédigée est complète, et il leur manque seulement le nom, le
    type et la description. Le repli les débloque sans ouvrir une porte : il
    ne s'applique champ par champ qu'à ce qui manque, et le `name` qu'il donne
    est déjà un nom d'affichage, donc il ne repasse pas par `nom_affichable`,
    qui pèle un conditionnement que ce nom-là n'a jamais porté.
    """
    repli = repli or {}
    meta = redac.get("_meta") or {}
    tox = meta.get("toxicity") or {}
    if "toxicityEstablished" not in tox:
        return None, "toxicityEstablished absent — une toxicité non établie serait lue comme prouvée sûre"
    en = (redac.get("translations") or {}).get("en")
    if not en:
        return None, "translations.en absent"
    nom = repli.get("name")
    titre = source.get("titre")
    if not nom:
        if not slug:
            return None, "aucune fiche source appariée"
        if not titre:
            return None, "titre introuvable dans la fiche source"
    description = source.get("description")
    if not description:
        return None, "pas de description française dans la fiche source"

    doc: dict[str, Any] = {
        "name": nom or nom_affichable(titre),
        "type": source.get("type") or repli.get("type") or "Plantes d’intérieur",
        "description": description,
        "modelURL": f"{cle}_potless.usdz",
        "imageURLs": [],
        "translations": {"en": en},
        "botanicalProfile": profil_botanique(slug, axes),
    }
    if not doc["botanicalProfile"] and repli:
        # Un profil vide est refusé à l'insertion, et c'est juste : une fiche
        # sans aucun trait n'a pas été auditée. On y pose donc le seul fait
        # qu'on tienne sans l'inventer — la version du schéma — pour que
        # `verser-toxicite.py` ait où écrire le verdict de toxicité, qui est
        # le trait dont l'absence compte vraiment.
        doc["botanicalProfile"] = {"schemaVersion": SCHEMA_BOTANIQUE}
    if not doc["botanicalProfile"] and not repli:
        # Le profil vient des axes d'enrichissement, indexés par SLUG. Une
        # fiche sans slug n'en a donc aucun, et le refus dirait seulement
        # qu'elle n'a pas de fiche source — ce qu'on sait déjà. Quand un repli
        # explicite existe, la plante est traitée sciemment hors de la chaîne
        # normale : elle entre avec un profil réduit, que `verser-toxicite.py`
        # remplit ensuite du seul champ qui ne peut pas manquer.
        return None, "profil botanique vide"

    # Une fiche dont l'identité n'a pas pu être tranchée ne se publie pas, même
    # complète de forme. Le cas qui l'impose : « Faux palmier » est un nom
    # commercial qui recouvre aussi bien Beaucarnea recurvata, que l'ASPCA
    # donne non toxique, que Cycas revoluta, dont la cycasine provoque une
    # insuffisance hépatique mortelle. Servir une plante en espérant que ce
    # soit la bonne des deux n'est pas une option.
    creux = sum(1 for v in _valeurs_texte(en)
                if re.match(r"\s*not (determined|established|resolved)", v, re.I))
    if creux >= SEUIL_CREUX:
        return None, f"identité non tranchée — {creux} champs « not determined »"
    return doc, None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--nouvelles", required=True, type=Path,
                    help="répertoire des blocs rédactionnels <clé>.json")
    ap.add_argument("--corpus", required=True, type=Path,
                    help="répertoire des fiches sources (un sous-dossier par slug)")
    ap.add_argument("--base304", required=True, type=Path,
                    help="table clé -> slug")
    ap.add_argument("--axes", required=True, type=Path,
                    help="répertoire des _<axe>_a_appliquer.json")
    ap.add_argument("--descriptions", type=Path,
                    help="répertoire de descriptions de REPLI <clé>.json "
                         "{fr,es,de}, employées quand la fiche source n'en "
                         "porte aucune")
    ap.add_argument("--out")
    a = ap.parse_args()

    base = json.loads(a.base304.read_text("utf-8"))
    slugs = {
        n: (e.get("dirs") or [None])[0] or e.get("dirRattrape")
        for n, e in base.items()
    }
    axes = {}
    for nom in AXES:
        f = a.axes / f"_{nom}_a_appliquer.json"
        if f.exists():
            axes[nom] = json.loads(f.read_text("utf-8"))

    # Descriptions de repli, écrites depuis le bloc anglais pour les plantes
    # dont la page du producteur n'en porte aucune.
    replis: dict[str, dict] = {}
    if a.descriptions:
        for f in a.descriptions.glob("*.json"):
            if f.name.startswith("_"):
                continue
            bloc = json.loads(f.read_text("utf-8")) or {}
            if isinstance(bloc, dict):
                replis[f.stem] = bloc

    prets, refuses, sans_fr, depuis_repli = [], [], 0, 0
    for f in sorted(a.nouvelles.glob("*.json")):
        cle = f.stem
        redac = json.loads(f.read_text("utf-8"))
        slug = slugs.get(cle)
        source = lire_source(a.corpus / slug) if slug else {}
        # Repli : la page du producteur ne porte PAS toujours de description,
        # et sans elle la fiche est refusée alors que tout le reste est prêt —
        # 13 plantes dans ce cas, dont le modèle 3D est déployé et inutilisé.
        # La description de repli est écrite depuis le bloc anglais, qui est
        # sourcé. Elle ne s'applique qu'à l'absence : une description présente,
        # même médiocre, reste celle du producteur et n'est pas écrasée ici.
        repli = replis.get(cle) or {}
        if not source.get("description") and repli.get("fr"):
            source = dict(source)
            source["description"] = repli["fr"].strip()
            depuis_repli += 1
        doc, motif = assembler(cle, redac, slug, source, axes, repli)
        if doc is None:
            refuses.append((cle, motif))
            continue
        if "fr" not in doc["translations"]:
            sans_fr += 1
        prets.append(doc)

    print(f"  fiches assemblées      : {len(prets)}", file=sys.stderr)
    print(f"  dont description de repli : {depuis_repli}", file=sys.stderr)
    print(f"  dont sans traduction fr: {sans_fr}", file=sys.stderr)
    print(f"  refusées               : {len(refuses)}", file=sys.stderr)
    for cle, motif in refuses[:10]:
        print(f"      {cle} — {motif}", file=sys.stderr)
    print("  ⚠️  `imageURLs` reste vide : l'URL porte l'_id, qui n'existe "
          "qu'après insertion. Seconde passe après le rendu de la vignette.",
          file=sys.stderr)

    if a.out:
        Path(a.out).write_text(
            json.dumps({"nouvelles": prets}, ensure_ascii=False, indent=1),
            encoding="utf-8")
        print(f"  écrit : {a.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
