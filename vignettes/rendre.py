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
from mathutils import Quaternion, Vector

# Gabarit servi, mesuré sur les 123 vignettes en service.
LARGEUR, HAUTEUR = 720, 900

# Studio repris de `PlantThumbnailRenderer` : le catalogue doit garder une
# seule allure, et c'est celle-là qui est en service. Les trois premières
# valeurs sont copiées du moteur iOS ; la quatrième est MESURÉE sur une
# vignette servie, parce que RealityKit applique son propre rendu à son mur
# « non éclairé » et que sa couleur nominale (0,72) sort à 161, pas à 184.
CHAMP_VERTICAL = 35.0      # cameraFOVDegrees
REMPLISSAGE = 0.70         # fillFactor
INCLINAISON = 8.0          # cameraPitchDegrees, vers le bas

# Décor : pelouse et ciel clair.
#
# Le beige prolonge la palette de l'app, dont le fond vaut #F0EEEA. Il n'est
# toutefois PAS repris tel quel : sa clarté vaut 238, au-dessus du seuil de
# 225 ci-dessous, et l'app refuserait toutes les vignettes. Celui-ci est de la
# même famille, en plus soutenu — et il se distingue aussi du fond des cartes,
# #FFFFFF en thème clair et #24231F en sombre.
CIEL = "#D5CBB8"
HERBE = "#628A4B"

# Plafond de clarté du ciel, et ce n'est pas un réglage de goût.
# `hasLegacyWhiteWallDarkFloor` REFUSE la vignette dès que deux de ses cinq
# points hauts dépassent 225 — le symptôme de l'ancien design, mur blanc sur
# sol sombre. Un ciel « clair » passe cette barre sans prévenir, et l'app
# rejetterait alors en silence toutes les vignettes du catalogue.
CIEL_CLARTE_MAX = 215


def vers_lineaire(c):
    """Octet sRGB vers la valeur linéaire que Blender attend d'un matériau."""
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def cadrer(largeur, hauteur, profondeur, rapport):
    """Port littéral de `PlantThumbnailFraming.fit`.

    Recalculer ce cadrage « à peu près » donnerait des vignettes qui ne se
    superposent pas aux anciennes : la plante changerait de taille d'une fiche
    à l'autre selon celle qui a été régénérée. On copie donc la formule, y
    compris sa prise en compte de la PROFONDEUR — c'est elle qui, une fois la
    caméra inclinée, fait sortir du cadre les plantes larges.
    """
    largeur = max(largeur, 0.001)
    hauteur = max(hauteur, 0.001)
    profondeur = max(profondeur, 0.001)
    rapport = max(rapport, 0.1)
    remplissage = min(max(REMPLISSAGE, 0.1), 0.95)

    demi_champ = CHAMP_VERTICAL * math.pi / 360
    tan_vertical = max(math.tan(demi_champ), 0.001)
    tan_horizontal = max(tan_vertical * rapport, 0.001)
    inclinaison = INCLINAISON * math.pi / 180
    sinus = abs(math.sin(inclinaison))
    cosinus = abs(math.cos(inclinaison))

    demi_vertical = (hauteur * 0.5 * cosinus) + (profondeur * 0.5 * sinus)
    demi_horizontal = largeur * 0.5
    demi_profondeur = (hauteur * 0.5 * sinus) + (profondeur * 0.5 * cosinus)

    marge_verticale = demi_vertical / (tan_vertical * remplissage)
    marge_horizontale = demi_horizontal / (tan_horizontal * remplissage)
    distance = demi_profondeur + max(marge_verticale, marge_horizontale)
    vise_z = hauteur * 0.5

    return {"distance": distance,
            "camera_z": vise_z + distance * math.sin(inclinaison),
            "camera_y": distance * math.cos(inclinaison),
            "vise_z": vise_z}

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

    # Qualité des ombres. Laissés par défaut, ces réglages donnent une ombre
    # portée mouchetée : EEVEE échantillonne la pénombre de façon stochastique,
    # et un feuillage fin est exactement le cas qui la fait bruiter. Le feuillage
    # est aussi ce qu'on photographie — l'ombre d'une plante EST une dentelle.
    s.eevee.use_shadows = True
    # Lancer de rayons COUPÉ, et ce n'est pas une économie. Activé, la pelouse
    # déteint sur le pot blanc par rayonnement indirect : physiquement juste,
    # inacceptable pour un catalogue où le pot doit rester blanc d'une fiche à
    # l'autre quelle que soit la couleur du sol. Ce n'est de toute façon pas
    # lui qui nettoie l'ombre — ce sont les trois réglages ci-dessous.
    s.eevee.use_raytracing = False
    s.eevee.shadow_ray_count = 4
    s.eevee.shadow_step_count = 16
    s.eevee.shadow_resolution_scale = 1.0
    s.eevee.shadow_pool_size = "1024"
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


def rvb(hexa):
    """`#RRGGBB` vers trois octets."""
    h = hexa.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def clarte(couleur):
    """Clarté Rec. 709, la même formule que `sampledBrightness` côté app."""
    r, v, b = couleur
    return 0.2126 * r + 0.7152 * v + 0.0722 * b


def poser_fond_studio(cadre, hauteur, largeur, profondeur, ciel, herbe, teinte_sol):
    """Pelouse et ciel : sol vert lisse, fond uni non éclairé.

    Le ciel est ÉMISSIF, et non éclairé comme une surface ordinaire. Sa
    couleur ne dépend donc ni des lampes ni de leur distance : le fond est
    rigoureusement plat d'un bord à l'autre et, surtout, IDENTIQUE d'une
    plante à l'autre. Éclairé, il prendrait un dégradé qui varierait avec la
    taille du sujet, et deux fiches voisines n'auraient pas le même ciel.

    Le sol, lui, reste éclairé : c'est lui qui reçoit l'ombre de contact, celle
    qui pose la plante au sol au lieu de la laisser flotter.
    """
    couleur_ciel = rvb(ciel)
    if clarte(couleur_ciel) > CIEL_CLARTE_MAX:
        raise SystemExit(
            f"ciel {ciel} trop clair : clarté {clarte(couleur_ciel):.0f} > "
            f"{CIEL_CLARTE_MAX}. Au-delà de 225, hasLegacyWhiteWallDarkFloor "
            f"refuse la vignette et l'app garde l'ancienne image, en silence.")

    echelle = max(hauteur, largeur, profondeur, cadre["distance"])
    taille = echelle * 10

    # --- pelouse, à -0,001 comme le sol du moteur iOS
    bpy.ops.mesh.primitive_plane_add(size=taille, location=(0, 0, -0.001))
    sol = bpy.context.active_object
    mat_sol = bpy.data.materials.new("pelouse")
    mat_sol.use_nodes = True
    principal = mat_sol.node_tree.nodes["Principled BSDF"]
    # La teinte dépasse 1, et c'est délibéré : le sol est un DÉCOR dont la
    # clarté est choisie, pas le résultat d'un éclairage physique. L'obtenir en
    # montant les lampes brûlerait le pot blanc — mesuré, 2,62 % de pixels
    # saturés contre 0,05 % sur une vignette servie. Multiplier n'écrase pas
    # l'ombre portée, qui est multipliée aussi : le contraste tient.
    vert = tuple(min(vers_lineaire(c) * teinte_sol, 1.0) for c in rvb(herbe))
    principal.inputs["Base Color"].default_value = (*vert, 1.0)
    principal.inputs["Roughness"].default_value = 0.92
    principal.inputs["Metallic"].default_value = 0.0
    sol.data.materials.append(mat_sol)

    # --- ciel, à la même distance que le mur du moteur iOS
    mur_y = profondeur + cadre["distance"] * 0.3
    bpy.ops.mesh.primitive_plane_add(size=taille, location=(0, mur_y, taille / 2))
    mur = bpy.context.active_object
    mur.rotation_euler[0] = math.radians(90)
    mat_mur = bpy.data.materials.new("ciel")
    mat_mur.use_nodes = True
    arbre = mat_mur.node_tree
    emission = arbre.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*[vers_lineaire(c) for c in couleur_ciel], 1.0)
    emission.inputs["Strength"].default_value = 1.0
    arbre.links.new(emission.outputs["Emission"],
                    arbre.nodes["Material Output"].inputs["Surface"])
    mur.data.materials.append(mat_mur)
    return sol, mur


def poser_eclairage(cadre, hauteur, largeur, profondeur, puissance_cle, ambiante):
    """Clé presque zénithale, remplissage et contre-jour — plan du moteur iOS.

    L'orientation de la clé n'est pas réglée à vue : elle est DÉRIVÉE des deux
    mêmes quaternions que `PlantThumbnailRenderer`, puis amenée dans le repère
    de Blender. C'est elle qui donne l'ombre de contact courte, celle qui pose
    la plante sur le sol au lieu de la laisser flotter.

    Les intensités, elles, ne se transposent pas : RealityKit compte en lux et
    en lumens, Blender en watts, et le moteur iOS applique en plus son propre
    rendu. Elles sont donc réglées sur la clarté MESURÉE d'une vignette servie.
    """
    echelle = max(hauteur, largeur, profondeur, cadre["distance"])

    # simd_quatf(-0,42 pi, X) * simd_quatf(pi/12, Y) appliqué à (0, 0, -1),
    # puis iOS (x, y, z) -> Blender (x, -z, y).
    q = (Quaternion((1, 0, 0), -math.pi * 0.42)
         @ Quaternion((0, 1, 0), math.pi / 12))
    d = q @ Vector((0, 0, -1))
    direction = Vector((d.x, -d.z, d.y))

    bpy.ops.object.light_add(type="SUN", location=(0, 0, hauteur * 2))
    cle = bpy.context.active_object
    cle.data.energy = puissance_cle
    cle.data.angle = math.radians(3.0)   # ombre douce, pas un trait net
    # `use_shadow_jitter` : sans lui, la pénombre est approchée par un flou de
    # la carte d'ombre et les feuilles se résolvent en escalier. Avec, elle est
    # échantillonnée pour de bon — plus lente à converger, mais elle converge.
    cle.data.use_shadow_jitter = True
    cle.data.shadow_maximum_resolution = 0.0005
    cle.data.shadow_filter_radius = 2.0
    cle.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    distance = echelle * 1.2
    puissance = 0.30 * distance * distance   # ratio du moteur iOS, en watts

    bpy.ops.object.light_add(type="POINT",
                             location=(distance, -distance, hauteur * 0.9))
    remplissage = bpy.context.active_object
    remplissage.data.energy = puissance
    remplissage.data.color = (0.92, 0.92, 0.92)
    remplissage.data.shadow_soft_size = echelle * 0.3

    bpy.ops.object.light_add(type="POINT",
                             location=(-distance, distance, hauteur * 0.8))
    contre = bpy.context.active_object
    contre.data.energy = puissance
    contre.data.color = (0.92, 0.92, 0.92)
    contre.data.shadow_soft_size = echelle * 0.3

    # Ambiante : `isLegacyDarkThumbnail` rejette une vignette globalement trop
    # sombre, et les creux du feuillage tomberaient au noir sans elle.
    monde = bpy.data.worlds.new("studio")
    monde.use_nodes = True
    # 0,60 et non 0,25 : c'est l'ambiante, et non la clé, qui remonte le sol
    # et déboucher l'ombre. Monter la clé à la place écrêterait le pot blanc.
    monde.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.5, 0.5, 1.0)
    monde.node_tree.nodes["Background"].inputs[1].default_value = ambiante
    bpy.context.scene.world = monde


def poser_camera(cadre):
    """Caméra en perspective, au cadrage calculé par `cadrer`.

    En perspective et non en orthographique : c'est ce que fait le moteur iOS,
    et une vignette orthographique à côté d'une vignette en perspective se
    repère immédiatement dans une grille de catalogue.
    """
    bpy.ops.object.camera_add()
    cam = bpy.context.active_object
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(CHAMP_VERTICAL)
    cam.data.clip_start = 1e-4
    # La caméra est devant le sujet, donc en Y négatif ; `cadre["camera_y"]`
    # est la distance en profondeur, toujours positive.
    cam.location = (0, -cadre["camera_y"], cadre["camera_z"])
    cam.rotation_euler = (math.radians(90 - INCLINAISON), 0, 0)
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
    bpy.ops.object.empty_add(location=(0, 0, 0))
    sujet = bpy.context.active_object
    sujet.name = "arbore_sujet"

    racines_plante, plante = importer_usd(modele)
    for o in racines_plante:
        o.parent = sujet
    if not pot_chemin or not pose:
        bpy.context.view_layer.update()
        return sujet, plante, None

    racines_pot, pot = importer_usd(pot_chemin)

    bpy.ops.object.empty_add(location=(0, 0, 0))
    porteur = bpy.context.active_object
    porteur.name = "arbore_pot"
    for o in racines_pot:
        o.parent = porteur
    bpy.context.view_layer.update()
    porteur.parent = sujet

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
        terre.parent = sujet
        objets.append(terre)

    # Le sol se pose sous le POT, pas sous la boîte englobante : les racines du
    # modèle descendent plus bas que le fond du pot, qui les cache. Au plus bas
    # de la boîte, le pot flotte de cinq centimètres au-dessus du sol.
    bas_pot, _ = boite(pot)
    bpy.context.view_layer.update()
    return sujet, plante + objets, bas_pot.z


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--modele", required=True)
    ap.add_argument("--sortie", required=True)
    ap.add_argument("--pot")
    ap.add_argument("--pose", help="JSON de la pose, servi par le backend")
    ap.add_argument("--echantillons", type=int, default=64,
                    help="échantillons EEVEE ; baisser pour un essai rapide")
    ap.add_argument("--puissance-cle", type=float, default=4.0,
                    help="intensité de la clé, réglée sur la clarté mesurée")
    ap.add_argument("--ambiante", type=float, default=0.40,
                    help="force de l'ambiante du monde")
    ap.add_argument("--teinte-sol", type=float, default=0.84,
                    help="corrige l'éclairage du sol pour qu'il rende la "
                         "couleur demandée ; 0,84 = 1 / l'exposition mesurée")
    ap.add_argument("--ciel", default=CIEL, help="couleur du fond, #RRGGBB")
    ap.add_argument("--herbe", default=HERBE, help="couleur du sol, #RRGGBB")
    a = ap.parse_args(argv_apres_double_tiret())

    scene = scene_vide()
    scene.eevee.taa_render_samples = a.echantillons
    pose = json.loads(a.pose) if a.pose else None
    sujet, maillages, niveau_sol = composer(a.modele, a.pot, pose)

    # Pose au sol et centrage, comme le moteur iOS : `model.position.y` ramène
    # le bas sur le sol, puis le centre est ramené sur l'axe.
    #
    # À une différence près, et elle compte : iOS rend le modèle COMPLET, dont
    # le bas EST le fond de son pot. Ici la plante est servie sans pot, et ses
    # racines descendent plus bas que le cachepot qui les couvre. Poser la
    # boîte englobante sur le sol ferait donc flotter le pot de cinq
    # centimètres. C'est le fond du POT qui touche le sol.
    bas, haut = boite(maillages)
    sol = bas.z if niveau_sol is None else niveau_sol
    sujet.location = (-(bas.x + haut.x) / 2, -(bas.y + haut.y) / 2, -sol)
    bpy.context.view_layer.update()

    bas, haut = boite(maillages)
    hauteur = max(haut.z, 0.001)
    largeur = max(haut.x - bas.x, 0.001)
    profondeur = max(haut.y - bas.y, 0.001)
    print(f"sujet H={hauteur:.4f} L={largeur:.4f} P={profondeur:.4f}")

    cadre = cadrer(largeur, hauteur, profondeur, LARGEUR / HAUTEUR)
    poser_fond_studio(cadre, hauteur, largeur, profondeur,
                      a.ciel, a.herbe, a.teinte_sol)
    poser_eclairage(cadre, hauteur, largeur, profondeur,
                    a.puissance_cle, a.ambiante)
    poser_camera(cadre)

    scene.render.filepath = a.sortie
    bpy.ops.render.render(write_still=True)
    poser_marqueur(a.sortie)
    print(f"vignette écrite : {a.sortie}")


if __name__ == "__main__":
    main()
