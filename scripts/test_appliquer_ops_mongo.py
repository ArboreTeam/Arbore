#!/usr/bin/env python3
"""Tests de scripts/appliquer-ops-mongo.py, section `nouvelles`. (#809)

Un seul sujet : **ce que le tri refuse d'insérer**, et pourquoi chaque refus
existe. Ce script écrit dans le catalogue servi ; une fiche créée à tort y
reste, sans vignette et sans historique, et se remarque par un trou dans
l'application plutôt que par une erreur.

Les tests portent sur `trier_nouvelles`, la fonction qui décide. Elle est pure
et ne touche pas la base : la collection est remplacée par un double qui
répond aux `find_one`, ce qui permet d'éprouver les refus sans Mongo.

  python3 -m unittest discover -s scripts -p 'test_*.py'
"""
import importlib.util
import pathlib
import tempfile
import unittest

_chemin = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "appliquer-ops-mongo.py"
_spec = importlib.util.spec_from_file_location("appliquer_ops_mongo", _chemin)
appliquer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(appliquer)


class FausseCollection:
    """Répond aux `find_one({"modelURL": ...})` sur un jeu d'URL connues."""

    def __init__(self, urls=()):
        self.urls = set(urls)

    def find_one(self, filtre, projection=None):
        return {"_id": "x"} if filtre.get("modelURL") in self.urls else None


def fiche(url="Plante_potless.usdz", **extra):
    """Une fiche complète, à laquelle chaque test retire ce qu'il éprouve."""
    d = {
        "name": "Plante",
        "type": "Plantes d’intérieur",
        "description": "Une description française.",
        "modelURL": url,
        "translations": {"en": {"description": "A description."}},
        "botanicalProfile": {"size": {"value": "small"}},
    }
    d.update(extra)
    return d


class CeQuiEstInsere(unittest.TestCase):

    def test_une_fiche_complete_et_inedite_passe(self):
        a, deja, refus = appliquer.trier_nouvelles(FausseCollection(), [fiche()], None)
        self.assertEqual(len(a), 1)
        self.assertEqual((deja, refus), ([], []))

    def test_imageurls_n_est_pas_exige(self):
        """Il se remplit APRÈS l'insertion : l'URL porte l'identifiant Mongo.

        L'exiger en entrée rendrait la section inutilisable, puisque personne
        ne peut le connaître avant l'écriture.
        """
        self.assertNotIn("imageURLs", appliquer.CHAMPS_REQUIS)
        a, _, refus = appliquer.trier_nouvelles(FausseCollection(), [fiche()], None)
        self.assertEqual(refus, [])
        self.assertEqual(len(a), 1)


class CeQuiEstRefuse(unittest.TestCase):

    def test_une_fiche_deja_au_catalogue_n_est_pas_reinseree(self):
        """Insérer un doublon donnerait deux fiches pour une plante.

        La seconde n'aurait ni vignette ni historique, et rien ne dirait
        laquelle l'application sert.
        """
        col = FausseCollection(["Plante_potless.usdz"])
        a, deja, refus = appliquer.trier_nouvelles(col, [fiche()], None)
        self.assertEqual(a, [])
        self.assertEqual(deja, ["Plante_potless.usdz"])
        self.assertEqual(refus, [], "un doublon n'est pas une erreur, c'est un déjà-fait")

    def test_un_doublon_dans_le_meme_fichier_est_attrape(self):
        """La base ne peut pas le voir : les deux insertions viennent après."""
        a, _, refus = appliquer.trier_nouvelles(
            FausseCollection(), [fiche(), fiche()], None)
        self.assertEqual(len(a), 1)
        self.assertEqual(len(refus), 1)
        self.assertIn("deux fois", refus[0][1])

    def test_chaque_champ_requis_manquant_fait_refuser(self):
        for champ in appliquer.CHAMPS_REQUIS:
            with self.subTest(champ=champ):
                d = fiche()
                del d[champ]
                a, _, refus = appliquer.trier_nouvelles(FausseCollection(), [d], None)
                self.assertEqual(a, [], f"{champ} manquant aurait dû faire refuser")
                self.assertEqual(len(refus), 1)
                self.assertIn(champ, refus[0][1])

    def test_un_champ_vide_vaut_un_champ_absent(self):
        """Une description vide n'est pas une description."""
        a, _, refus = appliquer.trier_nouvelles(
            FausseCollection(), [fiche(description="")], None)
        self.assertEqual(a, [])
        self.assertIn("description", refus[0][1])

    def test_sans_modelurl_la_fiche_est_refusee_et_nommee(self):
        d = fiche()
        del d["modelURL"]
        a, _, refus = appliquer.trier_nouvelles(FausseCollection(), [d], None)
        self.assertEqual(a, [])
        self.assertEqual(len(refus), 1)

    def test_un_lot_mixte_laisse_passer_les_bonnes(self):
        """Une fiche recalée ne doit pas emporter le lot avec elle."""
        a, deja, refus = appliquer.trier_nouvelles(
            FausseCollection(["Deja_potless.usdz"]),
            [fiche("Bonne_potless.usdz"), fiche("Deja_potless.usdz"),
             fiche("Creuse_potless.usdz", description="")],
            None)
        self.assertEqual([d["modelURL"] for d in a], ["Bonne_potless.usdz"])
        self.assertEqual(deja, ["Deja_potless.usdz"])
        self.assertEqual(len(refus), 1)


class LaFormeDesTraductions(unittest.TestCase):
    """Le typage de `translations`, et pourquoi il est vérifié à l'écriture.

    Panne réelle du 2026-11-11 : 126 fiches insérées avec trois champs de
    `health` en chaînes là où `HealthInfo` les déclare en `[]string`.
    `GET /internal/plants` a rendu 500 pour les 249 fiches du catalogue, parce
    que `cursor.All` décode le curseur entier — une seule fiche mal typée suffit
    à rendre toutes les autres inservables, et à arrêter le rendu des vignettes
    qui lit ce catalogue.

    L'écart ne se voyait ni à la relecture du JSON, ni à l'insertion : il
    n'apparaissait qu'au prochain appel, dans un message qui ne nommait aucune
    fiche.
    """

    def langue(self, **remplace):
        """Un bloc de langue conforme, dont chaque test casse un seul champ."""
        bloc = {
            "description": "A description.",
            "health": {"commonProblems": [], "symptomsAndCauses": [],
                       "pests": [], "treatments": [], "prevention": []},
            "sun": {"lightType": "bright", "recommendedRooms": [], "tips": []},
        }
        bloc.update(remplace)
        return fiche(translations={"en": bloc})

    def test_une_fiche_conforme_ne_produit_aucun_ecart(self):
        self.assertEqual(appliquer.ecarts_de_forme(self.langue()), [])

    def test_les_trois_champs_de_health_sont_des_listes(self):
        """Exactement la panne du 2026-11-11, champ par champ."""
        for champ in ("commonProblems", "symptomsAndCauses", "pests",
                      "treatments", "prevention"):
            with self.subTest(champ=champ):
                d = self.langue()
                d["translations"]["en"]["health"][champ] = "une phrase en prose."
                ecarts = appliquer.ecarts_de_forme(d)
                self.assertEqual(len(ecarts), 1)
                self.assertIn(f"en.health.{champ}", ecarts[0])
                self.assertIn("attendu liste", ecarts[0])

    def test_une_liste_la_ou_une_chaine_est_attendue_est_vue_aussi(self):
        """L'inverse casse tout autant : le contrôle va dans les deux sens."""
        d = self.langue()
        d["translations"]["en"]["sun"]["lightType"] = ["bright"]
        ecarts = appliquer.ecarts_de_forme(d)
        self.assertEqual(len(ecarts), 1)
        self.assertIn("attendu chaîne", ecarts[0])

    def test_une_liste_d_objets_est_refusee(self):
        """`[]string` ne décode pas une liste de dictionnaires."""
        d = self.langue()
        d["translations"]["en"]["health"]["pests"] = [{"nom": "puceron"}]
        self.assertIn("non-chaîne", appliquer.ecarts_de_forme(d)[0])

    def test_un_champ_absent_n_est_pas_un_ecart(self):
        """Go lui donne sa valeur zéro : le décodage réussit, donc on laisse.

        Ce contrôle ne répond que de ce qui casse. L'étendre à la complétude en
        ferait un second schéma rédactionnel et écarterait des fiches
        parfaitement servables.
        """
        d = self.langue()
        del d["translations"]["en"]["health"]["treatments"]
        del d["translations"]["en"]["sun"]
        self.assertEqual(appliquer.ecarts_de_forme(d), [])

    def test_un_null_n_est_pas_un_ecart(self):
        d = self.langue()
        d["translations"]["en"]["health"]["treatments"] = None
        self.assertEqual(appliquer.ecarts_de_forme(d), [])

    def test_un_champ_en_trop_n_est_pas_un_ecart(self):
        """Go ignore ce qu'il ne déclare pas."""
        d = self.langue()
        d["translations"]["en"]["health"]["inconnu"] = 42
        self.assertEqual(appliquer.ecarts_de_forme(d), [])

    def test_toutes_les_langues_sont_controlees_pas_seulement_en(self):
        d = self.langue()
        d["translations"]["fr"] = {"health": {"prevention": "en prose."}}
        self.assertIn("fr.health.prevention", appliquer.ecarts_de_forme(d)[0])

    def test_une_fiche_mal_typee_est_refusee_et_non_inseree(self):
        """Le garde-fou doit agir sur `trier_nouvelles`, pas seulement exister."""
        d = self.langue()
        d["translations"]["en"]["health"]["prevention"] = "en prose."
        a, _, refus = appliquer.trier_nouvelles(FausseCollection(), [d], None)
        self.assertEqual(a, [], "une fiche mal typée ne doit jamais être insérée")
        self.assertEqual(len(refus), 1)
        self.assertIn("mal typée", refus[0][1])
        self.assertIn("en.health.prevention", refus[0][1])

    def test_une_fiche_mal_typee_n_emporte_pas_le_lot(self):
        bonne = self.langue()
        bonne["modelURL"] = "Bonne_potless.usdz"
        mauvaise = self.langue()
        mauvaise["modelURL"] = "Mauvaise_potless.usdz"
        mauvaise["translations"]["en"]["health"]["treatments"] = "en prose."
        a, _, refus = appliquer.trier_nouvelles(
            FausseCollection(), [bonne, mauvaise], None)
        self.assertEqual([x["modelURL"] for x in a], ["Bonne_potless.usdz"])
        self.assertEqual(len(refus), 1)


class LOrdreDeploiementPuisBase(unittest.TestCase):
    """`--modeles` fait respecter l'ordre : les USDZ d'abord, la base ensuite.

    Une fiche écrite avant son modèle pointe vers un 404, et l'application ne
    le dit pas : elle échoue à charger la plante au moment du placement AR.
    """

    def test_un_modele_absent_du_disque_fait_refuser(self):
        with tempfile.TemporaryDirectory() as d:
            a, _, refus = appliquer.trier_nouvelles(
                FausseCollection(), [fiche()], pathlib.Path(d))
            self.assertEqual(a, [])
            self.assertIn("modèle absent", refus[0][1])

    def test_un_modele_present_laisse_passer(self):
        with tempfile.TemporaryDirectory() as d:
            (pathlib.Path(d) / "Plante_potless.usdz").write_bytes(b"usdz")
            a, _, refus = appliquer.trier_nouvelles(
                FausseCollection(), [fiche()], pathlib.Path(d))
            self.assertEqual(len(a), 1)
            self.assertEqual(refus, [])

    def test_sans_modeles_le_controle_ne_s_applique_pas(self):
        """Le contrôle est opt-in : l'hôte qui écrit n'a pas toujours le disque."""
        a, _, refus = appliquer.trier_nouvelles(FausseCollection(), [fiche()], None)
        self.assertEqual(len(a), 1)
        self.assertEqual(refus, [])


if __name__ == "__main__":
    unittest.main()
