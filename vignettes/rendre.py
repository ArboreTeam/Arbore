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

    # `Standard`, et surtout PAS le défaut de Blender 4.2, qui est AgX : un
    # rendu filmique qui désature et relève les noirs. SceneKit, lui, n'applique
    # aucun tonemapping. Laissé par défaut, le feuillage sortait vert pâle là
    # où la vignette servie est franchement verte — un écart de style sur tout
    # le catalogue, pour un réglage que personne n'avait choisi.
    s.view_settings.view_transform = "Standard"
    s.view_settings.look = "None"
    s.view_settings.exposure = 0.0
    s.view_settings.gamma = 1.0
    s.display_settings.display_device = "sRGB"
    return s


def importer_usd(chemin):
    """Importe un USDZ et rend les objets maillés ajoutés.

    Blender lit l'USDZ comme n'importe quelle couche USD. Les matériaux
    `UsdPreviewSurface` de nos fichiers se mappent sur Principled BSDF, ce qui
    préserve baseColor ET metallicRoughness — les deux textures que les modèles
    sans réduction embarquent (#684).
    """
    avant = set(bpy.data.objects)
    # Pas de `import_subdiv` : nos USDZ ne déclarent pas de
    # `subdivisionScheme`, donc le défaut d'USD (catmullClark) s'appliquerait.
    # Essayé le 2026-10-31 sur le cachepot : AUCUN changement de silhouette.
    # On reste sur le maillage tel quel, comme l'AR l'affiche.
    bpy.ops.wm.usd_import(filepath=chemin, import_materials=True)
    ajoutes = set(bpy.data.objects) - avant
    maillages = [o for o in ajoutes if o.type == "MESH"]
    if not maillages:
        raise RuntimeError(f"aucun maillage importé depuis {chemin}")
    # Les racines PORTENT la conversion Y-up → Z-up : nos USDZ déclarent
    # `upAxis = Y` et Blender la matérialise par une rotation X+90° sur
    # l'Xform racine, pas sur le maillage. Reparenter un maillage sans elle le
    # couche — un pot de 10 cm de haut se mesure alors 5,9 cm, son rayon.
    racines = [o for o in ajoutes if o.parent not in ajoutes]
    return racines, maillages


def boite(objets):
    """Boîte englobante en coordonnées du monde."""
    pts = [o.matrix_world @ Vector(c) for o in objets for c in o.bound_box]
    bas = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    haut = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return bas, haut


def poser_fond_studio(bas, haut, niveau_sol=None):
    """Fond studio : un mur et un sol, en dégradé doux.

    Ce n'est pas de la décoration. `hasLegacyWhiteWallDarkFloor` rejette
    précisément un mur clair sur un sol sombre — l'ancien design — et
    `hasTopBackdropSeam` rejette une couture franche en haut de l'image. Le
    fond doit donc être continu et le sol pas plus sombre que le mur.
    """
    taille = max(haut.x - bas.x, haut.z - bas.z, haut.y - bas.y) * 12.0
    z = bas.z if niveau_sol is None else niveau_sol

    bpy.ops.mesh.primitive_plane_add(size=taille, location=(0, 0, z))
    sol = bpy.context.active_object
    bpy.ops.mesh.primitive_plane_add(size=taille, location=(0, taille / 2.2, z))
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
    # 110 et non 260 : en vue `Standard`, sans la compression des hautes
    # lumières d'AgX, la clé à 260 écrêtait le pot blanc et effaçait le
    # relief en nid d'abeilles qu'elle est censée révéler.
    cle.data.energy = etendue * etendue * 110
    cle.data.size = etendue * 1.4
    cle.rotation_euler = (math.radians(52), 0, math.radians(38))

    bpy.ops.object.light_add(type="AREA",
                             location=(-etendue * 1.5, -etendue * 1.2, haut.z * 0.6))
    remplissage = bpy.context.active_object
    remplissage.data.energy = etendue * etendue * 60
    remplissage.data.size = etendue * 2.0
    remplissage.rotation_euler = (math.radians(74), 0, math.radians(-42))

    # Ambiante : empêche les creux de tomber au noir. `isLegacyDarkThumbnail`
    # rejette une vignette globalement trop sombre.
    monde = bpy.data.worlds.new("studio")
    monde.use_nodes = True
    monde.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.55, 0.55, 1.0)
    monde.node_tree.nodes["Background"].inputs[1].default_value = 0.48
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
    # `Non-Color` AVANT de lire les pixels, et c'est tout l'enjeu : l'image est
    # alors lue et réécrite telle quelle, sans transfert. On pose donc les
    # octets sRGB attendus par le détecteur, qui compare des OCTETS de PNG.
    #
    # Sans ce réglage, la tentation est de convertir la couleur en linéaire en
    # supposant que l'écriture reconvertira. Elle ne reconvertit pas : le
    # premier essai a produit (29, 3, 125) — exactement les valeurs linéaires
    # de (94, 28, 186) — et le détecteur, qui tolère 5, a refusé les 4 coins.
    img.colorspace_settings.name = "Non-Color"
    l, h = img.size
    cote = max(4, int(min(l, h) * MARQUEUR_PART))
    px = list(img.pixels)

    r, v, b = (c / 255.0 for c in MARQUEUR_RVB)

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


def _conv(x, y, z):
    """Pose du backend (Y en haut, comme SceneKit) vers le repère de Blender.

    L'importateur USD de Blender convertit la scène en Z-up ; la pose, elle,
    arrive dans le repère du modèle. Il faut lui appliquer LA MÊME conversion,
    sans quoi la hauteur et la profondeur sont interverties.
    """
    return (float(x), -float(z), float(y))


def composer(modele, pot_chemin, pose):
    """Assemble la plante, son pot et le disque de terre.

    `pose` vient du BACKEND, pas d'un calcul local : la règle de composition
    vit dans `PlantPotComposer` et le serveur la sert. La recalculer ici en
    ferait une seconde source, et l'AR comme les vignettes divergeraient sans
    que rien ne le signale.

    La structure calque `attachPot` : les maillages du pot sont groupés sous un
    PARENT, et c'est le parent qu'on met à l'échelle et qu'on translate. Mettre
    chaque objet à l'échelle séparément le ferait grandir autour de son propre
    centre et aplatirait les décalages internes du pot — un pot désassemblé,
    pour un fichier à plusieurs maillages.
    """
    _, plante = importer_usd(modele)
    if not pot_chemin or not pose:
        return plante, None

    racines_pot, pot = importer_usd(pot_chemin)

    bpy.ops.object.empty_add(location=(0, 0, 0))
    porteur = bpy.context.active_object
    porteur.name = "arbore_pot"
    for o in racines_pot:
        o.parent = porteur
    bpy.context.view_layer.update()

    # `potMax` dans l'espace LOCAL du porteur, comme `noeud.boundingBox` : le
    # porteur est encore à l'identité, donc le monde EST son espace local.
    _, haut_local = boite(pot)
    e = float(pose["scale"])
    x, y, z = _conv(pose["x"], pose["y"], pose["z"])
    porteur.scale = (e, e, e)
    porteur.location = (x, y, z - haut_local.z * e)
    bpy.context.view_layer.update()

    print(f"pot local max z={haut_local.z:.5f} x={haut_local.x:.5f} "
          f"y={haut_local.y:.5f} | echelle={e:.5f} | "
          f"porteur={tuple(round(v, 5) for v in porteur.location)}")
    bas_p, haut_p = boite(plante)
    print(f"plante bas={tuple(round(v, 5) for v in bas_p)} "
          f"haut={tuple(round(v, 5) for v in haut_p)}")

    # Le porteur est un Empty : sa `bound_box` vaut huit zéros et étendrait le
    # cadrage jusqu'à l'origine du monde. Seuls les maillages sont mesurés.
    objets = list(pot)

    disque = pose.get("disque")
    if disque:
        dx, dy, dz = _conv(disque["x"], disque["y"], disque["z"])
        bpy.ops.mesh.primitive_cylinder_add(
            radius=float(disque["rayon"]),
            depth=float(disque["epaisseur"]),
            location=(dx, dy, dz))
        terre = bpy.context.active_object
        mat = bpy.data.materials.new("terre")
        mat.use_nodes = True
        p = mat.node_tree.nodes["Principled BSDF"]
        p.inputs["Base Color"].default_value = (0.21, 0.15, 0.10, 1.0)
        p.inputs["Roughness"].default_value = 0.95
        p.inputs["Metallic"].default_value = 0.0
        terre.data.materials.append(mat)
        objets.append(terre)

    # Le sol se pose sous le POT, pas sous la boîte englobante : les racines du
    # modèle descendent plus bas que le fond du pot, qui les cache. Au plus bas
    # de la boîte, le pot flotte de cinq centimètres au-dessus du sol.
    bas_pot, _ = boite(pot)
    return plante + objets, bas_pot.z


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--modele", required=True)
    ap.add_argument("--sortie", required=True)
    ap.add_argument("--pot")
    ap.add_argument("--pose", help="JSON de la pose, servi par le backend")
    a = ap.parse_args(argv_apres_double_tiret())

    scene_vide()
    pose = json.loads(a.pose) if a.pose else None
    objets, niveau_sol = composer(a.modele, a.pot, pose)

    bas, haut = boite(objets)
    if niveau_sol is not None and niveau_sol > bas.z:
        # Ce qui passe sous le sol est caché : le cadrer réserverait une bande
        # vide en bas de l'image.
        bas = Vector((bas.x, bas.y, niveau_sol))
    poser_fond_studio(bas, haut, niveau_sol)
    poser_eclairage(bas, haut)
    poser_camera(bas, haut)

    bpy.context.scene.render.filepath = a.sortie
    bpy.ops.render.render(write_still=True)
    poser_marqueur(a.sortie)
    print(f"vignette écrite : {a.sortie}")


if __name__ == "__main__":
    main()
