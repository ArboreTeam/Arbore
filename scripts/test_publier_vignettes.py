#!/usr/bin/env python3
"""Tests de vignettes/publier.py. (#696)

Un seul sujet : **le type d'exception**, et pourquoi il décide du sort de
l'ouvrier.

`surveiller()` enveloppe chaque tâche dans `except Exception`, afin qu'un échec
soit DÉCLARÉ plutôt qu'abandonné en silence — sans quoi la tâche resterait « en
cours » vingt minutes et l'atelier afficherait un travail qui n'avance pas.

Or `SystemExit` dérive de `BaseException` et traverse donc ce `except`. Avec un
`SystemExit`, un atelier pas encore redéployé — qui remet une tâche sans champ
`interne` — tuait l'ouvrier au lieu de faire déclarer la tâche en échec. Et
c'est un ordre de déploiement normal : le web et l'ouvrier ne redémarrent pas à
la même seconde.

La distinction est invisible à la lecture et ne casse rien tant qu'on ne lit pas
les bons secrets. D'où ce test.

  python3 -m unittest discover -s scripts -p 'test_*.py'
"""
import importlib.util
import pathlib
import unittest

_chemin = pathlib.Path(__file__).resolve().parents[1] / "vignettes" / "publier.py"
_spec = importlib.util.spec_from_file_location("publier_vignettes", _chemin)
publier = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(publier)


class EntetesInternes(unittest.TestCase):

    def test_cas_nominal_rend_les_deux_entetes(self):
        """Les deux clés, et exactement deux en-têtes d'authentification.

        Les routes `/internal/*` exigent `X-API-Key` ET
        `X-Arbore-Internal-Key`. Le `User-Agent` qui les accompagne n'authentifie
        rien — d'où le partage en deux assertions plutôt qu'une égalité stricte
        du dictionnaire, qui mélangerait les deux sujets.
        """
        e = publier.entetes_internes("cle-api", "cle-interne")

        self.assertEqual(e["X-API-Key"], "cle-api")
        self.assertEqual(e["X-Arbore-Internal-Key"], "cle-interne")

        # Aucun `Authorization` ne doit revenir : c'est la voie Firebase qu'on
        # a justement abandonnee.
        auth = [k for k in e if k.lower() in ("authorization", "cookie")
                or k.lower().startswith("x-") and k not in
                ("X-API-Key", "X-Arbore-Internal-Key")]
        self.assertEqual(auth, [], "en-tete d'authentification inattendu : %r" % (auth,))

    def test_une_cle_manquante_leve_value_error(self):
        for nom, args in [
            ("clé d'API absente", ("", "interne")),
            ("clé d'API à None", (None, "interne")),
            ("clé interne absente", ("api", "")),
            ("clé interne à None", ("api", None)),
        ]:
            with self.subTest(nom):
                with self.assertRaises(ValueError):
                    publier.entetes_internes(*args)

    def test_le_refus_est_rattrape_par_except_exception(self):
        """LE test de ce fichier.

        Il reproduit littéralement la clause de `surveiller()`. Un `SystemExit`
        y passerait au travers et tuerait l'ouvrier ; le `else` ci-dessous est
        donc le constat d'échec, pas une branche morte.
        """
        try:
            publier.entetes_internes("api", None)
        except Exception as exc:                          # noqa: BLE001
            self.assertIn("clé interne absente", str(exc))
        except BaseException:                             # pragma: no cover
            self.fail("le refus traverse `except Exception` : l'ouvrier mourrait "
                      "au lieu de déclarer la tâche en échec")
        else:                                             # pragma: no cover
            self.fail("aucune exception levée pour une clé interne absente")

    def test_un_agent_est_annonce(self):
        """`urllib` envoie sinon « Python-urllib/3.x », que Cloudflare refuse
        par un 403 — mesure du 2026-11-02 : 200 avec l'agent de curl, 403 avec
        celui d'urllib, memes cles et meme URL.

        L'ouvrier passe desormais par l'adresse interne et ne traverse plus de
        CDN, donc ce n'est pas la parade. Mais un robot doit se nommer : un
        agent honnete se journalise, se compte, et se bloque nommement si
        besoin.
        """
        e = publier.entetes_internes("api", "interne")

        self.assertIn("User-Agent", e)
        self.assertIn("arbore-vignettes", e["User-Agent"])
        self.assertNotIn("urllib", e["User-Agent"])

    def test_le_message_dit_ou_poser_la_cle(self):
        """Un message qui ne nomme pas l'endroit fait rouvrir le code.

        On a passé cinq cycles de diagnostic sur des 401 et des 404 de cette
        chaîne ; le message doit couvrir les DEUX modes, le job autonome et la
        veille, puisqu'ils ne lisent pas le secret au même endroit.
        """
        with self.assertRaises(ValueError) as pris:
            publier.entetes_internes("api", "")

        message = str(pris.exception)
        self.assertIn("ARBORE_INTERNAL_KEY", message)
        self.assertIn("VIGNETTES_ENVIRONNEMENTS", message)


class RoutesVisees(unittest.TestCase):
    """Les appels doivent viser `/internal/*`.

    Les routes sans préfixe existent toujours — elles servent l'app — mais
    vivent sous `protected`, donc derrière une session Firebase qu'un robot ne
    peut pas tenir. Viser la mauvaise rend un 401 que rien n'explique.
    """

    def test_les_trois_appels_portent_le_prefixe_interne(self):
        source = _chemin.read_text(encoding="utf-8")

        for appel in [
            '{base}/internal/plants',
            '{base}/internal/models/{fichier}',
            '{base}/internal/models/thumbnails/{plant_id}',
        ]:
            with self.subTest(appel):
                self.assertIn(appel, source)

    def test_aucun_appel_ne_vise_plus_les_routes_de_l_app(self):
        source = _chemin.read_text(encoding="utf-8")

        for interdit in [
            'f"{base}/plants"',
            'f"{base}/models/{fichier}"',
            'f"{base}/models/thumbnails/{plant_id}"',
        ]:
            with self.subTest(interdit):
                self.assertNotIn(interdit, source)

    def test_aucune_trace_d_authentification_firebase(self):
        """Le compte de service administrateur est abandonné (#696). Son retour
        se signalerait par l'une de ces trois chaînes."""
        source = _chemin.read_text(encoding="utf-8")

        self.assertNotIn("ARBORE_ADMIN_TOKEN", source)
        self.assertNotIn("ARBORE_FIREBASE_KEY", source)
        self.assertNotIn("identitytoolkit", source)


class AppelerSurvitAuxCoupures(unittest.TestCase):
    """L'ouvrier ne doit pas mourir quand l'atelier redemarre. (#695)

    Observe le 2026-11-02 : `URLError: [Errno 111] Connection refused` remonte
    de `appeler` jusqu'a `main`, conteneur terminé, `RestartCount: 1`. Docker
    l'a relance, mais une tache en vol aurait ete perdue — elle serait restee
    « en cours » vingt minutes, et une passe de catalogue dure des heures.
    """

    def simuler(self, exc):
        """Remplace `urlopen` par une levee, et rend ce que `appeler` renvoie."""
        import urllib.request
        vrai = urllib.request.urlopen

        def faux(*a, **k):
            raise exc
        urllib.request.urlopen = faux
        try:
            return publier.appeler("biscuit=x", "http://atelier/api")
        finally:
            urllib.request.urlopen = vrai

    def test_connexion_refusee_ne_leve_pas(self):
        import urllib.error
        statut, corps = self.simuler(
            urllib.error.URLError(ConnectionRefusedError(111, "Connection refused")))

        self.assertEqual(statut, publier.INJOIGNABLE)
        self.assertIn("injoignable", corps.decode("utf-8"))

    def test_delai_depasse_ne_leve_pas(self):
        """`urlopen` leve un `TimeoutError` NU, qui ne derive pas de URLError."""
        statut, corps = self.simuler(TimeoutError("timed out"))

        self.assertEqual(statut, publier.INJOIGNABLE)
        self.assertIn("délai", corps.decode("utf-8"))

    def test_un_refus_du_serveur_reste_un_refus(self):
        """L'ordre des `except` compte : `HTTPError` HERITE de `URLError`.

        Dans le mauvais ordre, un 401 de l'atelier passerait pour une coupure
        reseau — et on perdrait le diagnostic qui a deja coute cinq cycles.
        """
        import io as _io
        import urllib.error
        statut, corps = self.simuler(urllib.error.HTTPError(
            "http://atelier/api", 401, "Unauthorized", {},
            _io.BytesIO(b'{"error":"Non authentifie"}')))

        self.assertEqual(statut, 401)
        self.assertIn(b"Non authentifie", corps)

    def test_injoignable_est_hors_de_la_plage_http(self):
        """La boucle teste `!= 200` ; le sentinelle doit aussi se distinguer
        d'un vrai code dans le journal."""
        self.assertEqual(publier.INJOIGNABLE, 0)
        self.assertNotEqual(publier.INJOIGNABLE, 204)


class Chronometrage(unittest.TestCase):
    """Les mesures de phases doivent remonter dans le journal. (#695)

    Une plante AVEC pot coute trois fois une plante sans — 269 s contre 85 s a
    plafond CPU egal — et rien ne disait ou partait ce temps. `rendre.py` les
    emet, `publier.py` les releve.
    """

    def test_le_prefixe_est_le_meme_des_deux_cotes(self):
        """Deux constantes, deux fichiers : elles divergeraient en silence.

        Si `rendre.py` changeait de prefixe, `publier.py` n'en releverait plus
        AUCUNE — et le journal redeviendrait muet sans que rien n'echoue.
        """
        rendre = (_chemin.parent / "rendre.py").read_text(encoding="utf-8")

        self.assertIn('MARQUE_TEMPS = "%s"' % publier.MARQUE_TEMPS, rendre,
                      "le prefixe de rendre.py ne correspond plus a celui de publier.py")

    def test_les_phases_attendues_sont_chronometrees(self):
        """Chaque phase nommee ici est un suspect du surcout du pot.

        Les retirer rendrait la mesure aveugle precisement la ou on cherche.
        """
        rendre = (_chemin.parent / "rendre.py").read_text(encoding="utf-8")

        for phase in ("import_plante", "import_pot", "composition_totale",
                      "decor_eclairage_camera", "rendu", "marqueur"):
            with self.subTest(phase):
                self.assertIn('chrono("%s")' % phase, rendre)

    def test_le_releve_ne_retient_que_les_lignes_de_temps(self):
        """Blender crache des centaines de lignes par rendu.

        Tout journaliser noierait le signal ; n'en journaliser aucune laisserait
        la question ouverte. Le filtre est donc le coeur de la mesure.
        """
        source = _chemin.read_text(encoding="utf-8")

        self.assertIn("ligne.startswith(MARQUE_TEMPS)", source)


class SessionQuiSeRouvre(unittest.TestCase):
    """Le défaut : l'ouvrier gardait une session périmée pour toujours.

    Il ouvrait UNE session au démarrage. À son expiration — ou à la rotation de
    `GENERATOR_SESSION_SECRET` lors d'un redéploiement du web — chaque appel
    prenait un 401 que la boucle journalisait avant de recommencer, sans jamais
    tenter de se reconnecter. Mesuré le 2026-11-11 : 6 973 refus en deux jours,
    conteneur `Up`, file qui s'accumule, aucune alerte.

    Ces tests tiennent au comportement, pas à la forme : ils remplacent
    `appeler` et `ouvrir_atelier` et comptent ce qui est tenté.
    """

    def setUp(self):
        self._appeler = publier.appeler
        self._ouvrir = publier.ouvrir_atelier
        self.addCleanup(setattr, publier, "appeler", self._appeler)
        self.addCleanup(setattr, publier, "ouvrir_atelier", self._ouvrir)

    def _session(self, reponses, ouvertures=None):
        """Monte une session dont les appels rendent `reponses` dans l'ordre."""
        self.appels = []
        self.ouvertures = 0
        suite = list(reponses)

        def faux_appeler(biscuit, url, corps=None, methode=None, delai=120):
            self.appels.append((biscuit, url))
            return suite.pop(0)

        def faux_ouvrir():
            self.ouvertures += 1
            if ouvertures is not None and self.ouvertures > ouvertures:
                raise SystemExit("atelier : connexion refusée (401) — clé invalide ?")
            return "http://web:3000", f"arbore_generator=jeton{self.ouvertures}"

        publier.appeler = faux_appeler
        publier.ouvrir_atelier = faux_ouvrir
        return publier.SessionAtelier()

    def test_un_401_declenche_une_reconnexion_et_un_rejeu(self):
        s = self._session([(401, b"Non authentifie"), (200, b"ok")])

        statut, corps = s.appeler("/api/generator/vignettes/prendre", methode="POST")

        self.assertEqual((statut, corps), (200, b"ok"))
        self.assertEqual(self.ouvertures, 2, "la session aurait dû être rouverte")
        self.assertEqual(self.appels[0][0], "arbore_generator=jeton1")
        self.assertEqual(self.appels[1][0], "arbore_generator=jeton2",
                         "le rejeu doit porter le NOUVEAU cookie")

    def test_le_nouveau_cookie_sert_aux_appels_suivants(self):
        """Sans ça, chaque appel paierait une reconnexion : on garde la session."""
        s = self._session([(401, b""), (200, b"a"), (200, b"b")])

        s.appeler("/un")
        s.appeler("/deux")

        self.assertEqual(self.ouvertures, 2, "une seule reconnexion attendue")
        self.assertEqual(self.appels[-1][0], "arbore_generator=jeton2")

    def test_une_reconnexion_impossible_ne_tue_pas_l_ouvrier(self):
        """`ouvrir_atelier` lève `SystemExit`, qui traverse `except Exception`.

        Au démarrage, mourir est correct. En cours de route, non : un atelier
        absent, c'est un déploiement du web, et l'ouvrier doit y survivre pour
        réessayer au tour suivant. On rend le 401 d'origine.
        """
        s = self._session([(401, b"Non authentifie")], ouvertures=1)

        statut, corps = s.appeler("/api/generator/vignettes/prendre")

        self.assertEqual(statut, 401)
        self.assertEqual(corps, b"Non authentifie")

    def test_on_ne_se_reconnecte_pas_en_boucle(self):
        """Un 401 APRÈS reconnexion est un refus, pas une expiration.

        Insister martèlerait l'atelier à chaque tour de boucle sans rien
        changer : la clé a été retirée des empreintes acceptées, et seule une
        intervention humaine y remédie.
        """
        s = self._session([(401, b""), (401, b"toujours refuse")])

        statut, corps = s.appeler("/api/generator/vignettes/prendre")

        self.assertEqual((statut, corps), (401, b"toujours refuse"))
        self.assertEqual(self.ouvertures, 2, "une seule tentative de reconnexion")

    def test_un_statut_non_401_ne_reconnecte_pas(self):
        for statut in (200, 204, 404, 500, publier.INJOIGNABLE):
            with self.subTest(statut=statut):
                s = self._session([(statut, b"")])
                s.appeler("/un")
                self.assertEqual(self.ouvertures, 1,
                                 f"{statut} ne doit pas rouvrir de session")


class AlerteSurRefusRepetes(unittest.TestCase):
    """Une panne durable ne doit pas se lire comme 6 973 lignes identiques."""

    def test_le_seuil_est_atteignable_et_laisse_passer_un_redeploiement(self):
        self.assertGreaterEqual(publier.SEUIL_ALERTE, 2,
                                "un seuil de 1 crierait au premier hoquet")
        self.assertLessEqual(publier.SEUIL_ALERTE, 60,
                             "un seuil trop haut laisserait la panne dormir")

    def test_l_alerte_est_emise_une_seule_fois(self):
        """Répétée à chaque tour, elle se noierait dans le bruit qu'elle dénonce."""
        source = _chemin.read_text(encoding="utf-8")

        self.assertIn("if refus == SEUIL_ALERTE:", source)
        self.assertNotIn("if refus >= SEUIL_ALERTE:", source)


if __name__ == "__main__":
    unittest.main()
