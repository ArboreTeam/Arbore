"""Rend et publie les vignettes du catalogue. (#694, #695)

Ne parle QU'À L'API. Il ignore où les fichiers vivent, et c'est délibéré.

## Pourquoi pas de montage de répertoire

La prod sert ses assets depuis `r2`, dev depuis `filesystem`. Un job qui
monterait des répertoires ne fonctionnerait tout simplement pas sur la prod.

Et le 30 octobre, manipuler les fichiers en direct a produit **54 empreintes
fausses sur 123** : deux répertoires de vignettes existent sur le VPS, un seul
est monté dans le conteneur. Connaître la disposition du stockage, c'est
pouvoir s'y tromper.

En passant par `POST /internal/models/thumbnails/:plantId`, c'est le backend
qui écrit et qui recalcule `versions.thumbnail` sur les octets qu'il vient
d'écrire (#687). Publier une empreinte qui ment devient impossible, pas
seulement improbable.

## Comment il s'authentifie

Par DEUX clés, et aucune session Firebase (#696) :

    ARBORE_API_BASE      https://api-dev.arbore.app
    ARBORE_API_KEY       clé d'API           -> en-tête X-API-Key
    ARBORE_INTERNAL_KEY  clé des routes internes -> X-Arbore-Internal-Key

La première version visait les routes de l'app, sous `protected` : clé d'API
PUIS session Firebase. Un robot ne pouvant pas tenir de session, la seule voie
était un compte de service ayant le rôle administrateur — un compte humain
détourné, avec son mot de passe à conserver, son jeton à rafraîchir, son UID
dans `ARBORE_ADMIN_UIDS`, et le droit d'écrire tout le catalogue. Pour déposer
des images.

Les routes `/internal/*` donnent exactement les trois gestes nécessaires —
lister le catalogue, télécharger un modèle, déposer une vignette — et rien de
plus. Elles exigent les deux clés ensemble : la clé d'API seule, celle que
porte l'app iOS, n'y donne pas accès.

## Mode veille

`--surveiller` en fait un OUVRIER : il consomme la file déposée par l'atelier,
exactement comme l'ouvrier Colab consomme `/api/generator/taches`. C'est ce
qui donne un bouton à l'atelier sans monter la socket Docker dans un
conteneur exposé.

    ATELIER_BASE         http://web:3000 (adresse joignable)
    ATELIER_HOTE         generator.arbore.app (en-tête Host à présenter)
    ATELIER_CLE          clé d'accès de l'atelier
    ARBORE_ENV_NOM       l'environnement servi, « dev » ou « prod »

`ATELIER_HOTE` n'est pas un doublon de `ATELIER_BASE`. L'atelier REFUSE par un
404 tout ce qui ne se présente pas sous son hôte — `bonHote()` compare
l'en-tête `Host` à `GENERATOR_HOST`, et le middleware fait de même. Joint sur
le réseau interne, le job enverrait `Host: web:3000` et prendrait un 404 à
chaque appel, sans jamais rien faire. Mesuré : 404 sans l'en-tête, 401 avec.

Un ouvrier ne sert QU'UN environnement, et c'est volontaire. En veille il ne
porte AUCUNE clé de backend : l'atelier les joint à la tâche qu'il remet, avec
l'adresse de l'API. `ARBORE_ENV_NOM` décide seulement de la file où il puise.
Un ouvrier branché sur dev n'a donc, à aucun instant, de quoi écrire en
production — ce n'est pas une consigne, c'est qu'il ne reçoit jamais le
secret.
"""
import argparse
import json
import os
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

LARGEUR, HAUTEUR = 720, 900
MARQUEUR_RVB = (94, 28, 186)
POIDS_PLANCHER = 50_000          # en dessous, le rendu est vide ou tronqué
# 5, comme `hasCurrentDesignMarker` : un contrôle plus large que le juge
# laisse passer ce que le juge refusera, en silence.
TOLERANCE_MARQUEUR = 5


def http(url, entetes, corps=None, methode=None, delai=300):
    req = urllib.request.Request(url, data=corps, headers=entetes, method=methode)
    with urllib.request.urlopen(req, timeout=delai) as r:
        return r.status, r.read()


def entetes_internes(cle_api, cle_interne):
    """Les deux en-têtes qu'exigent les routes `/internal/*`. (#696)

    Les deux sont vérifiés ici plutôt qu'au premier appel : un secret manquant
    doit se dire en une phrase au démarrage, pas se deviner depuis un 401 ou un
    503 remonté du backend. On vient d'y passer cinq cycles de diagnostic.
    """
    if not cle_api:
        raise SystemExit("clé d'API absente — en-tête X-API-Key impossible")
    if not cle_interne:
        raise SystemExit(
            "clé interne absente — les routes /internal/* répondront 401. "
            "La poser dans ARBORE_INTERNAL_KEY (job autonome), ou dans le champ "
            "`interne` de VIGNETTES_ENVIRONNEMENTS côté atelier (mode veille).")
    return {"X-API-Key": cle_api, "X-Arbore-Internal-Key": cle_interne}


def catalogue(base, entetes):
    statut, corps = http(f"{base}/internal/plants", entetes)
    if statut != 200:
        raise SystemExit(f"GET /internal/plants a rendu {statut}")
    return json.loads(corps)


def dimensions_png(donnees):
    if donnees[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", donnees[16:24])


def _lignes_png(brut, largeur, hauteur, canaux):
    """Défiltre les lignes d'un PNG décompressé.

    Les quatre filtres du format sont tous possibles : Blender en choisit
    librement. Lire le premier octet d'une seule ligne, comme on le faisait,
    ne marchait que par chance sur une ligne non filtrée.
    """
    pas = largeur * canaux
    lignes, prec, pos = [], bytearray(pas), 0
    for _ in range(hauteur):
        f = brut[pos]
        pos += 1
        cur = bytearray(brut[pos:pos + pas])
        pos += pas
        if f == 1:
            for i in range(canaux, pas):
                cur[i] = (cur[i] + cur[i - canaux]) & 255
        elif f == 2:
            for i in range(pas):
                cur[i] = (cur[i] + prec[i]) & 255
        elif f == 3:
            for i in range(pas):
                g = cur[i - canaux] if i >= canaux else 0
                cur[i] = (cur[i] + ((g + prec[i]) >> 1)) & 255
        elif f == 4:
            for i in range(pas):
                g = cur[i - canaux] if i >= canaux else 0
                h = prec[i]
                d = prec[i - canaux] if i >= canaux else 0
                pg, ph, pd = abs(h - d), abs(g - d), abs(g + h - 2 * d)
                pred = g if (pg <= ph and pg <= pd) else (h if ph <= pd else d)
                cur[i] = (cur[i] + pred) & 255
        lignes.append(cur)
        prec = cur
    return lignes


def coins_marques(chemin):
    """Vérifie le marqueur sans dépendance d'image, en décodant le PNG.

    Ce contrôle n'est pas une précaution de confort. Une vignette sans marqueur
    est téléchargée par l'app, **examinée, refusée**, et les cartes gardent
    l'ancienne image — sans que rien ne le signale. C'est exactement ce qui est
    arrivé le 30 octobre à 123 fichiers par ailleurs irréprochables.

    Échantillonne les MÊMES quatre points que `hasCurrentDesignMarker`, au même
    retrait de 1,75 % du petit côté, et exige les mêmes trois sur quatre.
    Contrôler le seul pixel (0, 0) laissait passer une image dont trois coins
    sur quatre manquaient — et c'est l'app qui aurait tranché, en silence.
    """
    import zlib
    d = open(chemin, "rb").read()
    pos, largeur, hauteur, canaux, idat = 8, None, None, None, b""
    while pos < len(d):
        lg = struct.unpack(">I", d[pos:pos + 4])[0]
        typ = d[pos + 4:pos + 8]
        corps = d[pos + 8:pos + 8 + lg]
        if typ == b"IHDR":
            largeur, hauteur, prof, couleur = struct.unpack(">IIBB", corps[:10])
            if prof != 8 or couleur not in (2, 6):
                return False
            canaux = 3 if couleur == 2 else 4
        elif typ == b"IDAT":
            idat += corps
        elif typ == b"IEND":
            break
        pos += 12 + lg
    if not idat or largeur is None:
        return False

    lignes = _lignes_png(zlib.decompress(idat), largeur, hauteur, canaux)
    retrait = max(1, int(min(largeur, hauteur) * 0.0175))
    points = ((retrait, retrait),
              (max(largeur - retrait - 1, 0), retrait),
              (retrait, max(hauteur - retrait - 1, 0)),
              (max(largeur - retrait - 1, 0), max(hauteur - retrait - 1, 0)))
    bons = 0
    for x, y in points:
        pixel = lignes[y][x * canaux:x * canaux + 3]
        if all(abs(a - b) <= TOLERANCE_MARQUEUR
               for a, b in zip(pixel, MARQUEUR_RVB)):
            bons += 1
    return bons >= 3


def telecharger_modele(base, entetes, fichier, version, dest):
    url = f"{base}/internal/models/{fichier}"
    if version:
        url += f"?v={version}"
    statut, corps = http(url, entetes)
    if statut != 200:
        raise RuntimeError(f"GET /internal/models/{fichier} a rendu {statut}")
    open(dest, "wb").write(corps)
    return len(corps)


# Nom du réglage côté atelier -> option de `rendre.py`.
REGLAGES = {
    "ciel": "--ciel", "herbe": "--herbe", "echantillons": "--echantillons",
    "puissanceCle": "--puissance-cle", "ambiante": "--ambiante",
    "teinteSol": "--teinte-sol",
}


def rendre(modele, sortie, pot=None, pose=None, reglages=None):
    cmd = ["blender", "--background", "--factory-startup",
           "--python", "/app/rendre.py", "--",
           "--modele", modele, "--sortie", sortie]
    if pot and pose:
        cmd += ["--pot", pot, "--pose", json.dumps(pose)]
    # Les réglages viennent de la TÂCHE, pas de l'environnement du conteneur :
    # une passe lancée ce matin doit rendre avec les réglages de ce matin, même
    # si l'atelier a changé de couleur depuis.
    for cle, option in REGLAGES.items():
        if reglages and cle in reglages:
            cmd += [option, str(reglages[cle])]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    if r.returncode != 0 or not os.path.exists(sortie):
        derniere = (r.stderr or r.stdout or "").strip().splitlines()[-3:]
        raise RuntimeError("blender a échoué : " + " | ".join(derniere))


def controler(chemin):
    """Les quatre garanties, avant tout envoi. Un lot n'est pas publié à moitié."""
    d = open(chemin, "rb").read()
    dims = dimensions_png(d)
    if dims is None:
        return "pas un PNG"
    if dims != (LARGEUR, HAUTEUR):
        return f"{dims[0]}x{dims[1]} au lieu de {LARGEUR}x{HAUTEUR}"
    if len(d) < POIDS_PLANCHER:
        return f"{len(d)} octets — rendu probablement vide"
    if not coins_marques(chemin):
        return "marqueur de design absent : l'app refuserait cette vignette"
    return None


def publier(base, entetes, plant_id, chemin):
    """Envoi multipart. Le backend écrit ET recalcule l'empreinte (#687)."""
    limite = "----arbore-vignettes"
    corps = (
        f"--{limite}\r\n"
        f'Content-Disposition: form-data; name="thumbnail"; filename="{plant_id}.png"\r\n'
        "Content-Type: image/png\r\n\r\n").encode() + open(chemin, "rb").read() + \
        f"\r\n--{limite}--\r\n".encode()
    e = dict(entetes)
    e["Content-Type"] = f"multipart/form-data; boundary={limite}"
    statut, reponse = http(
        f"{base}/internal/models/thumbnails/{plant_id}", e, corps, "POST")
    if statut != 200:
        raise RuntimeError(f"POST a rendu {statut} : {reponse[:160].decode(errors='replace')}")
    return json.loads(reponse)


# Nom du cookie de session de l'atelier, cf. `COOKIE_SESSION` côté web.
COOKIE_SESSION = "arbore_generator"


def ouvrir_atelier():
    """Ouvre une session d'atelier et rend le cookie qui la porte.

    L'atelier est derrière une session, comme pour l'ouvrier Colab : il n'y a
    pas de voie d'accès sans authentification à ouvrir pour un robot.

    Le cookie est porté À LA MAIN, et non par un `CookieJar`. Celui de
    l'atelier est marqué `Secure`, donc un gestionnaire de cookies conforme
    refuse de le renvoyer sur du HTTP en clair : la connexion réussissait, et
    tous les appels suivants prenaient un 401 « Non authentifié ».

    On ne passe pas pour autant par l'adresse publique en HTTPS : le saut va
    d'un conteneur à l'autre sur le pont interne de Docker et ne quitte jamais
    la machine. `Secure` protège d'une interception sur un réseau non sûr —
    ce n'en est pas un.
    """
    base = os.environ.get("ATELIER_BASE", "").rstrip("/")
    cle = os.environ.get("ATELIER_CLE")
    if not base or not cle:
        raise SystemExit("ATELIER_BASE et ATELIER_CLE sont requis en mode veille")

    corps = json.dumps({"cle": cle}).encode()
    req = urllib.request.Request(f"{base}/api/generator/login", data=corps,
                                 headers={"Content-Type": "application/json",
                                          "Host": hote_atelier()},
                                 method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            if r.status != 200:
                raise SystemExit(f"atelier : connexion refusée ({r.status})")
            biscuit = next(
                (sc.split(";", 1)[0] for sc in (r.headers.get_all("Set-Cookie") or [])
                 if sc.startswith(COOKIE_SESSION + "=")), None)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"atelier : connexion refusée ({e.code}) — clé invalide ?") from e
    except urllib.error.URLError as e:
        # Un conteneur qui meurt sur une trace d'appels se diagnostique mal.
        raise SystemExit(f"atelier injoignable sur {base} : {e.reason}") from e
    if not biscuit:
        raise SystemExit("atelier : connexion acceptée mais aucun cookie de "
                         f"session « {COOKIE_SESSION} » reçu")
    return base, biscuit


def hote_atelier():
    """L'hôte sous lequel se présenter. Voir la note en tête de module."""
    return os.environ.get("ATELIER_HOTE", "generator.arbore.app")


def appeler(biscuit, url, corps=None, methode=None, delai=120):
    """Appel porté par la session. Rend (statut, octets)."""
    donnees = json.dumps(corps).encode() if corps is not None else None
    entetes = {"Host": hote_atelier(), "Cookie": biscuit}
    if donnees:
        entetes["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=donnees, headers=entetes, method=methode)
    try:
        with urllib.request.urlopen(req, timeout=delai) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def rendre_une(tache, sortie):
    """Rend et publie UNE vignette. Rend None si tout va bien, le motif sinon.

    L'adresse de l'API et ses DEUX clés viennent de la TÂCHE : l'ouvrier ne les
    porte pas en configuration, sinon il faudrait lui donner celles de tous les
    environnements pour qu'il puisse en servir un.
    """
    base = tache["api"].rstrip("/")
    entetes = entetes_internes(tache.get("cle"), tache.get("interne"))
    pid = tache["plante"]

    fiches = catalogue(base, entetes)
    fiche = next((p for p in fiches if (p.get("id") or p.get("_id")) == pid), None)
    if not fiche:
        return f"{pid} absente du catalogue de {tache['env']}"

    with tempfile.TemporaryDirectory() as tmp:
        modele = os.path.join(tmp, "m.usdz")
        telecharger_modele(base, entetes, fiche["modelURL"],
                           (fiche.get("versions") or {}).get("model"), modele)

        pose, pot_local = None, None
        pot = fiche.get("pot")
        if pot:
            pot_local = os.path.join(tmp, "pot.usdz")
            telecharger_modele(base, entetes, pot["modelURL"], pot.get("version"), pot_local)
            pose = pot.get("pose") or fiche.get("potPose")

        png = os.path.join(sortie, f"{pid}.png")
        rendre(modele, png, pot_local if pose else None, pose, tache.get("reglages"))

        souci = controler(png)
        if souci:
            return souci

        r = publier(base, entetes, pid, png)
        if not r.get("versionUpdated"):
            return "publiée mais versions.thumbnail non mise à jour"
    return None


def surveiller(pause, sortie):
    """Boucle d'ouvrier : prendre, rendre, livrer.

    Une tâche qui échoue est DÉCLARÉE en échec, jamais abandonnée en silence :
    sans ça elle resterait « en cours » jusqu'à expiration, et l'atelier
    afficherait un travail qui n'avance pas sans dire pourquoi.
    """
    nom = os.environ.get("ARBORE_ENV_NOM", "").strip()
    if not nom:
        raise SystemExit("ARBORE_ENV_NOM est requis : un ouvrier ne sert qu'un environnement")
    atelier, biscuit = ouvrir_atelier()
    os.makedirs(sortie, exist_ok=True)
    print(f"ouvrier de vignettes en veille sur « {nom} », atelier {atelier}", flush=True)

    while True:
        statut, brut = appeler(
            biscuit,
            f"{atelier}/api/generator/vignettes/prendre?env={urllib.parse.quote(nom)}",
            corps={}, methode="POST")
        if statut == 204:
            time.sleep(pause)
            continue
        if statut != 200:
            print(f"prise refusée ({statut}) : {brut[:160].decode(errors='replace')}", flush=True)
            time.sleep(pause)
            continue

        tache = json.loads(brut)
        print(f"→ {tache['plante']} ({tache['env']})", flush=True)
        try:
            motif = rendre_une(tache, sortie)
        except Exception as exc:                          # noqa: BLE001
            motif = str(exc)[:400]

        if motif:
            print(f"  ÉCHEC : {motif}", flush=True)
            appeler(biscuit, f"{atelier}/api/generator/vignettes/{tache['id']}/echec",
                    corps={"reservation": tache["reservation"], "erreur": motif}, methode="POST")
        else:
            print("  publiée", flush=True)
            appeler(biscuit, f"{atelier}/api/generator/vignettes/{tache['id']}/resultat",
                    corps={"reservation": tache["reservation"], "resultat": {"publiee": True}},
                    methode="POST")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plantes", help="identifiants séparés par des virgules")
    ap.add_argument("--rendre-seulement", action="store_true",
                    help="rend et contrôle sans publier")
    ap.add_argument("--sortie", default="/sortie",
                    help="où déposer les PNG en mode rendre-seulement")
    ap.add_argument("--surveiller", action="store_true",
                    help="consomme la file de l'atelier au lieu du catalogue entier")
    ap.add_argument("--pause", type=float, default=20.0,
                    help="secondes entre deux interrogations de la file")
    a = ap.parse_args()

    if a.surveiller:
        return surveiller(a.pause, a.sortie)

    base = os.environ.get("ARBORE_API_BASE", "").rstrip("/")
    if not base:
        raise SystemExit("ARBORE_API_BASE est requis")

    entetes = entetes_internes(os.environ.get("ARBORE_API_KEY"),
                               os.environ.get("ARBORE_INTERNAL_KEY"))
    plantes = catalogue(base, entetes)
    if a.plantes:
        voulus = {x.strip() for x in a.plantes.split(",") if x.strip()}
        plantes = [p for p in plantes if p.get("id") in voulus or p.get("_id") in voulus]

    print(f"{len(plantes)} plante(s) à rendre")
    produites, echecs = [], []
    os.makedirs(a.sortie, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        pot_local = None
        for p in plantes:
            pid = p.get("id") or p.get("_id")
            nom = p.get("name", pid)
            try:
                modele = os.path.join(tmp, "m.usdz")
                telecharger_modele(base, entetes, p["modelURL"],
                                   (p.get("versions") or {}).get("model"), modele)

                pose = None
                pot = p.get("pot")
                if pot:
                    if pot_local is None:
                        pot_local = os.path.join(tmp, "pot.usdz")
                        telecharger_modele(base, entetes, pot["modelURL"],
                                           pot.get("version"), pot_local)
                    # La pose vient du backend quand il la sert ; sinon on ne
                    # compose pas de pot plutôt que d'en inventer la règle.
                    pose = pot.get("pose") or p.get("potPose")

                png = os.path.join(a.sortie, f"{pid}.png")
                rendre(modele, png, pot_local if pose else None, pose)

                souci = controler(png)
                if souci:
                    echecs.append((nom, souci))
                    continue

                if not a.rendre_seulement:
                    r = publier(base, entetes, pid, png)
                    if not r.get("versionUpdated"):
                        echecs.append((nom, "publiée mais versions.thumbnail non mise à jour"))
                        continue
                produites.append(nom)
            except Exception as exc:                      # noqa: BLE001
                echecs.append((nom, str(exc)[:160]))

    print(f"\nproduites : {len(produites)}    échecs : {len(echecs)}")
    for nom, raison in echecs:
        print(f"  ÉCHEC  {nom} : {raison}")
    # Un échec partiel est un échec : servir un catalogue à deux rendus est
    # pire que ne rien changer.
    return 1 if echecs else 0


if __name__ == "__main__":
    sys.exit(main())
