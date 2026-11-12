#!/usr/bin/env python3
"""Tests de scripts/appliquer-traductions.py. (#809)

Un seul sujet : **ce que le contrôle refuse de poser en base**, et pourquoi
chaque refus existe. Une traduction est écrite à la main ; elle dérive, et la
dérive ne se voit pas à la relecture d'un JSON de six mille caractères.

  python3 -m unittest discover -s scripts -p 'test_*.py'
"""
import copy
import importlib.util
import pathlib
import unittest

_chemin = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "appliquer-traductions.py"
_spec = importlib.util.spec_from_file_location("appliquer_traductions", _chemin)
trad = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(trad)

EN = {
    "description": "A description.",
    "plantType": "Houseplant",
    "sun": {"lightType": "bright", "durationPerDay": "6 h",
            "orientation": "south", "windowDistance": "1 m",
            "recommendedRooms": ["Living room"], "tips": ["Turn it", "Dust it"]},
    "water": {"frequency": "weekly", "amount": "200 ml", "method": "top",
              "humidity": "50%", "signsLack": "droop", "signsExcess": "yellow",
              "recommendedWater": "rain"},
    "soilAndPot": {"substrate": "peat", "drainage": "clay", "potSize": "20 cm",
                   "repotFrequency": "2 y", "repotSigns": "roots"},
    "health": {"commonProblems": ["Rot"], "symptomsAndCauses": ["Soft stem."],
               "pests": ["Scale"], "treatments": ["Repot."],
               "prevention": ["Drain well."]},
    "lifeCycle": {"growth": "spring", "flowering": "none", "dormancy": "winter",
                  "fertilizer": "monthly", "pruning": "rarely"},
    "care": {"weekly": ["Check soil"], "monthly": ["Feed"], "yearly": ["Repot"],
             "extraTips": ["Keep warm"]},
}

FR = {
    "description": "Une description française.",
    "plantType": "Plante d’intérieur",
    "sun": {"lightType": "vive", "durationPerDay": "6 h",
            "orientation": "sud", "windowDistance": "1 m",
            "recommendedRooms": ["Salon"], "tips": ["Tournez-la", "Dépoussiérez"]},
    "water": {"frequency": "hebdomadaire", "amount": "200 ml", "method": "dessus",
              "humidity": "50 %", "signsLack": "affaissement",
              "signsExcess": "jaunissement", "recommendedWater": "pluie"},
    "soilAndPot": {"substrate": "tourbe", "drainage": "billes", "potSize": "20 cm",
                   "repotFrequency": "2 ans", "repotSigns": "racines"},
    "health": {"commonProblems": ["Pourriture"],
               "symptomsAndCauses": ["Tige molle."], "pests": ["Cochenille"],
               "treatments": ["Rempotez."], "prevention": ["Drainez bien."]},
    "lifeCycle": {"growth": "printemps", "flowering": "aucune",
                  "dormancy": "hiver", "fertilizer": "mensuel",
                  "pruning": "rarement"},
    "care": {"weekly": ["Touchez la terre"], "monthly": ["Fertilisez"],
             "yearly": ["Rempotez"], "extraTips": ["Gardez au chaud"]},
}


def jeu(**remplace):
    """Une fiche et ses trois traductions conformes, qu'un test dégrade."""
    redac = {"_meta": {"difficulty": "easy"}, "translations": {"en": copy.deepcopy(EN)}}
    t = {lg: copy.deepcopy(FR) for lg in ("fr", "es", "de")}
    fr_source = {"P": {"description": FR["description"]}}
    d = {"redac": redac, "trad": t, "fr_source": fr_source}
    d.update(remplace)
    return d


def motifs(j):
    return trad.controler("P", j["redac"], j["trad"], j["fr_source"])


class CeQuiPasse(unittest.TestCase):

    def test_trois_traductions_conformes_passent(self):
        self.assertEqual(motifs(jeu()), [])

    def test_le_texte_n_est_pas_juge(self):
        """Le contrôle est structurel : il ne relit pas la langue.

        C'est voulu. Un contrôle qui prétendrait juger une traduction donnerait
        une fausse assurance ; celui-ci répond d'une seule chose, la forme.
        """
        j = jeu()
        j["trad"]["es"]["plantType"] = "n'importe quoi"
        self.assertEqual(motifs(j), [])


class CeQuiCasseLeDecodage(unittest.TestCase):
    """Panne du 2026-11-11 : une fiche mal typée casse TOUT le catalogue.

    `cursor.All` décode le curseur entier. Une chaîne là où Go attend
    `[]string` a rendu les 249 fiches de `arbore_dev` inservables d'un coup, et
    arrêté le rendu des vignettes qui lit ce catalogue.
    """

    def test_une_chaine_au_lieu_d_une_liste_est_refusee(self):
        j = jeu()
        j["trad"]["fr"]["health"]["treatments"] = "Rempotez."
        m = motifs(j)
        self.assertTrue(any("fr.health.treatments" in x and "liste" in x for x in m), m)

    def test_une_liste_au_lieu_d_une_chaine_est_refusee(self):
        j = jeu()
        j["trad"]["de"]["water"]["frequency"] = ["wöchentlich"]
        self.assertTrue(any("de.water.frequency" in x and "chaîne" in x
                            for x in motifs(j)))

    def test_un_element_de_liste_non_chaine_est_refuse(self):
        j = jeu()
        j["trad"]["es"]["care"]["weekly"] = [{"texte": "Riegue"}]
        self.assertTrue(any("es.care.weekly[0]" in x for x in motifs(j)))


class CeQuiCasseLAffichage(unittest.TestCase):

    def test_une_liste_qui_perd_des_elements_est_refusee(self):
        """Fusionner deux puces en une ne casse pas Go, mais casse l'écran."""
        j = jeu()
        j["trad"]["fr"]["sun"]["tips"] = ["Tournez-la et dépoussiérez-la"]
        self.assertTrue(any("fr.sun.tips" in x and "1 éléments au lieu de 2" in x
                            for x in motifs(j)))

    def test_un_champ_manquant_est_refuse(self):
        j = jeu()
        del j["trad"]["de"]["lifeCycle"]["pruning"]
        self.assertIn("de.lifeCycle.pruning manquant", motifs(j))

    def test_un_champ_invente_est_refuse(self):
        """Go l'ignorerait, mais c'est le signe d'une traduction qui improvise."""
        j = jeu()
        j["trad"]["es"]["sun"]["extra"] = "algo"
        self.assertIn("es.sun.extra en trop", motifs(j))

    def test_une_langue_entiere_absente_est_refusee(self):
        j = jeu()
        del j["trad"]["de"]
        self.assertIn("de absent", motifs(j))

    def test_le_tiret_cadratin_est_refuse(self):
        """Le reste du catalogue emploie le demi-cadratin ; le mélange se voit."""
        j = jeu()
        j["trad"]["fr"]["water"]["amount"] = "200—300 ml"
        self.assertTrue(any("tiret cadratin" in x for x in motifs(j)))

    def test_le_point_decimal_anglais_est_refuse(self):
        """Relevé : `fr` et `de` des 123 fiches servies n'en portent aucun.

        Deux agents de rédaction avaient tranché dans deux sens opposés —
        l'un convertissait en virgule, l'autre gardait le point. C'est ce
        désaccord silencieux que le contrôle existe pour arrêter.
        """
        for lg in ("fr", "es", "de"):
            with self.subTest(langue=lg):
                j = jeu()
                j["trad"][lg]["soilAndPot"]["substrate"] = "tourbe à pH 6.0"
                self.assertTrue(any(f"{lg} garde un point décimal" in x
                                    for x in motifs(j)))

    def test_la_virgule_decimale_passe(self):
        j = jeu()
        j["trad"]["fr"]["soilAndPot"]["substrate"] = "tourbe à pH 6,0 à 6,5"
        self.assertEqual(motifs(j), [])

    def test_un_entier_ou_une_plage_ne_declenche_rien(self):
        """Le motif exige un chiffre de part et d'autre du point."""
        j = jeu()
        j["trad"]["fr"]["water"]["amount"] = "200 ml, 20–30 cm, 18 °C. Puis."
        self.assertEqual(motifs(j), [])


class LaDescriptionFrancaiseNeSeTraduitPas(unittest.TestCase):
    """Sur les 123 fiches déjà traduites, `description` à la racine EST
    `translations.fr.description`. Traduire l'anglais donnerait deux textes
    français différents pour la même plante.
    """

    def test_une_fr_description_retraduite_est_refusee(self):
        j = jeu()
        j["trad"]["fr"]["description"] = "Une autre description française."
        self.assertIn("fr.description n'est pas la description servie à la racine",
                      motifs(j))

    def test_es_et_de_ne_sont_pas_contraintes_a_l_identique(self):
        """Elles la traduisent, donc elles diffèrent : c'est attendu."""
        j = jeu()
        j["trad"]["es"]["description"] = "Una descripción en español."
        j["trad"]["de"]["description"] = "Eine Beschreibung auf Deutsch."
        self.assertEqual(motifs(j), [])


class LaDifficulteEstPoseeIci(unittest.TestCase):
    """#485 : un `difficulty` absent ne neutralise pas le filtre du catalogue,
    il le VIDE — un critère absent n'excluait pas « rien », il excluait TOUT.
    """

    def test_les_quatre_langues_recoivent_leur_valeur(self):
        j = jeu()
        op = trad.operation("P", j["redac"], j["trad"])
        self.assertEqual(op["set"]["translations.en.care.difficulty"], "Easy")
        self.assertEqual(op["set"]["translations.fr"]["care"]["difficulty"], "Facile")
        self.assertEqual(op["set"]["translations.es"]["care"]["difficulty"], "Fácil")
        self.assertEqual(op["set"]["translations.de"]["care"]["difficulty"], "Einfach")

    def test_chaque_niveau_a_ses_quatre_valeurs(self):
        for niveau in ("easy", "medium", "hard"):
            with self.subTest(niveau=niveau):
                self.assertEqual(set(trad.DIFFICULTE[niveau]), {"en", "fr", "es", "de"})

    def test_une_difficulte_inconnue_fait_refuser(self):
        j = jeu()
        j["redac"]["_meta"]["difficulty"] = "très dur"
        self.assertTrue(any("_meta.difficulty" in x for x in motifs(j)))

    def test_une_difficulte_inventee_par_l_agent_est_ecrasee(self):
        """L'agent n'a pas à l'écrire ; s'il le fait, la valeur close gagne."""
        j = jeu()
        j["trad"]["fr"]["care"]["difficulty"] = "Très facile"
        self.assertEqual(motifs(j), [], "sa présence ne doit pas faire refuser")
        op = trad.operation("P", j["redac"], j["trad"])
        self.assertEqual(op["set"]["translations.fr"]["care"]["difficulty"], "Facile")


class LOperationViseLaBonneFiche(unittest.TestCase):

    def test_la_cible_est_le_modelurl(self):
        """Seule valeur que l'atelier, le disque et le catalogue partagent."""
        op = trad.operation("P", jeu()["redac"], jeu()["trad"])
        self.assertEqual(op["modelURL"], "P_potless.usdz")

    def test_les_trois_langues_sont_posees_en_une_operation(self):
        op = trad.operation("P", jeu()["redac"], jeu()["trad"])
        for lg in ("fr", "es", "de"):
            self.assertIn(f"translations.{lg}", op["set"])
        self.assertNotIn("translations.en", op["set"],
                         "l'anglais existe déjà : seul son difficulty manque")


if __name__ == "__main__":
    unittest.main()
