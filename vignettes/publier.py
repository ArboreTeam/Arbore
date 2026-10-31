"""Rend et publie les vignettes du catalogue. (#694, #695)

Ne parle QU'À L'API. Il ignore où les fichiers vivent, et c'est délibéré.

## Pourquoi pas de montage de répertoire

La prod sert ses assets depuis `r2`, dev depuis `filesystem`. Un job qui
monterait des répertoires ne fonctionnerait tout simplement pas sur la prod.

Et le 30 octobre, manipuler les fichiers en direct a produit **54 empreintes
fausses sur 123** : deux répertoires de vignettes existent sur le VPS, un seul
est monté dans le conteneur. Connaître la disposition du stockage, c'est
pouvoir s'y tromper.

En passant par `POST /models/thumbnails/:plantId`, c'est le backend qui écrit
et qui recalcule `versions.thumbnail` sur les octets qu'il vient d'écrire
(#687). Publier une empreinte qui ment devient impossible, pas seulement
improbable.

## Ce qu'il lui faut

    ARBORE_API_BASE      https://api-dev.arbore.app
    ARBORE_API_KEY       clé d'API
    ARBORE_FIREBASE_KEY  clé web du projet, pour ouvrir la session
    ARBORE_ADMIN_TOKEN   jeton d'un compte de service ayant le rôle admin
"""
import argparse
import json
import os
import struct
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

LARGEUR, HAUTEUR = 720, 900
MARQUEUR_RVB = (94, 28, 186)
POIDS_PLANCHER = 50_000          # en dessous, le rendu est vide ou tronqué
TOLERANCE_MARQUEUR = 12


def http(url, entetes, corps=None, methode=None, delai=300):
    req = urllib.request.Request(url, data=corps, headers=entetes, method=methode)
    with urllib.request.urlopen(req, timeout=delai) as r:
        return r.status, r.read()


def jeton(base_env):
    """Jeton d'authentification. Un jeton admin couvre aussi les lectures."""
    fourni = os.environ.get("ARBORE_ADMIN_TOKEN")
    if fourni:
        return fourni
    cle = os.environ.get("ARBORE_FIREBASE_KEY")
    if not cle:
        raise SystemExit("ni ARBORE_ADMIN_TOKEN ni ARBORE_FIREBASE_KEY — "
                         "le job ne peut ni lire le catalogue ni publier")
    # Session anonyme : suffisante pour LIRE, jamais pour publier. Utile pour
    # une passe de contrôle qui rend sans envoyer.
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={cle}"
    _, corps = http(url, {"Content-Type": "application/json"},
                    b'{"returnSecureToken":true}', "POST")
    return json.loads(corps)["idToken"]


def catalogue(base, entetes):
    statut, corps = http(f"{base}/plants", entetes)
    if statut != 200:
        raise SystemExit(f"GET /plants a rendu {statut}")
    return json.loads(corps)


def dimensions_png(donnees):
    if donnees[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", donnees[16:24])


def coins_marques(chemin):
    """Vérifie le marqueur sans dépendance d'image, en décodant le PNG.

    Ce contrôle n'est pas une précaution de confort. Une vignette sans marqueur
    est téléchargée par l'app, **examinée, refusée**, et les cartes gardent
    l'ancienne image — sans que rien ne le signale. C'est exactement ce qui est
    arrivé le 30 octobre à 123 fichiers par ailleurs irréprochables.
    """
    import zlib
    d = open(chemin, "rb").read()
    pos, largeur, canaux, idat = 8, None, None, b""
    while pos < len(d):
        lg = struct.unpack(">I", d[pos:pos + 4])[0]
        typ = d[pos + 4:pos + 8]
        corps = d[pos + 8:pos + 8 + lg]
        if typ == b"IHDR":
            largeur, _, prof, couleur = struct.unpack(">IIBB", corps[:10])
            if prof != 8 or couleur not in (2, 6):
                return False
            canaux = 3 if couleur == 2 else 4
        elif typ == b"IDAT":
            idat += corps
        elif typ == b"IEND":
            break
        pos += 12 + lg
    brut = zlib.decompress(idat)
    if not brut or brut[0] != 0:          # 1re ligne non filtrée attendue
        return False
    r, v, b = brut[1], brut[2], brut[3]
    return all(abs(a - b_) < TOLERANCE_MARQUEUR
               for a, b_ in zip((r, v, b), MARQUEUR_RVB))


def telecharger_modele(base, entetes, fichier, version, dest):
    url = f"{base}/models/{fichier}"
    if version:
        url += f"?v={version}"
    statut, corps = http(url, entetes)
    if statut != 200:
        raise RuntimeError(f"GET {fichier} a rendu {statut}")
    open(dest, "wb").write(corps)
    return len(corps)


def rendre(modele, sortie, pot=None, pose=None):
    cmd = ["blender", "--background", "--factory-startup",
           "--python", "/app/rendre.py", "--",
           "--modele", modele, "--sortie", sortie]
    if pot and pose:
        cmd += ["--pot", pot, "--pose", json.dumps(pose)]
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
    statut, reponse = http(f"{base}/models/thumbnails/{plant_id}", e, corps, "POST")
    if statut != 200:
        raise RuntimeError(f"POST a rendu {statut} : {reponse[:160].decode(errors='replace')}")
    return json.loads(reponse)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plantes", help="identifiants séparés par des virgules")
    ap.add_argument("--rendre-seulement", action="store_true",
                    help="rend et contrôle sans publier")
    ap.add_argument("--sortie", default="/sortie",
                    help="où déposer les PNG en mode rendre-seulement")
    a = ap.parse_args()

    base = os.environ.get("ARBORE_API_BASE", "").rstrip("/")
    cle = os.environ.get("ARBORE_API_KEY")
    if not base or not cle:
        raise SystemExit("ARBORE_API_BASE et ARBORE_API_KEY sont requis")

    entetes = {"X-API-Key": cle, "Authorization": "Bearer " + jeton(base)}
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
