"""Rend une vignette de catalogue depuis un USDZ, dans Blender sans écran. (#695)

Invoqué par `publier.py`, jamais à la main :

    blender --background --python rendre.py -- --modele <f.usdz> --sortie <f.png>
            --pot <pot.usdz> --pose <json>

## Ce que ce rendu doit reproduire, et pourquoi c'est contraint

L'app ne se contente pas d'afficher ce qu'elle télécharge : `isLegacyThumbnail`
enchaîne quatre contrôles et **ignore en silence** une vignette qui en échoue
un seul. Le 30 octobre, 123 vignettes parfaitement valides — bon format, bonnes
dimensions, empreintes justes — ont été refusées faute du marqueur de design.
Rien ne le signalait : ni le fichier, ni le journal, ni la base.

Les quatre contrôles sont des statistiques de pixels sur de petites grilles,
donc déterministes et vérifiables. Ce script vise à les satisfaire, et
`publier.py` les contrôle avant d'envoyer quoi que ce soit.

## Choix de moteur

EEVEE et non Cycles. À 720×900 sur un fond uni, le tracé de chemin n'apporte
rien de visible et coûte un ordre de grandeur de temps. Le besoin est une
vignette de catalogue, pas une image de rendu.
"""
import argparse
import json
import math
import sys

import bpy
from mathutils import Vector

# Gabarit servi, mesuré sur les 123 vignettes en service.
LARGEUR, HAUTEUR = 720, 900

# Marqueur de design attendu par l'app : quatre carrés dans les coins.
# `PlantThumbnailCache.designMarkerColor` vaut (94, 28, 186) en sRGB 8 bits,
# et `applyingCurrentDesignMarker` les pose sur 3,5 % du plus petit côté.
MARQUEUR_RVB = (94, 28, 186)
MARQUEUR_PART = 0.035


def argv_apres_double_tiret():
    """Blender consomme ses propres options ; les nôtres suivent un `--`."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def scene_vide():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "BLENDER_EEVEE_NEXT"
    s.render.resolution_x = LARGEUR
    s.render.resolution_y = HAUTEUR
    s.render.resolution_percentage = 100
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGB"      # sans alpha : le fond est opaque
    s.render.film_transparent = False
    # Le filtre par défaut adoucit les bords ; à 720 px une feuille fine
    # disparaîtrait à moitié. 1,2 px garde l'anticrénelage sans fondre le trait.
    s.render.filter_size = 1.2
    return s


def importer_usd(chemin):
    """Importe un USDZ et rend les objets maillés ajoutés.

    Blender lit l'USDZ comme n'importe quelle couche USD. Les matériaux
    `UsdPreviewSurface` de nos fichiers se mappent sur Principled BSDF, ce qui
    préserve baseColor ET metallicRoughness — les deux textures que les modèles
    sans réduction embarquent (#684).
    """
    avant = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=chemin, import_materials=True)
    ajoutes = [o for o in set(bpy.data.objects) - avant if o.type == "MESH"]
    if not ajoutes:
        raise RuntimeError(f"aucun maillage importé depuis {chemin}")
    return ajoutes


def boite(objets):
    """Boîte englobante en coordonnées du monde."""
    pts = [o.matrix_world @ Vector(c) for o in objets for c in o.bound_box]
    bas = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    haut = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return bas, haut


def poser_fond_studio(bas, haut):
    """Fond studio : un mur et un sol, en dégradé doux.

    Ce n'est pas de la décoration. `hasLegacyWhiteWallDarkFloor` rejette
    précisément un mur clair sur un sol sombre — l'ancien design — et
    `hasTopBackdropSeam` rejette une couture franche en haut de l'image. Le
    fond doit donc être continu et le sol pas plus sombre que le mur.
    """
    taille = max(haut.x - bas.x, haut.z - bas.z, haut.y - bas.y) * 12.0

    bpy.ops.mesh.primitive_plane_add(size=taille, location=(0, 0, bas.z))
    sol = bpy.context.active_object
    bpy.ops.mesh.primitive_plane_add(size=taille, location=(0, taille / 2.2, bas.z))
    mur = bpy.context.active_object
    mur.rotation_euler[0] = math.radians(90)

    mat = bpy.data.materials.new("fond_studio")
    mat.use_nodes = True
    p = mat.node_tree.nodes["Principled BSDF"]
    # Gris moyen, identique au sol et au mur : ni mur blanc, ni sol sombre.
    p.inputs["Base Color"].default_value = (0.62, 0.62, 0.62, 1.0)
    p.inputs["Roughness"].default_value = 0.92
    p.inputs["Metallic"].default_value = 0.0
    for o in (sol, mur):
        o.data.materials.append(mat)
    return sol, mur


def poser_eclairage(bas, haut):
    """Lumière clé en biais, plus un remplissage doux.

    Le biais n'est pas esthétique : c'est lui qui fait ressortir le relief du
    pot. Les rendus de contrôle du 2026-10-30 ont montré que le motif en nid
    d'abeilles disparaît sous un éclairage frontal et apparaît nettement en
    latéral — ce qui a d'ailleurs corrigé le diagnostic de #682, où le pot
    était cru « plat » alors que c'était la lumière qui l'écrasait.
    """
    etendue = max(haut.x - bas.x, haut.y - bas.y, haut.z - bas.z, 1e-6)

    bpy.ops.object.light_add(type="AREA",
                             location=(etendue * 1.6, -etendue * 1.4, haut.z + etendue * 1.1))
    cle = bpy.context.active_object
    cle.data.energy = etendue * etendue * 260
    cle.data.size = etendue * 1.4
    cle.rotation_euler = (math.radians(52), 0, math.radians(38))

    bpy.ops.object.light_add(type="AREA",
                             location=(-etendue * 1.5, -etendue * 1.2, haut.z * 0.6))
    remplissage = bpy.context.active_object
    remplissage.data.energy = etendue * etendue * 90
    remplissage.data.size = etendue * 2.0
    remplissage.rotation_euler = (math.radians(74), 0, math.radians(-42))

    # Ambiante : empêche les creux de tomber au noir. `isLegacyDarkThumbnail`
    # rejette une vignette globalement trop sombre.
    monde = bpy.data.worlds.new("studio")
    monde.use_nodes = True
    monde.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.55, 0.55, 1.0)
    monde.node_tree.nodes["Background"].inputs[1].default_value = 0.55
    bpy.context.scene.world = monde


def poser_camera(bas, haut):
    """Cadrage orthographique, sujet centré avec une marge constante.

    Orthographique et non perspective : une vignette de catalogue se compare à
    la suivante, et une focale introduirait une déformation qui varierait avec
    la taille de la plante.
    """
    centre = (bas + haut) / 2
    hauteur_sujet = haut.z - bas.z
    largeur_sujet = max(haut.x - bas.x, haut.y - bas.y)

    bpy.ops.object.camera_add()
    cam = bpy.context.active_object
    cam.data.type = "ORTHO"
    # 1,18 : la marge des vignettes servies, mesurée sur le cadrage actuel.
    cam.data.ortho_scale = max(hauteur_sujet * HAUTEUR / LARGEUR, largeur_sujet) * 1.18
    cam.data.clip_start = 1e-4

    recul = max(hauteur_sujet, largeur_sujet) * 6
    cam.location = (0, -recul, centre.z)
    cam.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.scene.camera = cam
    return cam


def poser_marqueur(chemin_png):
    """Pose les quatre carrés du marqueur de design sur l'image rendue.

    APRÈS le rendu, et c'est l'ordre qui compte. L'app marque elle aussi en
    dernier, dans `save()` : fond studio, puis marqueur, puis écriture. Marquer
    avant un rééchantillonnage mélangerait le violet au fond et le détecteur ne
    le reconnaîtrait plus — on aurait le même symptôme qu'une vignette non
    marquée, avec un marqueur pourtant posé.

    Fait avec `bpy.data.images`, le seul outil d'image disponible ici : l'image
    n'est pas rééchantillonnée, seuls des pixels sont écrasés.
    """
    img = bpy.data.images.load(chemin_png)
    l, h = img.size
    cote = max(4, int(min(l, h) * MARQUEUR_PART))
    px = list(img.pixels)

    # Blender travaille en linéaire ; le PNG est en sRGB. On convertit la
    # couleur attendue plutôt que l'image : poser 94/255 tel quel donnerait un
    # violet plus clair à l'écriture, et le détecteur tolère moins de 12.
    def vers_lineaire(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, v, b = (vers_lineaire(c) for c in MARQUEUR_RVB)

    for x0, y0 in ((0, 0), (l - cote, 0), (0, h - cote), (l - cote, h - cote)):
        for y in range(y0, y0 + cote):
            base = (y * l + x0) * 4
            for i in range(cote):
                d = base + i * 4
                px[d], px[d + 1], px[d + 2], px[d + 3] = r, v, b, 1.0

    img.pixels = px
    img.filepath_raw = chemin_png
    img.file_format = "PNG"
    img.save()


def composer(modele, pot_chemin, pose):
    """Assemble la plante, son pot et le disque de terre.

    `pose` vient du BACKEND, pas d'un calcul local : la règle de composition
    vit dans `PlantPotComposer` et le serveur la sert. La recalculer ici en
    ferait une seconde source, et l'AR comme les vignettes divergeraient sans
    que rien ne le signale.
    """
    plante = importer_usd(modele)
    if not pot_chemin or not pose:
        return plante

    pot = importer_usd(pot_chemin)
    e = float(pose["scale"])
    # Les bornes du pot AVANT mise à l'échelle, comme le fait `attachPot`.
    pot_bas, pot_haut = boite(pot)
    for o in pot:
        o.scale = (e, e, e)
        o.location = (float(pose["x"]),
                      float(pose["z"]),
                      float(pose["y"]) - pot_haut.z * e)

    disque = pose.get("disque")
    if disque:
        bpy.ops.mesh.primitive_cylinder_add(
            radius=float(disque["rayon"]),
            depth=float(disque["epaisseur"]),
            location=(float(disque["x"]), float(disque["z"]), float(disque["y"])))
        terre = bpy.context.active_object
        mat = bpy.data.materials.new("terre")
        mat.use_nodes = True
        p = mat.node_tree.nodes["Principled BSDF"]
        p.inputs["Base Color"].default_value = (0.21, 0.15, 0.10, 1.0)
        p.inputs["Roughness"].default_value = 0.95
        p.inputs["Metallic"].default_value = 0.0
        terre.data.materials.append(mat)
        pot.append(terre)

    return plante + pot


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--modele", required=True)
    ap.add_argument("--sortie", required=True)
    ap.add_argument("--pot")
    ap.add_argument("--pose", help="JSON de la pose, servi par le backend")
    a = ap.parse_args(argv_apres_double_tiret())

    scene_vide()
    pose = json.loads(a.pose) if a.pose else None
    objets = composer(a.modele, a.pot, pose)

    bas, haut = boite(objets)
    poser_fond_studio(bas, haut)
    poser_eclairage(bas, haut)
    poser_camera(bas, haut)

    bpy.context.scene.render.filepath = a.sortie
    bpy.ops.render.render(write_still=True)
    poser_marqueur(a.sortie)
    print(f"vignette écrite : {a.sortie}")


if __name__ == "__main__":
    main()
