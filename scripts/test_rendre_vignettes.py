#!/usr/bin/env python3
"""Tests des fonctions pures de `vignettes/rendre.py`. (#725 point 7)

`rendre.py` fait 686 lignes et n'avait **aucun test de comportement** : le seul
qui le mentionnait LISAIT son texte pour vérifier un préfixe de journal. Le
correctif d'échelle de #718 a donc été prouvé par un rendu de 38 secondes, là
où trois lignes auraient suffi.

## Ce qui est testé, et pourquoi ce sont les bonnes cibles

Chacune de ces fonctions, cassée, produit un **refus SILENCIEUX de l'app** :
`isLegacyThumbnail` enchaîne quatre contrôles et ignore sans rien dire une
vignette qui en échoue un. Le 30 octobre, 123 vignettes valides ont été
refusées faute du marqueur — ni le fichier, ni le journal, ni la base ne le
signalaient. Ces constantes et ces formules sont donc du contrat, pas du
réglage.

## Pourquoi on peut les tester sans Blender

`rendre.py` importe `bpy` et `mathutils` à sa première ligne utile. On les
remplace dans `sys.modules` AVANT de charger le fichier. `Vector` est
réimplémenté pour de vrai — pas un mock : `boite()` en fait de l'arithmétique,
et un faux objet rendrait le test vide de sens.

    python3 -I -m unittest discover -s scripts -p 'test_*.py'
"""
import importlib.util
import math
import pathlib
import sys
import types
import unittest


class _Vecteur:
    """Le strict nécessaire de `mathutils.Vector` pour `boite()`."""

    def __init__(self, coordonnees):
        self.x, self.y, self.z = (float(v) for v in coordonnees)

    def __iter__(self):
        return iter((self.x, self.y, self.z))

    def __repr__(self):
        return f"_Vecteur({self.x}, {self.y}, {self.z})"


class _MatriceIdentite:
    """`o.matrix_world @ Vector(c)` : ici l'identité, les coins font foi."""

    def __matmul__(self, vecteur):
        return vecteur


class _Objet:
    """Un maillage réduit à ce que `boite()` lui demande."""

    def __init__(self, coins):
        self.bound_box = coins
        self.matrix_world = _MatriceIdentite()
        self.scale = (1.0, 1.0, 1.0)


def _pave(xmin, ymin, zmin, xmax, ymax, zmax):
    """Les huit coins d'un pavé, dans l'ordre qu'importe peu à `boite()`."""
    return [(x, y, z)
            for x in (xmin, xmax)
            for y in (ymin, ymax)
            for z in (zmin, zmax)]


def _charger_rendre():
    """Charge `rendre.py` avec `bpy` et `mathutils` simulés."""
    bpy = types.ModuleType("bpy")
    bpy.ops = types.SimpleNamespace()
    bpy.data = types.SimpleNamespace()
    # `view_layer.update()` est appelé par `normaliser_echelle` ; sans scène
    # réelle il n'a rien à faire, mais il doit exister.
    bpy.context = types.SimpleNamespace(
        view_layer=types.SimpleNamespace(update=lambda: None))

    mathutils = types.ModuleType("mathutils")
    mathutils.Vector = _Vecteur
    mathutils.Quaternion = object

    sys.modules["bpy"] = bpy
    sys.modules["mathutils"] = mathutils

    chemin = pathlib.Path(__file__).resolve().parents[1] / "vignettes" / "rendre.py"
    spec = importlib.util.spec_from_file_location("rendre_vignettes", chemin)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rendre = _charger_rendre()


# --- Le contrat avec l'app ------------------------------------------------

class ContratAvecLApp(unittest.TestCase):
    """Des constantes dont la violation est INVISIBLE à l'exécution."""

    def test_le_ciel_reste_sous_le_plafond_de_clarte(self):
        """La garde la plus silencieuse de toute la chaîne.

        `hasLegacyWhiteWallDarkFloor` REFUSE une vignette dès que deux de ses
        cinq points hauts dépassent 225 — le symptôme de l'ancien design, mur
        blanc sur sol sombre. Un ciel « un peu plus clair » franchirait cette
        barre sans que rien ne le dise, et l'app garderait les anciennes
        images pour TOUT le catalogue.
        """
        clarte_du_ciel = rendre.clarte(rendre.rvb(rendre.CIEL))
        self.assertLessEqual(
            clarte_du_ciel, rendre.CIEL_CLARTE_MAX,
            f"le ciel {rendre.CIEL} a une clarté de {clarte_du_ciel:.0f}, "
            f"au-dessus du plafond {rendre.CIEL_CLARTE_MAX} : l'app refuserait "
            f"toutes les vignettes, en silence")

    def test_le_plafond_reste_sous_le_seuil_de_lapp(self):
        """225 est le seuil de l'app ; 215 est notre marge. Elle doit exister."""
        self.assertLess(rendre.CIEL_CLARTE_MAX, 225)

    def test_le_marqueur_porte_la_couleur_exacte_attendue_par_lapp(self):
        """`PlantThumbnailCache.designMarkerColor` vaut (94, 28, 186).

        Le détecteur compare des OCTETS et tolère 5. Une valeur voisine
        passerait le test « à l'œil » et échouerait le détecteur — exactement
        le défaut du 30 octobre, où 123 vignettes valides ont été refusées.
        """
        self.assertEqual(rendre.MARQUEUR_RVB, (94, 28, 186))

    def test_le_marqueur_couvre_la_part_attendue(self):
        """`applyingCurrentDesignMarker` pose 3,5 % du plus petit côté."""
        self.assertAlmostEqual(rendre.MARQUEUR_PART, 0.035)

    def test_le_gabarit_est_celui_des_vignettes_en_service(self):
        """720×900, mesuré sur les 123 vignettes servies."""
        self.assertEqual((rendre.LARGEUR, rendre.HAUTEUR), (720, 900))


# --- Couleurs -------------------------------------------------------------

class Couleurs(unittest.TestCase):

    def test_rvb_lit_un_hexadecimal_avec_ou_sans_diese(self):
        self.assertEqual(rendre.rvb("#D5CBB8"), (213, 203, 184))
        self.assertEqual(rendre.rvb("628A4B"), (98, 138, 75))

    def test_clarte_suit_rec_709(self):
        self.assertAlmostEqual(rendre.clarte((255, 255, 255)), 255.0, places=4)
        self.assertAlmostEqual(rendre.clarte((0, 0, 0)), 0.0, places=4)
        # Le vert pèse le plus lourd des trois, le bleu le moins.
        self.assertGreater(rendre.clarte((0, 255, 0)), rendre.clarte((255, 0, 0)))
        self.assertGreater(rendre.clarte((255, 0, 0)), rendre.clarte((0, 0, 255)))

    def test_vers_lineaire_respecte_les_deux_branches_de_srgb(self):
        """La courbe sRGB est linéaire en bas, puissance 2,4 au-dessus.

        Se tromper de branche éclaircit ou assombrit tout le décor sans que
        rien n'échoue — et le sol a justement une teinte MESURÉE.
        """
        self.assertAlmostEqual(rendre.vers_lineaire(0), 0.0)
        self.assertAlmostEqual(rendre.vers_lineaire(255), 1.0, places=6)
        # 10/255 = 0,0392 < 0,04045 : branche linéaire.
        self.assertAlmostEqual(rendre.vers_lineaire(10), (10 / 255) / 12.92)
        # 128/255 = 0,502 : branche puissance.
        attendu = ((128 / 255 + 0.055) / 1.055) ** 2.4
        self.assertAlmostEqual(rendre.vers_lineaire(128), attendu)

    def test_vers_lineaire_est_monotone(self):
        valeurs = [rendre.vers_lineaire(c) for c in range(0, 256, 17)]
        self.assertEqual(valeurs, sorted(valeurs))


# --- Repères --------------------------------------------------------------

class ConversionDeRepere(unittest.TestCase):
    """Y-up (SceneKit, d'où vient la pose) vers Z-up (ce que Blender importe).

    Se tromper ici intervertit la HAUTEUR et la PROFONDEUR : le pot se
    retrouve couché, et rien ne lève d'erreur.
    """

    def test_la_hauteur_du_backend_devient_le_z_de_blender(self):
        self.assertEqual(rendre._conv(0, 7, 0), (0.0, 0.0, 7.0))

    def test_la_profondeur_change_de_signe(self):
        self.assertEqual(rendre._conv(0, 0, 3), (0.0, -3.0, 0.0))

    def test_le_x_est_inchange(self):
        self.assertEqual(rendre._conv(5, 0, 0), (5.0, 0.0, 0.0))

    def test_la_conversion_rend_des_flottants(self):
        """La pose arrive en JSON ; des entiers s'y glissent."""
        for valeur in rendre._conv(1, 2, 3):
            self.assertIsInstance(valeur, float)


# --- Cadrage --------------------------------------------------------------

class Cadrage(unittest.TestCase):
    """Port littéral de `PlantThumbnailFraming.fit`.

    Recalculer ce cadrage « à peu près » donnerait des vignettes qui ne se
    superposent pas aux anciennes : la plante changerait de taille d'une fiche
    à l'autre selon celle qui a été régénérée.
    """

    RAPPORT = 720 / 900

    def cadrer(self, largeur, hauteur, profondeur):
        return rendre.cadrer(largeur, hauteur, profondeur, self.RAPPORT)

    def test_le_cadrage_est_invariant_dechelle(self):
        """Doubler le sujet double la distance, et rien d'autre ne change.

        C'est la propriété qui autorise `normaliser_echelle` à exister : si le
        cadrage dépendait de l'échelle absolue, corriger un modèle en
        centimètres changerait aussi son cadrage.
        """
        petit = self.cadrer(1.0, 2.0, 1.5)
        grand = self.cadrer(2.0, 4.0, 3.0)
        for cle in ("distance", "camera_y", "camera_z", "vise_z"):
            self.assertAlmostEqual(grand[cle], 2 * petit[cle], places=6,
                                   msg=f"« {cle} » n'est pas proportionnel")

    def test_la_camera_vise_le_milieu_de_la_hauteur(self):
        cadre = self.cadrer(1.0, 2.0, 1.0)
        self.assertAlmostEqual(cadre["vise_z"], 1.0)

    def test_la_profondeur_eloigne_la_camera(self):
        """Une plante large et plate sort du cadre une fois la caméra inclinée.

        Le cadrage en tient compte, et c'est toute la raison pour laquelle
        `cadrer` prend trois dimensions et pas deux.
        """
        plate = self.cadrer(1.0, 1.0, 0.2)
        profonde = self.cadrer(1.0, 1.0, 2.0)
        self.assertGreater(profonde["distance"], plate["distance"])

    def test_un_sujet_plus_large_eloigne_la_camera(self):
        etroit = self.cadrer(0.5, 1.0, 0.5)
        large = self.cadrer(3.0, 1.0, 0.5)
        self.assertGreater(large["distance"], etroit["distance"])

    def test_la_camera_est_posee_selon_linclinaison(self):
        """`camera_y` et `camera_z` décomposent la distance sur l'inclinaison."""
        cadre = self.cadrer(1.0, 2.0, 1.0)
        inclinaison = math.radians(rendre.INCLINAISON)
        self.assertAlmostEqual(
            cadre["camera_y"], cadre["distance"] * math.cos(inclinaison))
        self.assertAlmostEqual(
            cadre["camera_z"],
            cadre["vise_z"] + cadre["distance"] * math.sin(inclinaison))

    def test_des_dimensions_nulles_ne_divisent_jamais_par_zero(self):
        """Un maillage dégénéré ne doit pas faire exploser le rendu."""
        cadre = self.cadrer(0.0, 0.0, 0.0)
        self.assertGreater(cadre["distance"], 0.0)
        self.assertTrue(math.isfinite(cadre["distance"]))

    def test_les_constantes_de_cadrage_sont_celles_du_moteur_ios(self):
        self.assertAlmostEqual(rendre.CHAMP_VERTICAL, 35.0)
        self.assertAlmostEqual(rendre.REMPLISSAGE, 0.70)
        self.assertAlmostEqual(rendre.INCLINAISON, 8.0)


# --- Normalisation d'échelle (#718) ---------------------------------------

class NormalisationDEchelle(unittest.TestCase):
    """La correction de #718 : deux modèles du catalogue sont en centimètres.

    Le décor a des constantes ABSOLUES — plan rapproché à 1e-4, pelouse à
    -0,001 — qui supposent un sujet de l'ordre du mètre. À 153 unités, le pas
    du tampon de profondeur dépasse la hauteur du pot, et le sol l'emporte.
    """

    def normaliser(self, etendue_x, etendue_y, etendue_z):
        sujet = _Objet([])
        maillage = _Objet(_pave(0, 0, 0, etendue_x, etendue_y, etendue_z))
        facteur = rendre.normaliser_echelle(sujet, [maillage])
        return facteur, sujet

    def test_un_sujet_dans_la_bande_nest_PAS_transforme(self):
        """La propriété qui compte : les 121 modèles sains ne bougent pas.

        C'est elle qui a permis de livrer #723 sans rejouer les 123 vignettes
        — vérifié par ailleurs au pixel près sur Alocasia Zebrina.
        """
        for etendue in (0.1, 0.83, 1.5, 2.0, 10.0):
            with self.subTest(etendue=etendue):
                facteur, sujet = self.normaliser(etendue, etendue / 2, etendue / 3)
                self.assertEqual(facteur, 1.0)
                self.assertEqual(sujet.scale, (1.0, 1.0, 1.0),
                                 "aucune transformation ne doit être posée")

    def test_un_modele_en_centimetres_est_ramene_a_lechelle_de_reference(self):
        """Cactus mesure 122,43 unités, Livistona 152,89."""
        for etendue in (122.4279, 152.8894):
            with self.subTest(etendue=etendue):
                facteur, sujet = self.normaliser(etendue, etendue, etendue)
                self.assertAlmostEqual(
                    facteur, rendre.HAUTEUR_DE_REFERENCE / etendue, places=9)
                self.assertAlmostEqual(etendue * facteur,
                                       rendre.HAUTEUR_DE_REFERENCE, places=6)
                self.assertEqual(sujet.scale, (facteur, facteur, facteur))

    def test_le_facteur_suit_la_plus_GRANDE_etendue(self):
        """Livistona est plus large que haute : 160,1 contre 152,9.

        Suivre la hauteur laisserait le sujet déborder du cadre dans l'autre
        sens.
        """
        facteur, _ = self.normaliser(160.1076, 145.4689, 152.8894)
        self.assertAlmostEqual(
            facteur, rendre.HAUTEUR_DE_REFERENCE / 160.1076, places=9)

    def test_un_sujet_minuscule_est_agrandi(self):
        """La bande a deux bords. Un modèle en millimètres poserait le
        problème symétrique, et l'indétermination de l'échelle ne doit pas
        dépendre du sens."""
        facteur, sujet = self.normaliser(0.01, 0.01, 0.01)
        self.assertGreater(facteur, 1.0)
        self.assertAlmostEqual(0.01 * facteur, rendre.HAUTEUR_DE_REFERENCE)

    def test_un_sujet_sans_etendue_est_laisse_tel_quel(self):
        """Étendue nulle : aucune échelle n'a de sens, et diviser lèverait."""
        facteur, sujet = self.normaliser(0.0, 0.0, 0.0)
        self.assertEqual(facteur, 1.0)
        self.assertEqual(sujet.scale, (1.0, 1.0, 1.0))

    def test_les_bornes_de_la_bande_sont_inclusives(self):
        """Exactement 10,0 est DANS la bande, 10,1 n'y est plus."""
        self.assertEqual(self.normaliser(rendre.ECHELLE_MAX, 1, 1)[0], 1.0)
        self.assertNotEqual(self.normaliser(rendre.ECHELLE_MAX + 0.1, 1, 1)[0], 1.0)
        self.assertEqual(self.normaliser(rendre.ECHELLE_MIN, 0.01, 0.01)[0], 1.0)

    def test_la_hauteur_de_reference_est_plausible_pour_une_plante(self):
        """1,5 unité : dans la bande, et de l'ordre d'une plante réelle."""
        self.assertTrue(
            rendre.ECHELLE_MIN <= rendre.HAUTEUR_DE_REFERENCE <= rendre.ECHELLE_MAX)


# --- Boîte englobante -----------------------------------------------------

class BoiteEnglobante(unittest.TestCase):

    def test_la_boite_couvre_tous_les_maillages(self):
        a = _Objet(_pave(-1, -1, 0, 0, 0, 1))
        b = _Objet(_pave(0, 0, 0, 2, 3, 4))
        bas, haut = rendre.boite([a, b])
        self.assertEqual((bas.x, bas.y, bas.z), (-1.0, -1.0, 0.0))
        self.assertEqual((haut.x, haut.y, haut.z), (2.0, 3.0, 4.0))


# --- Arguments ------------------------------------------------------------

class ArgumentsApresDoubleTiret(unittest.TestCase):
    """Blender consomme ses propres options ; les nôtres suivent un `--`."""

    def test_les_arguments_apres_le_double_tiret_sont_rendus(self):
        precedent = sys.argv
        try:
            sys.argv = ["blender", "--background", "--", "--modele", "a.usdz"]
            self.assertEqual(rendre.argv_apres_double_tiret(),
                             ["--modele", "a.usdz"])
        finally:
            sys.argv = precedent

    def test_sans_double_tiret_aucun_argument_nest_rendu(self):
        """Et surtout : on ne récupère PAS ceux de Blender."""
        precedent = sys.argv
        try:
            sys.argv = ["blender", "--background", "--python", "rendre.py"]
            self.assertEqual(rendre.argv_apres_double_tiret(), [])
        finally:
            sys.argv = precedent


# --- Relais des mesures ---------------------------------------------------

class RelaisDesMesures(unittest.TestCase):
    """`publier.py` relève les lignes préfixées par `MARQUE_TEMPS`.

    Le préfixe est un contrat entre les deux fichiers : s'il change d'un côté,
    les mesures disparaissent des journaux sans que rien n'échoue.
    """

    def test_le_prefixe_est_celui_que_publier_releve(self):
        publier = (pathlib.Path(__file__).resolve().parents[1]
                   / "vignettes" / "publier.py").read_text(encoding="utf-8")
        self.assertIn(repr(rendre.MARQUE_TEMPS).strip("'"), publier,
                      "`publier.py` ne relèverait plus les mesures de phase")


if __name__ == "__main__":
    unittest.main()
