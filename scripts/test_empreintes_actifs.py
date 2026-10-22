#!/usr/bin/env python3
"""Tests de empreintes-actifs.py. (#294, #524)

Deux erreurs opposées, toutes deux coûteuses.

Ne PAS changer quand le fichier a changé laisse un appareil sur un modèle
périmé indéfiniment : `Documents/Models/` survit aux mises à jour. C'est le
défaut qu'on répare.

Changer quand le fichier n'a PAS changé fait retélécharger pour rien — 440 Mo
pour les 123 modèles light. C'est le défaut du compteur global de #524, celui
qu'on refuse de reproduire.

  python3 -m unittest discover -s scripts -p 'test_*.py'
"""
import importlib.util
import pathlib
import tempfile
import unittest

_chemin = pathlib.Path(__file__).with_name("empreintes-actifs.py")
_spec = importlib.util.spec_from_file_location("empreintes_actifs", _chemin)
emp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(emp)


class Empreinte(unittest.TestCase):
    def fichier(self, contenu: bytes) -> pathlib.Path:
        d = pathlib.Path(tempfile.mkdtemp())
        f = d / "m.usdz"
        f.write_bytes(contenu)
        return f

    def test_deterministe(self):
        f = self.fichier(b"des octets de modele")
        self.assertEqual(emp.empreinte(f), emp.empreinte(f))

    def test_un_octet_suffit_a_la_changer(self):
        a = emp.empreinte(self.fichier(b"modele version 1"))
        b = emp.empreinte(self.fichier(b"modele version 2"))
        self.assertNotEqual(a, b, "sinon l'appareil garde le fichier périmé")

    def test_longueur_et_alphabet(self):
        v = emp.empreinte(self.fichier(b"x"))
        self.assertEqual(len(v), emp.LONGUEUR)
        self.assertTrue(set(v) <= set("0123456789abcdef"),
                        "la valeur finit dans un nom de fichier et dans une URL")

    def test_fichier_vide(self):
        self.assertEqual(len(emp.empreinte(self.fichier(b""))), emp.LONGUEUR)

    # Lu par blocs d'un mégaoctet : un fichier plus grand qu'un bloc doit
    # donner le même résultat qu'une lecture d'un seul tenant.
    def test_plusieurs_blocs(self):
        gros = b"a" * (emp.BLOC * 2 + 7)
        import hashlib
        attendu = hashlib.sha256(gros).hexdigest()[:emp.LONGUEUR]
        self.assertEqual(emp.empreinte(self.fichier(gros)), attendu)


class Repertoire(unittest.TestCase):
    def test_repertoire_absent_ou_vide(self):
        self.assertEqual(emp.empreintes_du_repertoire(None, "*.usdz"), {})
        self.assertEqual(
            emp.empreintes_du_repertoire(pathlib.Path("/n/existe/pas"), "*.usdz"), {})
        vide = pathlib.Path(tempfile.mkdtemp())
        self.assertEqual(emp.empreintes_du_repertoire(vide, "*.usdz"), {})

    def test_ne_retient_que_le_motif(self):
        d = pathlib.Path(tempfile.mkdtemp())
        (d / "a.usdz").write_bytes(b"1")
        (d / "b.png").write_bytes(b"2")
        (d / "c.usdz").write_bytes(b"3")
        got = emp.empreintes_du_repertoire(d, "*.usdz")
        self.assertEqual(sorted(got), ["a.usdz", "c.usdz"])

    def test_ignore_les_sous_repertoires(self):
        d = pathlib.Path(tempfile.mkdtemp())
        (d / "a.usdz").write_bytes(b"1")
        (d / "heavy.usdz").mkdir()
        self.assertEqual(sorted(emp.empreintes_du_repertoire(d, "*.usdz")), ["a.usdz"])


class Operations(unittest.TestCase):
    def test_light_seul(self):
        ops = emp.operations({"A.usdz": "aaaa1111"}, {}, {}, set())
        self.assertEqual(ops["plantes"], [
            {"modelURL": "A.usdz", "set": {"versions.model": "aaaa1111"}}])

    # Les deux fichiers sont distincts : remplacer le light ne doit pas faire
    # retélécharger le heavy, qui pèse dix fois plus.
    def test_light_et_heavy_sont_deux_champs(self):
        ops = emp.operations({"A.usdz": "aaaa1111"}, {"A.usdz": "bbbb2222"}, {}, set())
        self.assertEqual(ops["plantes"][0]["set"], {
            "versions.model": "aaaa1111", "versions.modelHeavy": "bbbb2222"})

    def test_heavy_sans_light_est_ignore(self):
        ops = emp.operations({}, {"A.usdz": "bbbb2222"}, {}, set())
        self.assertEqual(ops["plantes"], [],
                         "un heavy sans light ne sera jamais demandé : le client part du light")

    # Un pot n'est pas une plante : il vit dans sa propre collection et ne doit
    # pas se retrouver visé comme une fiche de catalogue.
    def test_un_pot_ne_sort_pas_dans_les_plantes(self):
        ops = emp.operations({"A.usdz": "aaaa1111", "pot.usdz": "cccc3333"},
                             {}, {}, {"pot.usdz"})
        self.assertEqual([o["modelURL"] for o in ops["plantes"]], ["A.usdz"])
        self.assertEqual(ops["pots"], [
            {"modelURL": "pot.usdz", "set": {"version": "cccc3333"}}])

    def test_pot_declare_mais_absent_du_disque(self):
        ops = emp.operations({"A.usdz": "aaaa1111"}, {}, {}, {"fantome.usdz"})
        self.assertEqual(ops["pots"], [])

    # La vignette est nommée d'après l'identifiant de la fiche, pas d'après le
    # modèle : elle se vise par `_id`.
    def test_vignettes_visees_par_identifiant(self):
        ops = emp.operations({}, {}, {"6a3ff8e06142f7224ca8dee9.png": "dddd4444"}, set())
        self.assertEqual(ops["vignettes"], [
            {"id": "6a3ff8e06142f7224ca8dee9", "set": {"versions.thumbnail": "dddd4444"}}])

    # Les chemins pointés sont des sous-champs : écrire le sous-document entier
    # effacerait les empreintes des autres fichiers.
    def test_les_chemins_sont_pointes(self):
        ops = emp.operations({"A.usdz": "aaaa1111"}, {}, {"id.png": "dddd4444"}, set())
        for cle in list(ops["plantes"][0]["set"]) + list(ops["vignettes"][0]["set"]):
            self.assertTrue(cle.startswith("versions."),
                            f"{cle} devrait être un chemin pointé, sinon il écrase le sous-document")

    def test_rien_du_tout(self):
        self.assertEqual(emp.operations({}, {}, {}, set()),
                         {"plantes": [], "pots": [], "vignettes": []})


if __name__ == "__main__":
    unittest.main()


# --- Ciblage des plantes par le script d'application -----------------------

class CiblageDesPlantes(unittest.TestCase):
    """`cibler_plantes` décide quel filtre trouve réellement chaque fiche.

    C'est le point où une passe ultérieure peut silencieusement n'atteindre
    personne : le filtre vise l'ancien `modelURL`, et les fiches de la passe
    précédente portent déjà le nouveau.
    """

    def setUp(self):
        _s = importlib.util.spec_from_file_location(
            "appliquer_ops", pathlib.Path(__file__).with_name("appliquer-ops-mongo.py"))
        self.app = importlib.util.module_from_spec(_s)
        _s.loader.exec_module(self.app)

    class FauxPlants:
        def __init__(self, urls):
            self.urls = set(urls)

        def find_one(self, filtre, _projection=None):
            return {"_id": 1} if filtre.get("modelURL") in self.urls else None

    def test_fiche_trouvee_par_son_nom_actuel(self):
        p = self.FauxPlants({"A.usdz"})
        faire, introuvables, rejouees = self.app.cibler_plantes(
            p, [{"modelURL": "A.usdz", "set": {"versions.model": "aaaa1111"}}])
        self.assertEqual(faire, [({"modelURL": "A.usdz"}, {"versions.model": "aaaa1111"})])
        self.assertEqual((introuvables, rejouees), ([], 0))

    def test_fiche_deja_basculee_retrouvee_par_son_nouveau_nom(self):
        p = self.FauxPlants({"A_potless.usdz"})
        faire, introuvables, rejouees = self.app.cibler_plantes(
            p, [{"modelURL": "A.usdz", "set": {"modelURL": "A_potless.usdz", "potless": True}}])
        self.assertEqual(faire[0][0], {"modelURL": "A_potless.usdz"})
        self.assertEqual((introuvables, rejouees), ([], 1))

    def test_fiche_absente_est_signalee(self):
        p = self.FauxPlants(set())
        faire, introuvables, rejouees = self.app.cibler_plantes(
            p, [{"modelURL": "Fantome.usdz", "set": {"versions.model": "aaaa1111"}}])
        self.assertEqual(faire, [])
        self.assertEqual(introuvables, ["Fantome.usdz"])

    # Une mise à jour d'empreinte ne renomme rien : sans `modelURL` dans le
    # `set`, il n'y a pas de repli possible, et la fiche doit être signalée.
    def test_sans_renommage_aucun_repli(self):
        p = self.FauxPlants({"A_potless.usdz"})
        faire, introuvables, _ = self.app.cibler_plantes(
            p, [{"modelURL": "A.usdz", "set": {"versions.model": "aaaa1111"}}])
        self.assertEqual(faire, [])
        self.assertEqual(introuvables, ["A.usdz"])
