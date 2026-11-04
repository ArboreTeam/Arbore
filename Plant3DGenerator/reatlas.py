#!/usr/bin/env python3
"""Reconstruit un maillage dense a atlas fragmente en bas-polygone a atlas propre.

Les maillages de reconstruction portent un atlas decoupe en micro-chartes :
2,28 sommets par position distincte. Un decimateur qui preserve les coordonnees
de texture verrouille chaque couture et plafonne a 3x, quelle que soit l'erreur
autorisee. On decime donc librement, on deplie un atlas neuf, et on recuit la
couleur en projetant chaque texel sur le triangle source le plus proche.

Le materiau sort en double face : le maillage est une membrane a deux peaux, et
apres decimation les faces gardent des enroulements opposes, ce qui annule la
normale lissee et fait rendre noir un quart de la surface.
"""
from __future__ import annotations

import io
import os
import sys
import time

import reatlas_bake as bake
import fast_simplification
import numpy as np
import trimesh
import xatlas
from PIL import Image
from scipy.ndimage import distance_transform_edt
from scipy.spatial import cKDTree


def charger(chemin: str):
    m = trimesh.load(chemin, force="mesh", process=False)
    return (np.asarray(m.vertices, np.float64),
            np.asarray(m.faces, np.int64),
            np.asarray(m.visual.uv, np.float64),
            m.visual.material.baseColorTexture.convert("RGB"))


def normales_non_orientees(V: np.ndarray, F: np.ndarray) -> np.ndarray:
    """Normale par sommet, calculee AU SIGNE PRES.

    La source a 42,6 % de faces a contre-sens (#638). Moyenner les normales des
    faces incidentes les fait s'annuler et l'ombrage s'aplatit. On moyenne donc
    les tenseurs n.nT, invariants au signe, et on prend le vecteur propre
    dominant. Le materiau etant en double face, le signe retenu est sans effet.
    """
    g = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    aire = np.linalg.norm(g, axis=1, keepdims=True)
    g = np.divide(g, aire, out=np.zeros_like(g), where=aire > 1e-20)
    tenseur = np.einsum("fi,fj->fij", g, g) * aire[:, :, None]
    acc = np.zeros((len(V), 3, 3))
    for k in range(3):
        np.add.at(acc, F[:, k], tenseur)
    _, vecteurs = np.linalg.eigh(acc)
    N = vecteurs[:, :, 2]                       # vecteur propre dominant
    # oriente chaque normale vers la face incidente la plus grande, par coherence locale
    ref = np.zeros((len(V), 3))
    for k in range(3):
        np.add.at(ref, F[:, k], g * aire)
    N *= np.where(np.einsum("ij,ij->i", N, ref) < 0, -1.0, 1.0)[:, None]
    return N


def rasteriser(F: np.ndarray, P: np.ndarray, taille: int):
    """Texels couverts par l'atlas : leur position 3D, leur normale, et leur
    index dans l'image.

    La normale sert à la cuisson : sans elle, un texel pris sur une fronde se
    projette parfois sur le tronc, dont le sommet est plus proche.
    """
    pts, dest, norms = [], [], []
    for t in range(len(F)):
        tri = F[t]
        p = P[tri]
        x0, y0 = np.maximum(np.floor(p.min(0)).astype(int) - 1, 0)
        x1, y1 = np.minimum(np.ceil(p.max(0)).astype(int) + 1, taille)
        if x1 <= x0 or y1 <= y0:
            continue
        d = p[1:] - p[0]
        det = d[0, 0] * d[1, 1] - d[0, 1] * d[1, 0]
        if abs(det) < 1e-12:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        q = np.stack([xs.ravel(), ys.ravel()], 1)
        r = q - p[0]
        b1 = (r[:, 0] * d[1, 1] - r[:, 1] * d[1, 0]) / det
        b2 = (d[0, 0] * r[:, 1] - d[0, 1] * r[:, 0]) / det
        b0 = 1.0 - b1 - b2
        dedans = (b0 >= -1e-6) & (b1 >= -1e-6) & (b2 >= -1e-6)
        if not dedans.any():
            continue
        yield_b = np.stack([b0[dedans], b1[dedans], b2[dedans]], 1)
        pts.append(yield_b @ VERTS[tri])
        g = np.cross(VERTS[tri[1]] - VERTS[tri[0]], VERTS[tri[2]] - VERTS[tri[0]])
        ng = np.linalg.norm(g)
        norms.append(np.tile(g / ng if ng > 1e-20 else g, (int(dedans.sum()), 1)))
        qq = q[dedans].astype(int)
        dest.append(qq[:, 1] * taille + qq[:, 0])
    return np.concatenate(pts), np.concatenate(norms), np.concatenate(dest)


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    cible = int(sys.argv[3]) if len(sys.argv) > 3 else 40000
    taille = int(sys.argv[4]) if len(sys.argv) > 4 else 1024
    t0 = time.time()

    V, F, uv_src, img = charger(src)
    print(f"  source   {len(V):>9,} sommets  {len(F):>9,} triangles  texture {img.size[0]}")

    Vd, Fd = fast_simplification.simplify(
        V.astype(np.float32), F.astype(np.int32), target_count=min(cible, len(F) - 1))
    print(f"  decime   {len(Vd):>9,} sommets  {len(Fd):>9,} triangles  ({time.time()-t0:.1f}s)")

    opt = xatlas.ChartOptions()
    opt.max_cost = 8.0          # defaut 2.0 : accepte plus de distorsion, donc coud moins
    opt.max_iterations = 2
    atlas = xatlas.Atlas()
    atlas.add_mesh(Vd.astype(np.float32), Fd.astype(np.uint32))
    atlas.generate(chart_options=opt)
    vm, idx, uv = atlas.get_mesh(0)
    Vn, idx, uv = Vd[vm], np.asarray(idx, np.int64), np.asarray(uv, np.float64)
    print(f"  deplie   {len(Vn):>9,} sommets  {len(idx):>9,} triangles  ({time.time()-t0:.1f}s)")

    global VERTS
    VERTS = Vn
    pts, norms, dest = rasteriser(idx, uv * taille, taille)
    coul = bake.couleurs(pts, norms, V, F, uv_src, np.asarray(img, np.float64),
                         cKDTree(V), bake.adjacence(F, len(V)))
    print(f"  cuit     {len(pts):>9,} texels   atlas {taille}        ({time.time()-t0:.1f}s)")

    plan = np.zeros((taille * taille, 3), np.uint8)
    masque = np.zeros(taille * taille, bool)
    plan[dest] = coul
    masque[dest] = True
    # dilatation : sans marge, le filtrage bilineaire tire du noir aux coutures
    _, (iy, ix) = distance_transform_edt(~masque.reshape(taille, taille), return_indices=True)
    tex = Image.fromarray(plan.reshape(taille, taille, 3)[iy, ix])

    tampon = io.BytesIO()
    tex.save(tampon, format="JPEG", quality=85, optimize=True)
    tampon.seek(0)
    tex = Image.open(tampon)    # porte .format = JPEG, que trimesh respecte

    # materiau explicite : trimesh pose sinon un baseColorFactor de 0,4 qui
    # assombrit la texture de 60 %, et un metallicFactor de 1 qui la noircit
    mat = trimesh.visual.material.PBRMaterial(
        baseColorTexture=tex,
        baseColorFactor=[255, 255, 255, 255],
        metallicFactor=0.0,
        roughnessFactor=1.0,   # la source vaut 1,0 (carte MR : vert a 1,00)
        doubleSided=True,       # membrane : sans cela un quart des faces rend noir
    )
    # trimesh RETOURNE v en lisant un GLB — `uv_trimesh = 1 - uv_fichier` — et
    # le retourne donc à nouveau en écrivant. Or l'atlas a été rasterisé avec
    # le v de xatlas, ligne = v * taille. Sans cette compensation, le fichier
    # porte `1 - v` et le moteur lit l'atlas à l'envers : les couleurs restent
    # justes mais se posent au mauvais endroit, ce qui donne une statistique
    # d'aire identique à la source et un rendu marbré.
    uv = np.column_stack([uv[:, 0], 1.0 - uv[:, 1]])

    maille = trimesh.Trimesh(vertices=Vn, faces=idx, process=False)
    # sans normales explicites, USD ombre a plat : a 40 000 triangles la plante
    # est facettee et plus claire que la source
    maille.vertex_normals = normales_non_orientees(Vn, idx)
    maille.visual = trimesh.visual.TextureVisuals(uv=uv, material=mat)
    maille.export(out)
    print(f"  ecrit    {os.path.getsize(out)/1e6:.2f} Mo  ({time.time()-t0:.1f}s)")


if __name__ == "__main__":
    main()
