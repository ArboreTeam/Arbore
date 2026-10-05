// Images d'entrée : dépôt, service et retrait.
//
// Elles vivaient sur Drive pendant le spike, et `tache.image` portait un chemin
// Colab. L'atelier ne pouvait alors pas déposer de tâche — il aurait écrit un
// chemin qu'il ne pouvait ni voir ni vérifier, et la faute ne se serait révélée
// qu'au moment où l'ouvrier prend la tâche, 165 s de GPU plus tard.
//
// Sur le volume, l'atelier les voit. C'est ce qui lui rend le dépôt.
import { createReadStream, statSync } from 'node:fs';
import { Readable } from 'node:stream';
import { NextRequest, NextResponse } from 'next/server';

import { cheminSource, marquerSansPot, supprimerSource } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';
import { recevoirMorceau } from '@/lib/generator/televersement';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

// Une source détourée reste une image : quelques mégaoctets, pas des dizaines.
// Un plafond bas ici attrape tôt le fichier déposé par erreur.
const MAX_OCTETS = 32 * 1024 * 1024;

const TYPES: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
};

function resoudre(fichier: string): { chemin: string; type: string } | null {
  const nom = decodeURIComponent(fichier);
  const type = TYPES[nom.slice(nom.lastIndexOf('.')).toLowerCase()];
  if (!type) return null;
  try {
    return { chemin: cheminSource(nom), type };
  } catch {
    return null;
  }
}

/** Sert l'image. L'ouvrier la télécharge, l'atelier l'affiche en vignette. */
export async function GET(req: NextRequest, ctx: { params: Promise<{ fichier: string }> }) {
  if (!bonHote(req)) return introuvable();
  const r = resoudre((await ctx.params).fichier);
  if (!r) return introuvable();

  let taille: number;
  try {
    const st = statSync(r.chemin);
    if (!st.isFile()) return introuvable();
    taille = st.size;
  } catch {
    return introuvable();
  }

  return new NextResponse(
    Readable.toWeb(createReadStream(r.chemin)) as ReadableStream<Uint8Array>,
    {
      headers: {
        'Content-Type': r.type,
        'Content-Length': String(taille),
        // Même raison que pour les aperçus : le nom est stable, le contenu peut
        // changer quand on remplace une source par un meilleur détourage.
        'Cache-Control': 'no-store, must-revalidate',
        'X-Content-Type-Options': 'nosniff',
      },
    },
  );
}

export async function PUT(req: NextRequest, ctx: { params: Promise<{ fichier: string }> }) {
  if (!bonHote(req)) return introuvable();
  const r = resoudre((await ctx.params).fichier);
  if (!r) return introuvable();
  return recevoirMorceau(req, r.chemin, MAX_OCTETS);
}

/**
 * Retire une source ET ses tâches en attente.
 *
 * Les artefacts déjà produits ne sont PAS touchés : une plante dont on retire
 * l'image garde ses aperçus et son verdict, qui restent la trace de ce qui a
 * été jugé.
 *
 * Refusé tant qu'une tâche est en cours — 409 et non 404 : la source existe,
 * c'est le moment qui ne convient pas, et réessayer plus tard marchera.
 */
export async function DELETE(req: NextRequest, ctx: { params: Promise<{ fichier: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { fichier } = await ctx.params;
  const r = await supprimerSource(decodeURIComponent(fichier));
  if (r.ok) return NextResponse.json({ ok: true, tachesRetirees: r.tachesRetirees });
  if (r.raison === 'tache_en_cours') {
    return NextResponse.json(
      { error: 'une génération est en cours sur cette plante' }, { status: 409 },
    );
  }
  return introuvable();
}

/**
 * Marque la source comme étant sans pot, ou le défait.
 *
 * L'ouvrier saute alors la détection — quelques secondes de CPU par plante — et
 * la plante n'entre pas dans le périmètre des pots personnalisés. Un palmier
 * hors pot a reçu une proposition de coupe sur le premier lot : la question
 * n'aurait pas dû être posée.
 */
export async function PATCH(req: NextRequest, ctx: { params: Promise<{ fichier: string }> }) {
  if (!bonHote(req)) return introuvable();
  const nom = decodeURIComponent((await ctx.params).fichier);
  try {
    cheminSource(nom);
  } catch {
    return introuvable();
  }
  const c = await corps<{ sansPot?: boolean }>(req);
  if (typeof c?.sansPot !== 'boolean') {
    return NextResponse.json({ error: 'sansPot requis' }, { status: 400 });
  }
  await marquerSansPot(nom, c.sansPot);
  return NextResponse.json({ ok: true, sansPot: c.sansPot });
}
