"""Cuisson exacte : projette chaque texel sur le triangle source le plus proche
et lit la texture d'origine a sa position barycentrique.

Lire une couleur par sommet source perd le detail haute frequence (les panachures
d'une feuille), et monter l'atlas de 1024 a 2048 n'y change rien puisque la
limite est le maillage, pas l'image.
"""
from __future__ import annotations

import numpy as np


def adjacence(F: np.ndarray, n: int, plafond: int = 8):
    """Faces incidentes a chaque sommet, en tableau rectangulaire (-1 = vide)."""
    coins = np.repeat(np.arange(len(F)), 3)
    som = F.ravel()
    ordre = np.argsort(som, kind="stable")
    som, coins = som[ordre], coins[ordre]
    debuts = np.searchsorted(som, np.arange(n + 1))
    nb = np.minimum(np.diff(debuts), plafond)
    tab = np.full((n, plafond), -1, np.int64)
    for k in range(plafond):
        pris = nb > k
        tab[pris, k] = coins[debuts[:-1][pris] + k]
    return tab


def plus_proche_sur_triangles(P, A, B, C):
    """Point le plus proche de P sur le triangle ABC, en coordonnees barycentriques.
    Algorithme d'Ericson, Real-Time Collision Detection, section 5.1.5."""
    ab, ac, ap = B - A, C - A, P - A
    d1 = np.einsum("...i,...i->...", ab, ap)
    d2 = np.einsum("...i,...i->...", ac, ap)
    bp = P - B
    d3 = np.einsum("...i,...i->...", ab, bp)
    d4 = np.einsum("...i,...i->...", ac, bp)
    cp = P - C
    d5 = np.einsum("...i,...i->...", ab, cp)
    d6 = np.einsum("...i,...i->...", ac, cp)
    va = d3 * d6 - d5 * d4
    vb = d5 * d2 - d1 * d6
    vc = d1 * d4 - d3 * d2
    denom = np.where(np.abs(va + vb + vc) < 1e-20, 1e-20, va + vb + vc)
    v = np.clip(vb / denom, 0, 1)
    w = np.clip(vc / denom, 0, 1)

    # retombees sur les sommets et les aretes
    v = np.where((d1 <= 0) & (d2 <= 0), 0.0, v)
    w = np.where((d1 <= 0) & (d2 <= 0), 0.0, w)
    sur_ab = (vc <= 0) & (d1 >= 0) & (d3 <= 0)
    t_ab = np.clip(d1 / np.where(d1 - d3 == 0, 1e-20, d1 - d3), 0, 1)
    v = np.where(sur_ab, t_ab, v)
    w = np.where(sur_ab, 0.0, w)
    sur_ac = (vb <= 0) & (d2 >= 0) & (d6 <= 0)
    t_ac = np.clip(d2 / np.where(d2 - d6 == 0, 1e-20, d2 - d6), 0, 1)
    v = np.where(sur_ac, 0.0, v)
    w = np.where(sur_ac, t_ac, w)
    sur_bc = (va <= 0) & (d4 - d3 >= 0) & (d5 - d6 >= 0)
    t_bc = np.clip((d4 - d3) / np.where((d4 - d3) + (d5 - d6) == 0, 1e-20,
                                        (d4 - d3) + (d5 - d6)), 0, 1)
    v = np.where(sur_bc, 1.0 - t_bc, v)
    w = np.where(sur_bc, t_bc, w)

    u = 1.0 - v - w
    Q = A + v[..., None] * ab + w[..., None] * ac
    d = np.einsum("...i,...i->...", Q - P, Q - P)
    return d, np.stack([u, v, w], -1)


def bilineaire(img_a: np.ndarray, uv: np.ndarray) -> np.ndarray:
    h, w = img_a.shape[:2]
    x = (uv[:, 0] % 1.0) * w - 0.5
    y = (1.0 - uv[:, 1] % 1.0) * h - 0.5
    x0 = np.floor(x).astype(np.int32); y0 = np.floor(y).astype(np.int32)
    fx = (x - x0)[:, None]; fy = (y - y0)[:, None]
    x0c = np.clip(x0, 0, w - 1); x1c = np.clip(x0 + 1, 0, w - 1)
    y0c = np.clip(y0, 0, h - 1); y1c = np.clip(y0 + 1, 0, h - 1)
    a = img_a[y0c, x0c] * (1 - fx) + img_a[y0c, x1c] * fx
    b = img_a[y1c, x0c] * (1 - fx) + img_a[y1c, x1c] * fx
    return a * (1 - fy) + b * fy


def couleurs(pts, Vsrc, Fsrc, uv_src, img_a, arbre, adj, lot=200_000):
    """Couleur de chaque point, lue sur le triangle source le plus proche."""
    sortie = np.empty((len(pts), 3), np.uint8)
    for i in range(0, len(pts), lot):
        p = pts[i:i + lot]
        _, graine = arbre.query(p, workers=-1)
        faces = adj[graine]                       # (n, plafond)
        vide = faces < 0
        f = Fsrc[np.where(vide, 0, faces)]        # (n, plafond, 3)
        d, bary = plus_proche_sur_triangles(
            p[:, None, :], Vsrc[f[..., 0]], Vsrc[f[..., 1]], Vsrc[f[..., 2]])
        d = np.where(vide, np.inf, d)
        k = d.argmin(1)
        n = np.arange(len(p))
        uv = np.einsum("ij,ijk->ik", bary[n, k], uv_src[f[n, k]])
        sortie[i:i + lot] = bilineaire(img_a, uv).round().clip(0, 255).astype(np.uint8)
    return sortie
