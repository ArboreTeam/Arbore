#!/usr/bin/env python3
"""Tests de poser-pots-sur-plantes.py. (#609, #623)

Le risque de ce script n'est pas de planter : c'est de poser un socle **faux**
sur une plante. Un socle manquant se voit — la plante sort nue. Un socle qui
vient de la mauvaise relance, ou d'une autre coupe que celle retenue par
l'opérateur, donne un pot décalé que personne ne reliera à ce script.

Ces tests portent donc sur l'appariement et sur les refus.

  python3 -m unittest discover -s scripts -p 'test_*.py'
"""
import importlib.util
import pathlib
import unittest

_chemin = pathlib.Path(__file__).with_name("poser-pots-sur-plantes.py")
_spec = importlib.util.spec_from_file_location("poser_pots", _chemin)
poser = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(poser)


def socle(rayon=0.16146, **extra):
    s = {"x": 0.00432, "y": -0.10521, "z": -0.07449, "rayon": rayon}
    s.update(extra)
    return s


def tache(plante, coupe, socle_, pris=1000):
    return {
        "plante": plante,
        "pris": pris,
        "resultat": {"candidats_pot": [
            {"fichier": f"/content/recoupe/{plante}/{coupe}", "socle": socle_}
        ]},
    }


class AppariementDeLaCoupe(unittest.TestCase):
    def test_retient_le_candidat_choisi_par_loperateur(self):
        taches = [
            tache("P", "sanspot_couleur.glb", socle(rayon=0.9)),
            tache("P", "sanspot_geometrie.glb", socle(rayon=0.1)),
        ]
        got = poser.socle_de_la_coupe(taches, "P", "sanspot_geometrie.glb")
        self.assertEqual(got["rayon"], 0.1)

    def test_entre_deux_relances_la_plus_recente(self):
        taches = [
            tache("P", "sanspot_geometrie.glb", socle(rayon=0.1), pris=10),
            tache("P", "sanspot_geometrie.glb", socle(rayon=0.2), pris=99),
        ]
        got = poser.socle_de_la_coupe(taches, "P", "sanspot_geometrie.glb")
        self.assertEqual(got["rayon"], 0.2, "une relance remplace le maillage sur le disque")

    def test_ne_prend_pas_le_socle_dune_autre_plante(self):
        taches = [tache("AUTRE", "sanspot_geometrie.glb", socle())]
        self.assertIsNone(poser.socle_de_la_coupe(taches, "P", "sanspot_geometrie.glb"))

    def test_coupe_absente_des_candidats(self):
        taches = [tache("P", "sanspot_couleur.glb", socle())]
        self.assertIsNone(poser.socle_de_la_coupe(taches, "P", "sanspot_geometrie.glb"))

    def test_resultat_absent_ou_malforme(self):
        for resultat in (None, "livree", {}, {"candidats_pot": None}):
            with self.subTest(resultat=resultat):
                taches = [{"plante": "P", "resultat": resultat}]
                self.assertIsNone(poser.socle_de_la_coupe(taches, "P", "c.glb"))

    def test_candidat_sans_socle(self):
        taches = [{"plante": "P", "resultat": {"candidats_pot": [
            {"fichier": "/x/c.glb"}]}}]
        self.assertIsNone(poser.socle_de_la_coupe(taches, "P", "c.glb"))


class ConversionDuSocle(unittest.TestCase):
    def test_renomme_vers_les_noms_de_lapi(self):
        got = poser.convertir_socle(socle(y_terre=-0.19691, hauteur_vegetal=0.64856))
        self.assertEqual(got, {"x": 0.00432, "y": -0.10521, "z": -0.07449,
                               "radius": 0.16146, "groundY": -0.19691,
                               "plantHeight": 0.64856})

    def test_les_champs_absents_sont_omis_et_non_mis_a_zero(self):
        got = poser.convertir_socle(socle())
        self.assertNotIn("groundY", got, "un zéro se confondrait avec une mesure")
        self.assertNotIn("plantHeight", got)

    def test_ignore_les_valeurs_non_numeriques(self):
        got = poser.convertir_socle({"rayon": "0.1", "x": None, "y": 2})
        self.assertEqual(got, {"y": 2.0})


class Operations(unittest.TestCase):
    def etat(self, **plantes):
        taches = []
        for nom, p in plantes.items():
            if p.get("_socle") is not None:
                taches.append(tache(nom, p.get("coupe", ""), p["_socle"]))
        return {
            "plantes": {n: {k: v for k, v in p.items() if not k.startswith("_")}
                        for n, p in plantes.items()},
            "taches": taches,
            "pots": {"cachepot_pieds.glb": {"rayon": 0.058654, "hauteur": 0.1}},
        }

    def test_une_plante_validee_avec_socle(self):
        e = self.etat(P={"verdict": "validee", "coupe": "c.glb", "_socle": socle()})
        ops = poser.operations(e)
        self.assertEqual(len(ops["plantes"]), 1)
        self.assertTrue(ops["plantes"][0]["set"]["potless"])
        self.assertAlmostEqual(ops["plantes"][0]["set"]["potBase"]["radius"], 0.16146)

    # Le filtre vise le modèle actuel, la mise à jour pointe sur le recoupé.
    # Les confondre écraserait le modèle en service (#294 : le cache iOS est
    # indexé par nom de fichier, un même nom n'atteindrait aucun téléphone).
    def test_le_modele_recoupe_ne_remplace_pas_lancien(self):
        e = self.etat(P={"verdict": "validee", "coupe": "c.glb", "_socle": socle()})
        op = poser.operations(e)["plantes"][0]
        self.assertEqual(op["modelURL"], "P.usdz", "le filtre vise le modèle actuel")
        self.assertEqual(op["set"]["modelURL"], "P_potless.usdz")
        self.assertNotEqual(op["modelURL"], op["set"]["modelURL"],
                            "un même nom écraserait le fichier servi")

    # Les plantes qu'on ne bascule pas ne doivent porter AUCUNE opération : leur
    # modèle actuel, pot compris, reste préférable à un modèle nu sans socle.
    def test_les_non_posables_gardent_leur_modele(self):
        e = self.etat(
            Bonne={"verdict": "validee", "coupe": "c.glb", "_socle": socle()},
            SansSocle={"verdict": "validee", "coupe": "c.glb", "_socle": None},
        )
        ops = poser.operations(e)
        vises = {o["modelURL"] for o in ops["plantes"]}
        self.assertEqual(vises, {"Bonne.usdz"})
        self.assertIn("SansSocle", ops["sans_socle"])

    def test_une_plante_non_validee_est_ignoree(self):
        for verdict in ("invalidee", "ecartee", None):
            with self.subTest(verdict=verdict):
                e = self.etat(P={"verdict": verdict, "coupe": "c.glb", "_socle": socle()})
                self.assertEqual(poser.operations(e)["plantes"], [])

    def test_validee_sans_coupe_est_signalee_et_non_posee(self):
        e = self.etat(P={"verdict": "validee", "_socle": None})
        ops = poser.operations(e)
        self.assertEqual(ops["plantes"], [])
        self.assertEqual(ops["sans_coupe"], ["P"])

    def test_coupe_sans_socle_est_signalee_et_non_posee(self):
        e = self.etat(P={"verdict": "validee", "coupe": "c.glb", "_socle": None})
        ops = poser.operations(e)
        self.assertEqual(ops["plantes"], [])
        self.assertEqual(ops["sans_socle"], ["P"])

    # Un rayon nul rendrait l'échelle du pot infinie ; le backend refuse déjà de
    # servir un pot dans ce cas, le script refuse de poser le socle.
    def test_rayon_nul_ou_negatif_refuse(self):
        for rayon in (0, -0.1):
            with self.subTest(rayon=rayon):
                e = self.etat(P={"verdict": "validee", "coupe": "c.glb",
                                 "_socle": socle(rayon=rayon)})
                ops = poser.operations(e)
                self.assertEqual(ops["plantes"], [])
                self.assertEqual(ops["sans_socle"], ["P"])

    def test_bibliotheque_de_pots_et_un_seul_defaut(self):
        ops = poser.operations(self.etat(P={"verdict": "validee", "coupe": "c.glb",
                                            "_socle": socle()}))
        self.assertEqual(len(ops["pots"]), 1)
        self.assertEqual(ops["pots"][0]["name"], "cachepot_pieds")
        self.assertAlmostEqual(ops["pots"][0]["rimRadius"], 0.058654)
        self.assertEqual(sum(1 for p in ops["pots"] if p["default"]), 1)

    def test_etat_vide(self):
        ops = poser.operations({})
        self.assertEqual(ops, {"plantes": [], "pots": [], "sans_socle": [], "sans_coupe": []})


if __name__ == "__main__":
    unittest.main()
