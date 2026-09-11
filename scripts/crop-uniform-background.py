#!/usr/bin/env python3
"""Retire le fond uni autour d'un sujet, quand il y en a un et seulement alors.

## Le défaut

Les 97 photos venues de botanic sont des visuels produit : un sujet posé au
milieu d'un carré blanc. Les 25 photos Unsplash sont des photographies en
situation, qui remplissent leur cadre. Affichées côte à côte dans la même carte,
les premières paraissent « ne pas remplir » alors qu'elles remplissent
parfaitement : c'est leur propre fond blanc qu'on voit.

## La garantie, et ce qu'elle n'est pas

Ce script ne promet PAS de recadrer correctement toutes les images. Il promet de
**ne jamais recadrer à tort** : au moindre doute il s'abstient et dit pourquoi.

Le compromis est délibéré. Une image laissée telle quelle reste lisible ; une
image recadrée dans le sujet est abîmée définitivement, et personne ne le
remarque avant de la voir en production.

## Les quatre refus

1. **Bordure non uniforme.** L'anneau extérieur doit tenir dans une plage
   étroite. Une photo en situation a un ciel dégradé, un mur texturé, un flou
   d'arrière-plan : rien de tout cela ne passe.

2. **Image entièrement unie.** Le cas que vous avez nommé : un Unsplash tout
   vert. La couleur de bordure dévore alors l'image entière et il ne reste aucun
   sujet. Détecté par un contenu résiduel nul ou dérisoire.

3. **Rien à retirer.** Le sujet touche déjà les bords : recadrer ne gagnerait
   rien et risquerait de mordre.

4. **Le sujet touche un bord.** S'il est coupé par le cadre, on ignore ce qui
   manque hors champ. Recadrer les trois autres côtés déséquilibrerait le
   résultat, donc on s'abstient.

## Pourquoi une bordure et pas un remplissage par diffusion

Un remplissage depuis les coins suivrait le fond jusque dans les creux du sujet
— entre les feuilles d'une plante retombante, par exemple — et le recadrage
resterait juste. Mais il coûte cher et ne change rien au résultat, puisque seul
le rectangle englobant nous intéresse. On balaie donc par lignes et par colonnes
depuis chaque bord, ce qui se raisonne et se vérifie à l'œil nu.
"""

from __future__ import annotations
import argparse, json, sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow requis : python3 -m pip install Pillow")

# Tolérance, par canal, autour de la couleur de bordure. 12 laisse passer le
# bruit de compression JPEG et les dégradés très doux d'un fond studio, sans
# absorber un sujet clair posé sur blanc.
TOLERANCE = 12

# Écart toléré, par canal, entre un pixel de l'anneau et sa couleur médiane.
UNIFORMITE_BORDURE = 10

# Fraction de l'anneau qui doit tenir dans cet écart.
#
# On ne prend PAS le maximum. Une première version le faisait, et un seul pixel
# parasite — bruit JPEG, ombre portée d'un millimètre — suffisait à disqualifier
# une photo studio parfaitement propre : mesuré sur 11 des 97 visuels botanic,
# dont un écart de 11 pour un seuil de 10.
#
# Une photo d'ambiance, elle, ne rate pas ce seuil de justesse : son anneau
# dévie sur des dizaines de pourcents. La distinction reste donc franche.
PART_UNIFORME = 0.99

# En deçà, le « sujet » restant est trop petit pour être un sujet : on a
# probablement mangé l'image (cas de l'image entièrement unie).
SURFACE_MIN = 0.02

# Au-delà, il n'y a rien à retirer.
SURFACE_DEJA_PLEINE = 0.98

# Épaisseur de l'anneau échantillonné, en fraction du plus petit côté.
EPAISSEUR_ANNEAU = 0.02


def couleur_de_bordure(im: Image.Image) -> tuple[tuple[int, int, int], float]:
    """Couleur médiane de l'anneau extérieur, et la part qui s'en écarte."""
    w, h = im.size
    e = max(1, int(min(w, h) * EPAISSEUR_ANNEAU))
    pts = []
    for x in range(0, w, max(1, w // 64)):
        pts += [im.getpixel((x, y)) for y in range(e)]
        pts += [im.getpixel((x, y)) for y in range(h - e, h)]
    for y in range(0, h, max(1, h // 64)):
        pts += [im.getpixel((x, y)) for x in range(e)]
        pts += [im.getpixel((x, y)) for x in range(w - e, w)]

    canaux = list(zip(*pts))
    mediane = tuple(sorted(c)[len(c) // 2] for c in canaux)
    conformes = sum(
        1 for p in pts
        if all(abs(p[i] - mediane[i]) <= UNIFORMITE_BORDURE for i in range(3))
    )
    return mediane, conformes / len(pts)


def boite_du_sujet(im: Image.Image, fond: tuple[int, int, int]) -> tuple[int, int, int, int]:
    """Rectangle englobant de ce qui n'est pas le fond."""
    w, h = im.size
    px = im.load()

    def est_fond(p) -> bool:
        return all(abs(p[i] - fond[i]) <= TOLERANCE for i in range(3))

    def ligne_vide(y: int) -> bool:
        return all(est_fond(px[x, y]) for x in range(w))

    def colonne_vide(x: int) -> bool:
        return all(est_fond(px[x, y]) for y in range(h))

    haut = next((y for y in range(h) if not ligne_vide(y)), h)
    if haut == h:                      # tout est fond
        return (0, 0, 0, 0)
    bas = next(y for y in range(h - 1, -1, -1) if not ligne_vide(y))
    gauche = next(x for x in range(w) if not colonne_vide(x))
    droite = next(x for x in range(w - 1, -1, -1) if not colonne_vide(x))
    return (gauche, haut, droite + 1, bas + 1)


def analyser(chemin: Path, marge: int) -> dict:
    im = Image.open(chemin).convert("RGB")
    w, h = im.size
    surface = w * h

    fond, part = couleur_de_bordure(im)
    if part < PART_UNIFORME:
        return {"fichier": chemin.name, "action": "ignorée",
                "raison": f"bordure non uniforme ({part:.1%} conforme, il en faut {PART_UNIFORME:.0%})",
                "taille": [w, h]}

    x0, y0, x1, y1 = boite_du_sujet(im, fond)
    aire = (x1 - x0) * (y1 - y0)

    if aire == 0 or aire / surface < SURFACE_MIN:
        return {"fichier": chemin.name, "action": "ignorée",
                "raison": "image entièrement unie, aucun sujet à isoler",
                "taille": [w, h], "fond": list(fond)}

    if aire / surface > SURFACE_DEJA_PLEINE:
        return {"fichier": chemin.name, "action": "ignorée",
                "raison": "le sujet occupe déjà le cadre",
                "taille": [w, h], "fond": list(fond)}

    if x0 == 0 or y0 == 0 or x1 == w or y1 == h:
        return {"fichier": chemin.name, "action": "ignorée",
                "raison": "le sujet touche un bord, il est peut-être coupé hors champ",
                "taille": [w, h], "fond": list(fond)}

    x0 = max(0, x0 - marge); y0 = max(0, y0 - marge)
    x1 = min(w, x1 + marge); y1 = min(h, y1 + marge)

    return {"fichier": chemin.name, "action": "recadrée",
            "taille": [w, h], "fond": list(fond),
            "boite": [x0, y0, x1, y1],
            "nouvelle_taille": [x1 - x0, y1 - y0],
            "gain": round(1 - ((x1 - x0) * (y1 - y0)) / surface, 3)}


def autotest() -> int:
    """Vérifie les cinq verdicts sur des cas fabriqués, sans toucher au disque.

    Ces cas sont la spécification. Si l'un d'eux change de verdict, la règle a
    dérivé — c'est plus utile qu'un commentaire, parce que ça échoue.
    """
    import random
    from tempfile import TemporaryDirectory

    def sujet_sur_fond(fond, w=400, h=400, marge=80):
        im = Image.new("RGB", (w, h), fond)
        d = Image.new("RGB", (w - 2 * marge, h - 2 * marge))
        rng = random.Random(7)
        d.putdata([(rng.randrange(30, 90), rng.randrange(90, 160), rng.randrange(30, 90))
                   for _ in range(d.width * d.height)])
        im.paste(d, (marge, marge))
        return im

    cas = []

    # 1. Le cas nominal : un sujet au milieu d'un fond blanc.
    cas.append(("sujet sur fond blanc", sujet_sur_fond((255, 255, 255)), "recadrée"))

    # 2. Le cas que vous avez nommé : un Unsplash entièrement vert.
    cas.append(("image entièrement unie", Image.new("RGB", (400, 400), (46, 125, 50)), "ignorée"))

    # 3. Une photographie : du bruit partout, y compris au bord.
    rng = random.Random(3)
    photo = Image.new("RGB", (400, 400))
    photo.putdata([(rng.randrange(256), rng.randrange(256), rng.randrange(256))
                   for _ in range(400 * 400)])
    cas.append(("photographie en situation", photo, "ignorée"))

    # 4. Le sujet touche un bord : on ignore ce qui manque hors champ.
    touche = sujet_sur_fond((255, 255, 255))
    touche.paste(Image.new("RGB", (60, 60), (20, 90, 20)), (0, 170))
    cas.append(("sujet touchant un bord", touche, "ignorée"))

    # 5. Rien à retirer : le sujet occupe déjà presque tout.
    cas.append(("sujet déjà plein cadre", sujet_sur_fond((255, 255, 255), marge=2), "ignorée"))

    # 6. Un fond uni non blanc doit marcher aussi.
    cas.append(("sujet sur fond gris", sujet_sur_fond((184, 184, 184)), "recadrée"))

    echecs = 0
    with TemporaryDirectory() as tmp:
        for nom, image, attendu in cas:
            chemin = Path(tmp) / f"{nom.replace(' ', '_')}.png"
            image.save(chemin)
            obtenu = analyser(chemin, marge=8)
            marque = "ok" if obtenu["action"] == attendu else "ÉCHEC"
            if obtenu["action"] != attendu:
                echecs += 1
            detail = obtenu.get("raison", obtenu.get("nouvelle_taille", ""))
            print(f"  [{marque:5}] {nom:28} → {obtenu['action']:9} {detail}", file=sys.stderr)

    print(f"\n  {len(cas) - echecs}/{len(cas)} verdicts attendus", file=sys.stderr)
    return 1 if echecs else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="*", help="fichiers à analyser")
    ap.add_argument("--autotest", action="store_true",
                    help="vérifie les règles sur des cas fabriqués, puis sort")
    ap.add_argument("--out", help="dossier de sortie ; sans lui, simulation seule")
    ap.add_argument("--marge", type=int, default=8,
                    help="pixels de fond conservés autour du sujet (défaut 8)")
    ap.add_argument("--json", action="store_true", help="sortie JSON")
    a = ap.parse_args()

    if a.autotest:
        return autotest()
    if not a.images:
        ap.error("préciser des images, ou --autotest")

    resultats = [analyser(Path(p), a.marge) for p in a.images]

    if a.out:
        dossier = Path(a.out)
        dossier.mkdir(parents=True, exist_ok=True)
        for r in resultats:
            if r["action"] != "recadrée":
                continue
            src = next(Path(p) for p in a.images if Path(p).name == r["fichier"])
            Image.open(src).convert("RGB").crop(tuple(r["boite"])).save(dossier / r["fichier"])

    if a.json:
        print(json.dumps(resultats, ensure_ascii=False, indent=1))
        return 0

    recadrees = [r for r in resultats if r["action"] == "recadrée"]
    print(f"  analysées : {len(resultats)}", file=sys.stderr)
    print(f"  recadrées : {len(recadrees)}", file=sys.stderr)
    print(f"  ignorées  : {len(resultats) - len(recadrees)}", file=sys.stderr)
    if not a.out:
        print("  (simulation — aucun fichier écrit)", file=sys.stderr)

    raisons = {}
    for r in resultats:
        if r["action"] == "ignorée":
            raisons[r["raison"]] = raisons.get(r["raison"], 0) + 1
    for raison, n in sorted(raisons.items(), key=lambda x: -x[1]):
        print(f"    · {n:3}  {raison}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
