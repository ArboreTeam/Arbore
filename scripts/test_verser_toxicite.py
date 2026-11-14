#!/usr/bin/env python3
"""Tests de scripts/verser-toxicite.py. (#809)

Un seul sujet : **ce qui peut être affirmé sur la toxicité d'une plante, et
avec quoi pour le soutenir.** C'est l'affirmation la plus lourde du catalogue —
quelqu'un décide d'après elle s'il met la plante à portée de son chat.

  python3 -m unittest discover -s scripts -p 'test_*.py'
"""
import importlib.util
import json
import pathlib
import tempfile
import unittest

_chemin = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "verser-toxicite.py"
_spec = importlib.util.spec_from_file_location("verser_toxicite", _chemin)
vt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(vt)

ASPCA = ("ASPCA Toxic and Non-Toxic Plants, lists the species as non-toxic to "
         "dogs, cats and horses")
NCSTATE = "NC State Extension Gardener Plant Toolbox, poisonous, severity medium"
CULTURE = "RHS plant profile, gives the mature height at 2 to 3 m after ten years"


def tox(toxic, etabli, **extra):
    d = {"toxic": toxic, "toxicityEstablished": etabli,
         "toxicPrinciple": "Saponines.", "signs": "Irritation digestive."}
    d.update(extra)
    return d


class LeCroisementDesDeuxBooleens(unittest.TestCase):
    """`toxic` seul ne suffit pas : c'est `toxicityEstablished` qui distingue
    « une source affirme l'innocuité » de « personne n'a rien trouvé ».
    """

    def test_toxique_rend_toxic(self):
        f, motif = vt.fait(tox(True, True), NCSTATE, "2026-11-12", False)
        self.assertIsNone(motif)
        self.assertEqual(f["value"], "toxic")

    def test_non_toxique_et_etabli_rend_safe(self):
        f, _ = vt.fait(tox(False, True), ASPCA, "2026-11-12", False)
        self.assertEqual(f["value"], "safe")

    def test_non_etabli_rend_unknown_et_jamais_safe(self):
        """Le cœur de #778/#781 : 31 des 126 fiches sont dans ce cas."""
        f, motif = vt.fait(tox(False, False), ASPCA, "2026-11-12", False)
        self.assertIsNone(motif)
        self.assertEqual(f["value"], "unknown")
        self.assertNotEqual(f["value"], "safe")

    def test_toxique_non_etabli_reste_toxic(self):
        """Le drapeau se lève par prudence : on ne rétrograde pas en unknown."""
        f, _ = vt.fait(tox(True, False), NCSTATE, "2026-11-12", False)
        self.assertEqual(f["value"], "toxic")

    def test_tous_les_verdicts_sont_du_vocabulaire_ferme(self):
        for t in (True, False):
            for e in (True, False):
                with self.subTest(toxic=t, etabli=e):
                    self.assertIn(vt.verdict(tox(t, e)), vt.VERDICTS)


class SafeExigeUneSource(unittest.TestCase):
    """`safe` est une AFFIRMATION d'innocuité, pas une absence de preuve."""

    def test_safe_sans_source_de_toxicite_est_refuse(self):
        f, motif = vt.fait(tox(False, True), None, "2026-11-12", False)
        self.assertIsNone(f)
        self.assertIn("sans source", motif)

    def test_une_source_de_CULTURE_ne_soutient_pas_un_safe(self):
        """Une source de taille ou d'arrosage n'établit rien sur la toxicité."""
        self.assertIsNone(vt.source_toxicite([CULTURE]))
        f, motif = vt.fait(tox(False, True), vt.source_toxicite([CULTURE]),
                           "2026-11-12", False)
        self.assertIsNone(f, motif)

    def test_unknown_et_toxic_passent_sans_source(self):
        """Eux n'affirment pas l'innocuité : ils n'ont rien à soutenir."""
        for t, e, attendu in ((False, False, "unknown"), (True, False, "toxic")):
            with self.subTest(attendu=attendu):
                f, motif = vt.fait(tox(t, e), None, "2026-11-12", False)
                self.assertIsNone(motif)
                self.assertEqual(f["value"], attendu)
                self.assertNotIn("evidence", f)


class LaProseExigeUneSource(unittest.TestCase):
    """Le verdict et le détail ne se soutiennent pas de la même chose. (#841)

    Le verdict `toxic` est un fait : il peut être posé sans source, et le
    retirer faute de source rendrait le catalogue moins sûr. Le détail, lui,
    est une FORMULATION — `detail()` ne sait le composer que de
    `toxicPrinciple` et `signs`, deux champs calqués sur la présentation d'une
    base externe. La servir sans nommer d'où elle vient, c'est reprendre une
    rédaction au lieu de citer un fait.
    """

    def test_un_toxic_sans_source_garde_son_verdict(self):
        """Le garde ne retire pas d'avertissement."""
        f, motif = vt.fait(tox(True, False), None, "2026-11-12", False)
        self.assertIsNone(motif)
        self.assertEqual(f["value"], "toxic")

    def test_un_toxic_sans_source_part_sans_detail(self):
        f, _ = vt.fait(tox(True, False), None, "2026-11-12", False)
        self.assertNotIn("detail", f)

    def test_un_unknown_sans_source_part_sans_detail(self):
        f, _ = vt.fait(tox(False, False), None, "2026-11-12", False)
        self.assertEqual(f["value"], "unknown")
        self.assertNotIn("detail", f)

    def test_avec_une_source_le_detail_revient(self):
        """Le garde ne ferme que le cas non attribué."""
        f, _ = vt.fait(tox(True, False), NCSTATE, "2026-11-12", False)
        self.assertIn("detail", f)
        self.assertIn("Saponines", f["detail"])
        self.assertEqual(f["evidence"]["sourceName"], "NC State Extension Gardener Plant Toolbox")

    def test_une_source_de_culture_ne_fait_pas_passer_la_prose(self):
        """`source_toxicite` l'écarte en amont : la prose reste sans appui."""
        self.assertIsNone(vt.source_toxicite([CULTURE]))
        f, _ = vt.fait(tox(True, False), vt.source_toxicite([CULTURE]),
                       "2026-11-12", False)
        self.assertNotIn("detail", f)

    def test_le_detail_n_est_jamais_servi_sans_son_evidence(self):
        """L'invariant, dit dans les deux sens : l'un ne va pas sans l'autre."""
        for source in (None, NCSTATE, ASPCA):
            for toxic, etabli in ((True, False), (False, False), (False, True)):
                f, motif = vt.fait(tox(toxic, etabli), source, "2026-11-12", False)
                if motif:
                    continue
                with self.subTest(source=bool(source), v=f["value"]):
                    self.assertEqual("detail" in f, "evidence" in f)


class LeChoixDeLaSource(unittest.TestCase):

    def test_la_source_de_toxicite_est_preferee_a_la_premiere(self):
        self.assertEqual(vt.source_toxicite([CULTURE, ASPCA]), ASPCA)

    def test_la_premiere_source_de_toxicite_gagne(self):
        """L'ordre de rédaction va du plus au moins autoritaire."""
        self.assertEqual(vt.source_toxicite([ASPCA, NCSTATE]), ASPCA)

    def test_aucune_source_de_toxicite_rend_none(self):
        self.assertIsNone(vt.source_toxicite([CULTURE]))
        self.assertIsNone(vt.source_toxicite([]))

    def test_le_nom_de_source_s_arrete_a_la_virgule(self):
        """Sinon `sourceName` ferait trois lignes dans chaque fiche servie."""
        self.assertEqual(vt.nom_de_source(ASPCA), "ASPCA Toxic and Non-Toxic Plants")

    def test_l_evidence_porte_la_source_et_la_date(self):
        f, _ = vt.fait(tox(False, True), ASPCA, "2026-11-12", False)
        self.assertEqual(f["evidence"]["sourceName"],
                         "ASPCA Toxic and Non-Toxic Plants")
        self.assertEqual(f["evidence"]["reviewedAt"], "2026-11-12")

    def test_aucune_evidence_ne_pretend_a_une_url(self):
        """Les fiches ne citent aucune URL : en inventer une serait un faux."""
        f, _ = vt.fait(tox(True, True), NCSTATE, "2026-11-12", False)
        self.assertNotIn("sourceURL", f["evidence"])


class LeVerdictEnfant(unittest.TestCase):
    """`toxicTo` ne liste `humans` que sur une partie des fiches ; son silence
    n'établit pas l'innocuité pour l'enfant.
    """

    def test_une_plante_toxique_aux_animaux_reste_toxique_pour_l_enfant(self):
        t = tox(True, True, toxicTo=["cats", "dogs"])
        enfant, _ = vt.fait(t, NCSTATE, "2026-11-12", True)
        self.assertEqual(enfant["value"], "toxic")

    def test_le_detail_enfant_ne_recite_pas_la_liste_des_animaux(self):
        t = tox(True, True, toxicTo=["cats", "dogs"])
        animal, _ = vt.fait(t, NCSTATE, "2026-11-12", False)
        enfant, _ = vt.fait(t, NCSTATE, "2026-11-12", True)
        self.assertIn("toxic to cats, dogs", animal["detail"])
        self.assertNotIn("toxic to cats", enfant["detail"])


class SurLesFichesReelles(unittest.TestCase):

    def ecrire(self, d, cle, meta):
        (d / f"{cle}.json").write_text(
            json.dumps({"_meta": meta, "translations": {"en": {}}}),
            encoding="utf-8")

    def test_l_operation_vise_le_modelurl_et_pose_le_schema(self):
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            self.ecrire(d, "Plante", {"toxicity": tox(True, True),
                                      "sources": [NCSTATE]})
            ops, refus = vt.operations(d, "2026-11-12")
            self.assertEqual(refus, [])
            self.assertEqual(ops[0]["modelURL"], "Plante_potless.usdz")
            self.assertEqual(ops[0]["set"]["botanicalProfile.schemaVersion"],
                             vt.SCHEMA)
            self.assertIn("botanicalProfile.childToxicity", ops[0]["set"])

    def test_une_toxicite_incomplete_fait_refuser_la_fiche(self):
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            self.ecrire(d, "Plante", {"toxicity": {"toxic": True}, "sources": []})
            ops, refus = vt.operations(d, "2026-11-12")
            self.assertEqual(ops, [])
            self.assertIn("incomplet", refus[0][1])

    def test_une_fiche_recalee_n_emporte_pas_le_lot(self):
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            self.ecrire(d, "Bonne", {"toxicity": tox(True, True),
                                     "sources": [NCSTATE]})
            self.ecrire(d, "Creuse", {"toxicity": {}, "sources": []})
            ops, refus = vt.operations(d, "2026-11-12")
            self.assertEqual([o["modelURL"] for o in ops], ["Bonne_potless.usdz"])
            self.assertEqual(len(refus), 1)

    def test_les_fichiers_techniques_sont_ignores(self):
        """`_fr_source.json` et consorts ne sont pas des fiches."""
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            (d / "_fr_source.json").write_text("{}", encoding="utf-8")
            ops, refus = vt.operations(d, "2026-11-12")
            self.assertEqual((ops, refus), ([], []))


if __name__ == "__main__":
    unittest.main()
