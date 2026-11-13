#!/usr/bin/env python3
"""Tests de scripts/promouvoir-catalogue.py. (#809)

Un seul sujet : **ce qu'on promeut d'un environnement à l'autre, et sous quel
identifiant.** Une fiche promue sous un identifiant neuf perd sa vignette, qui
est nommée d'après lui — le défaut ne se voit qu'à l'écran, sous la forme d'un
trou dans le catalogue.

  python3 -m unittest discover -s scripts -p 'test_*.py'
"""
import importlib.util
import pathlib
import tempfile
import unittest

_chemin = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "promouvoir-catalogue.py"
_spec = importlib.util.spec_from_file_location("promouvoir_catalogue", _chemin)
pc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pc)

_ops = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "appliquer-ops-mongo.py"
_s2 = importlib.util.spec_from_file_location("appliquer_ops_mongo", _ops)
ops = importlib.util.module_from_spec(_s2)
_s2.loader.exec_module(ops)


class FausseCollection:
    """Un double de collection : `find` rend les documents qu'on lui a donnés."""

    def __init__(self, docs):
        self.docs = docs

    def find(self, filtre=None, projection=None):
        return [dict(d) for d in self.docs]


def fiche(oid, url, **extra):
    d = {"_id": oid, "modelURL": url, "name": url.replace("_potless.usdz", "")}
    d.update(extra)
    return d


class CeQuiEstPromu(unittest.TestCase):

    def test_une_fiche_absente_de_la_cible_est_promue(self):
        p = pc.plan(FausseCollection([fiche("a1", "Plante_potless.usdz")]),
                    FausseCollection([]))
        self.assertEqual(len(p["a_creer"]), 1)
        self.assertEqual(p["conflits"], [])

    def test_une_fiche_deja_presente_n_est_pas_repromue(self):
        src = FausseCollection([fiche("a1", "Plante_potless.usdz")])
        dst = FausseCollection([fiche("a1", "Plante_potless.usdz")])
        p = pc.plan(src, dst)
        self.assertEqual(p["a_creer"], [])
        self.assertEqual(p["deja"], ["a1"])

    def test_un_lot_mixte_ne_promeut_que_le_manquant(self):
        src = FausseCollection([fiche("a1", "A_potless.usdz"),
                                fiche("a2", "B_potless.usdz")])
        dst = FausseCollection([fiche("a1", "A_potless.usdz")])
        p = pc.plan(src, dst)
        self.assertEqual([d["modelURL"] for d in p["a_creer"]], ["B_potless.usdz"])


class LIdentifiantEstConserve(unittest.TestCase):
    """Le nom du fichier de vignette EST l'identifiant de la fiche. Le laisser
    changer rend inutilisables les vignettes déjà rendues.
    """

    def test_le_document_promu_porte_son_identifiant_d_origine(self):
        p = pc.plan(FausseCollection([fiche("abc", "Plante_potless.usdz")]),
                    FausseCollection([]))
        self.assertEqual(p["a_creer"][0]["_id"], {"$oid": "abc"})

    def test_l_identifiant_survit_au_passage_par_le_json(self):
        """Extended JSON : la forme que `json` écrit et que Mongo relit."""
        import json
        p = pc.plan(FausseCollection([fiche("abc", "P_potless.usdz")]),
                    FausseCollection([]))
        relu = json.loads(json.dumps(p["a_creer"][0], default=str))
        self.assertEqual(relu["_id"], {"$oid": "abc"})

    def test_l_insertion_reconvertit_l_identifiant(self):
        """Le contrat entre les deux scripts : `{"$oid": …}` redevient ObjectId."""
        vus = []
        d = ops.avec_identifiant({"_id": {"$oid": "abc"}, "name": "P"},
                                 lambda s: vus.append(s) or f"OID({s})")
        self.assertEqual(vus, ["abc"])
        self.assertEqual(d["_id"], "OID(abc)")

    def test_un_document_sans_identifiant_passe_inchange(self):
        """Une création ordinaire laisse Mongo choisir, comme avant."""
        d = ops.avec_identifiant({"name": "P"}, lambda s: "jamais")
        self.assertNotIn("_id", d)

    def test_l_original_n_est_pas_modifie(self):
        src = {"_id": {"$oid": "abc"}, "name": "P"}
        ops.avec_identifiant(src, lambda s: "OID")
        self.assertEqual(src["_id"], {"$oid": "abc"})


class LesBasesQuiDivergent(unittest.TestCase):

    def test_un_meme_modele_sous_deux_identifiants_est_un_conflit(self):
        """Promouvoir donnerait deux fiches pour une plante, dont une sans
        vignette — exactement ce que le garde-fou des doublons existe pour
        empêcher, mais entre deux bases.
        """
        src = FausseCollection([fiche("a1", "Plante_potless.usdz")])
        dst = FausseCollection([fiche("ZZ", "Plante_potless.usdz")])
        p = pc.plan(src, dst)
        self.assertEqual(p["a_creer"], [])
        self.assertEqual(len(p["conflits"]), 1)
        self.assertEqual(p["conflits"][0][0], "Plante_potless.usdz")


class LesFichiersATransferer(unittest.TestCase):

    def test_seuls_les_fichiers_absents_de_la_cible_sont_comptes(self):
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            vs, vc = d / "vs", d / "vc"
            ms, mc = d / "ms", d / "mc"
            for x in (vs, vc, ms, mc):
                x.mkdir()
            (vs / "a1.png").write_bytes(b"x" * 10)
            (ms / "P_potless.usdz").write_bytes(b"y" * 20)
            a = [{"_id": {"$oid": "a1"}, "modelURL": "P_potless.usdz"}]
            r = pc.fichiers(a, vs, vc, ms, mc)
            self.assertEqual(r["vignettes"], ["a1.png"])
            self.assertEqual(r["modeles"], ["P_potless.usdz"])
            self.assertEqual(r["octets"], 30)

            # Déjà dans la cible : plus rien à transférer, et c'est rejouable.
            (vc / "a1.png").write_bytes(b"x" * 10)
            (mc / "P_potless.usdz").write_bytes(b"y" * 20)
            r2 = pc.fichiers(a, vs, vc, ms, mc)
            self.assertEqual((r2["vignettes"], r2["modeles"], r2["octets"]),
                             ([], [], 0))

    def test_un_fichier_absent_de_la_SOURCE_est_signale(self):
        """On ne peut pas transférer ce qu'on n'a pas : il faut le savoir avant
        d'écrire la fiche, pas après.
        """
        with tempfile.TemporaryDirectory() as t:
            d = pathlib.Path(t)
            for x in ("vs", "vc", "ms", "mc"):
                (d / x).mkdir()
            a = [{"_id": {"$oid": "a1"}, "modelURL": "P_potless.usdz"}]
            r = pc.fichiers(a, d / "vs", d / "vc", d / "ms", d / "mc")
            self.assertEqual(r["vignettes_absentes"], ["a1"])
            self.assertEqual(r["modeles_absents"], ["P_potless.usdz"])


if __name__ == "__main__":
    unittest.main()
