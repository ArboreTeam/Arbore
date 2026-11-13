#!/usr/bin/env python3
"""Contrôle des blocs de traduction et émission des opérations qui les posent.

Séparé de l'écriture, comme les autres scripts de catalogue : il ne touche
aucune base, il produit un fichier d'opérations que `appliquer-ops-mongo.py`
applique après relecture.

## Ce qu'il refuse, et pourquoi chaque refus existe

Un bloc de traduction est écrit à la main, donc il dérive. Les contrôles ne
sont pas des précautions de principe : chacun correspond à une panne vécue sur
ce catalogue.

  - **la forme doit être celle de l'anglais** — mêmes clés, mêmes types. Le
    décodeur Go lit `Translations map[string]LanguageData` : une chaîne là où il
    attend `[]string` fait échouer `cursor.All`, donc le décodage de TOUT le
    curseur. Le 2026-11-11, trois champs mal typés sur 126 fiches ont rendu les
    249 du catalogue inservables, et arrêté le rendu des vignettes avec elles.
  - **une liste doit garder son nombre d'éléments.** Fusionner quatre puces en
    un paragraphe ne casse pas le décodage, mais l'application affiche des
    puces : la fiche traduite n'aurait plus la même structure que l'anglaise.
  - **`fr.description` doit être exactement la description servie à la racine.**
    Sur les 123 fiches déjà traduites, les deux coïncident toujours. Traduire
    l'anglais donnerait deux textes français différents pour la même plante.
  - **aucun tiret cadratin** (U+2014). Le reste du catalogue emploie le
    demi-cadratin pour les plages ; le mélange se voit à l'écran.
  - **la virgule décimale** en fr, es et de. Relevé sur les 123 fiches servies :
    `fr` et `de` portent **zéro** point décimal contre 43 et 44 fiches à
    virgule, `en` l'inverse exactement. Ce n'est donc pas une préférence, c'est
    la convention du catalogue — et deux agents de rédaction l'avaient tranchée
    dans deux sens opposés, ce qui est précisément ce qu'un contrôle évite.
  - **`care.difficulty` n'est pas repris du bloc traduit**, il est posé ici par
    correspondance fermée depuis `_meta.difficulty`. Son vocabulaire est
    relevé sur les 123 fiches servies, et #485 rappelle qu'un `difficulty`
    absent ne neutralise pas le filtre du catalogue : il le **vide**.

  python3 scripts/appliquer-traductions.py --nouvelles <rép> \\
      --traductions <rép> --fr-source <fichier.json> [--out ops.json]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

LANGUES = ("fr", "es", "de")

# Relevé sur les 123 fiches servies, dans les quatre langues. Valeurs closes :
# le filtre du catalogue compare des chaînes, une variante ne filtre rien.
DIFFICULTE = {
    "easy": {"en": "Easy", "fr": "Facile", "es": "Fácil", "de": "Einfach"},
    "medium": {"en": "Moderate", "fr": "Intermédiaire", "es": "Intermedio",
               "de": "Mittel"},
    "hard": {"en": "Hard", "fr": "Exigeant", "es": "Difícil",
             "de": "Anspruchsvoll"},
}

CADRATIN = "—"

# Un point entre deux chiffres, c'est-à-dire un séparateur décimal anglais.
# Sûr parce qu'il est absent des blocs fr et de des 123 fiches servies : le
# motif n'attrape donc rien de légitime dans ce corpus.
POINT_DECIMAL = re.compile(r"\d\.\d")


def ecarts(ref: Any, bloc: Any, chemin: str = "") -> list[str]:
    """Compare un bloc traduit à son modèle anglais, et nomme chaque écart.

    La comparaison est structurelle : ni le texte ni la langue ne sont jugés
    ici, seulement la forme. Rend la liste des écarts, vide si le bloc est
    conforme.
    """
    out: list[str] = []
    if isinstance(ref, dict):
        if not isinstance(bloc, dict):
            return [f"{chemin or '(racine)'} devrait être un objet"]
        for k in ref:
            ou = f"{chemin}.{k}" if chemin else k
            if k not in bloc:
                out.append(f"{ou} manquant")
            else:
                out += ecarts(ref[k], bloc[k], ou)
        for k in bloc:
            if k not in ref:
                out.append(f"{chemin}.{k} en trop" if chemin else f"{k} en trop")
        return out
    if isinstance(ref, list):
        if not isinstance(bloc, list):
            return [f"{chemin} devrait être une liste, reçu {type(bloc).__name__}"]
        if len(ref) != len(bloc):
            out.append(f"{chemin} a {len(bloc)} éléments au lieu de {len(ref)}")
        out += [f"{chemin}[{i}] n'est pas une chaîne"
                for i, v in enumerate(bloc) if not isinstance(v, str)]
        return out
    if isinstance(ref, str) and not isinstance(bloc, str):
        return [f"{chemin} devrait être une chaîne, reçu {type(bloc).__name__}"]
    return out


def _textes(o: Any) -> list[str]:
    if isinstance(o, str):
        return [o]
    if isinstance(o, dict):
        return [s for v in o.values() for s in _textes(v)]
    if isinstance(o, list):
        return [s for v in o for s in _textes(v)]
    return []


def controler(cle: str, redac: dict, trad: dict, fr_source: dict) -> list[str]:
    """Tous les refus d'une fiche, nommés. Liste vide si elle passe."""
    motifs: list[str] = []
    en = (redac.get("translations") or {}).get("en")
    if not en:
        return ["translations.en absent de la fiche rédigée"]

    # `care.difficulty` est posé par ce script : l'anglais ne le porte pas, et
    # un bloc traduit qui l'invente serait signalé « en trop » à juste titre.
    modele = {k: v for k, v in en.items()}
    modele["care"] = {k: v for k, v in (en.get("care") or {}).items()
                      if k != "difficulty"}

    for lg in LANGUES:
        bloc = trad.get(lg)
        if not bloc:
            motifs.append(f"{lg} absent")
            continue
        sans_diff = {k: v for k, v in bloc.items()}
        sans_diff["care"] = {k: v for k, v in (bloc.get("care") or {}).items()
                             if k != "difficulty"}
        motifs += [f"{lg}.{e}" for e in ecarts(modele, sans_diff)]
        for t in _textes(bloc):
            if CADRATIN in t:
                motifs.append(f"{lg} contient un tiret cadratin : {t[:60]!r}")
                break
        for t in _textes(bloc):
            if m := POINT_DECIMAL.search(t):
                motifs.append(f"{lg} garde un point décimal anglais "
                              f"({m.group()}) : {t[:60]!r}")
                break

    attendue = (fr_source.get(cle) or {}).get("description")
    rendue = (trad.get("fr") or {}).get("description")
    if attendue and rendue != attendue:
        motifs.append("fr.description n'est pas la description servie à la racine")

    niveau = (redac.get("_meta") or {}).get("difficulty")
    if niveau not in DIFFICULTE:
        motifs.append(f"_meta.difficulty vaut {niveau!r}, attendu "
                      f"{'/'.join(DIFFICULTE)}")
    return motifs


def operation(cle: str, redac: dict, trad: dict) -> dict:
    """L'opération qui pose les trois langues et les quatre `difficulty`."""
    niveau = DIFFICULTE[(redac.get("_meta") or {})["difficulty"]]
    set_: dict[str, Any] = {}
    for lg in LANGUES:
        bloc = {k: v for k, v in trad[lg].items()}
        bloc["care"] = {k: v for k, v in (bloc.get("care") or {}).items()
                        if k != "difficulty"}
        bloc["care"]["difficulty"] = niveau[lg]
        set_[f"translations.{lg}"] = bloc
    # L'anglais existe déjà en base ; seul son `difficulty` manque.
    set_["translations.en.care.difficulty"] = niveau["en"]
    return {"modelURL": f"{cle}_potless.usdz", "set": set_}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--nouvelles", required=True, type=Path)
    ap.add_argument("--traductions", required=True, type=Path)
    ap.add_argument("--fr-source", required=True, type=Path)
    ap.add_argument("--out")
    a = ap.parse_args()

    fr_source = json.loads(a.fr_source.read_text("utf-8"))
    prets, refuses, absents = [], [], []
    for cle in sorted(fr_source):
        f = a.traductions / f"{cle}.json"
        if not f.exists():
            absents.append(cle)
            continue
        redac = json.loads((a.nouvelles / f"{cle}.json").read_text("utf-8"))
        try:
            trad = json.loads(f.read_text("utf-8"))
        except ValueError as e:
            refuses.append((cle, [f"JSON illisible : {e}"]))
            continue
        motifs = controler(cle, redac, trad, fr_source)
        if motifs:
            refuses.append((cle, motifs))
            continue
        prets.append(operation(cle, redac, trad))

    print(f"  fiches attendues   : {len(fr_source)}", file=sys.stderr)
    print(f"  traductions prêtes : {len(prets)}", file=sys.stderr)
    print(f"  pas encore écrites : {len(absents)}", file=sys.stderr)
    print(f"  refusées           : {len(refuses)}", file=sys.stderr)
    for cle, motifs in refuses[:15]:
        print(f"      {cle} — {len(motifs)} écart(s)", file=sys.stderr)
        for m in motifs[:4]:
            print(f"          {m}", file=sys.stderr)

    if a.out:
        Path(a.out).write_text(
            json.dumps({"plantes": prets}, ensure_ascii=False, indent=1),
            encoding="utf-8")
        print(f"  écrit : {a.out}", file=sys.stderr)
    return 1 if refuses else 0


if __name__ == "__main__":
    sys.exit(main())
