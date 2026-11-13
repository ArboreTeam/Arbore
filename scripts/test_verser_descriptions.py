#!/usr/bin/env python3
"""Tests de scripts/verser-descriptions.py. (#809)

Un seul sujet : **ce qu'on refuse de poser comme description**, et pourquoi.
Chaque refus vient d'un défaut trouvé sur une vraie fiche du catalogue.

  python3 -m unittest discover -s scripts -p 'test_*.py'
"""
import importlib.util
import json
import pathlib
import tempfile
import unittest

_chemin = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "verser-descriptions.py"
_spec = importlib.util.spec_from_file_location("verser_descriptions", _chemin)
vd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(vd)

FR = ("Le fusain 'Emerald Gaiety' est un arbuste persistant au feuillage vert "
      "bordé de blanc, qui rosit sous le froid. Il forme un buisson de 0,9 à "
      "1,8 m, et s'utilise en bordure comme en couvre-sol.")
ES = ("El evónimo 'Emerald Gaiety' es un arbusto perenne de follaje verde "
      "ribeteado de blanco, que se tiñe de rosa con el frío. Forma una mata de "
      "0,9 a 1,8 m y se usa en borduras y como cubresuelos.")
DE = ("Die Kriechspindel 'Emerald Gaiety' ist ein immergrüner Strauch mit grün "
      "weiß gerandetem Laub, das sich bei Kälte rosa färbt. Sie bildet einen "
      "Busch von 0,9 bis 1,8 m und eignet sich für Beeteinfassungen.")


def bloc(**remplace):
    d = {"fr": FR, "es": ES, "de": DE}
    d.update(remplace)
    return d


class CeQuiPasse(unittest.TestCase):

    def test_trois_langues_correctes_passent(self):
        self.assertEqual(vd.ecarts("Fusain", bloc()), [])

    def test_l_operation_ecrit_les_QUATRE_champs(self):
        """La racine ET les trois langues, sinon deux textes français
        concurrents cohabitent pour la même plante.
        """
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            (d / "Fusain.json").write_text(json.dumps(bloc()), encoding="utf-8")
            ops, refus, _ = vd.operations(d, None)
            self.assertEqual(refus, [])
            s = ops[0]["set"]
            self.assertEqual(ops[0]["modelURL"], "Fusain_potless.usdz")
            self.assertEqual(s["description"], s["translations.fr.description"])
            for lg in ("fr", "es", "de"):
                self.assertIn(f"translations.{lg}.description", s)


class CeQuiEstRefuse(unittest.TestCase):

    def test_une_langue_manquante_est_refusee(self):
        for lg in ("fr", "es", "de"):
            with self.subTest(langue=lg):
                b = bloc(); del b[lg]
                self.assertIn(f"{lg} absent ou vide", vd.ecarts("X", b))

    def test_une_langue_vide_est_refusee(self):
        self.assertIn("es absent ou vide", vd.ecarts("X", bloc(es="   ")))

    def test_une_description_tronquee_est_refusee(self):
        """Le défaut réel du thym serpolet : « Egalement utilisé en tisa »."""
        b = bloc(fr=FR[:-20])
        self.assertTrue(any("ponctuation" in m for m in vd.ecarts("X", b)))

    def test_le_point_decimal_anglais_est_refuse(self):
        b = bloc(fr=FR.replace("0,9 à 1,8", "0.9 à 1.8"))
        self.assertTrue(any("point décimal" in m for m in vd.ecarts("X", b)))

    def test_le_tiret_cadratin_est_refuse(self):
        b = bloc(de=DE.replace("Laub,", "Laub—"))
        self.assertTrue(any("cadratin" in m for m in vd.ecarts("X", b)))

    def test_une_description_trop_courte_est_refusee(self):
        b = bloc(fr="Un arbuste.")
        self.assertTrue(any("trop court" in m for m in vd.ecarts("X", b)))

    def test_une_fiche_entiere_collee_est_refusee(self):
        b = bloc(fr=FR * 10)
        self.assertTrue(any("trop long" in m for m in vd.ecarts("X", b)))

    def test_une_traduction_non_traduite_est_refusee(self):
        """Recopier le français en espagnol est l'oubli le plus probable."""
        self.assertIn("une traduction est identique au français",
                      vd.ecarts("X", bloc(es=FR)))

    def test_une_fiche_recalee_n_emporte_pas_le_lot(self):
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            (d / "Bonne.json").write_text(json.dumps(bloc()), encoding="utf-8")
            (d / "Creuse.json").write_text(json.dumps(bloc(de="")), encoding="utf-8")
            ops, refus, _ = vd.operations(d, None)
            self.assertEqual([o["modelURL"] for o in ops], ["Bonne_potless.usdz"])
            self.assertEqual(len(refus), 1)


class LaSelection(unittest.TestCase):
    """`--seulement` sert à poser d'abord les corrections urgentes, sans
    emporter les descriptions écrites pour des fiches pas encore insérées.
    """

    def test_seules_les_cles_demandees_sortent(self):
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            for cle in ("A", "B"):
                (d / f"{cle}.json").write_text(json.dumps(bloc()), encoding="utf-8")
            ops, _, hors = vd.operations(d, {"A"})
            self.assertEqual([o["modelURL"] for o in ops], ["A_potless.usdz"])
            self.assertEqual(hors, ["B"])

    def test_les_fichiers_techniques_sont_ignores(self):
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            (d / "_index.json").write_text("{}", encoding="utf-8")
            self.assertEqual(vd.operations(d, None), ([], [], []))


if __name__ == "__main__":
    unittest.main()
