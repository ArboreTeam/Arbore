// Bibliothèque de pots : dépôt, service et retrait.
//
// Un pot ne vient pas des plantes générées — ceux que `candidats_coupe` sépare
// sont des sous-produits. Ceux-ci sont sourcés ou générés à part, et le but est
// de pouvoir choisir lequel va sous quelle plante.
//
// Le rebord est mesuré À L'INGESTION, côté serveur, sur le fichier reçu. Un pot
// qu'on ne sait pas poser est refusé tout de suite plutôt que rangé dans la
// bibliothèque pour être découvert inutilisable à l'essayage.
import { createReadStream, statSync, unlinkSync } from 'node:fs';
import { Readable } from 'node:stream';
import { NextRequest, NextResponse } from 'next/server';

import { cheminPot, noterPot, supprimerPot } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';
import { mesurerRebord } from '@/lib/generator/pot';
import { profilerPot } from '@/lib/generator/profil';
import { recevoirMorceau } from '@/lib/generator/televersement';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

// Un pot est un objet simple : quelques dizaines de milliers de triangles
// suffisent. Le plafond attrape tôt le maillage déposé par erreur.
const MAX_OCTETS = 64 * 1024 * 1024;

export async function GET(req: NextRequest, ctx: { params: Promise<{ fichier: string }> }) {
  if (!bonHote(req)) return introuvable();
  let chemin: string;
  try {
    chemin = cheminPot(decodeURIComponent((await ctx.params).fichier));
  } catch {
    return introuvable();
  }

  let taille: number;
  try {
    const st = statSync(chemin);
    if (!st.isFile()) return introuvable();
    taille = st.size;
  } catch {
    return introuvable();
  }

  return new NextResponse(
    Readable.toWeb(createReadStream(chemin)) as ReadableStream<Uint8Array>,
    {
      headers: {
        'Content-Type': 'model/gltf-binary',
        'Content-Length': String(taille),
        'Cache-Control': 'no-store, must-revalidate',
        'X-Content-Type-Options': 'nosniff',
      },
    },
  );
}

export async function PUT(req: NextRequest, ctx: { params: Promise<{ fichier: string }> }) {
  if (!bonHote(req)) return introuvable();
  const nom = decodeURIComponent((await ctx.params).fichier);
  let chemin: string;
  try {
    chemin = cheminPot(nom);
  } catch {
    return introuvable();
  }

  const reponse = await recevoirMorceau(req, chemin, MAX_OCTETS);
  // Seul le DERNIER morceau publie le fichier : avant, il n'y a rien à mesurer.
  if (reponse.status !== 201) return reponse;

  const rebord = mesurerRebord(chemin);
  if (!rebord) {
    // On retire le fichier : laisser un GLB non mesurable sur le volume
    // donnerait une bibliothèque où certains pots ne se posent pas, sans que
    // rien ne distingue les bons des mauvais.
    try {
      unlinkSync(chemin);
    } catch {
      // Déjà parti.
    }
    return NextResponse.json(
      { error: 'rebord non mesurable : ce maillage ne ressemble pas à un pot' },
      { status: 422 },
    );
  }

  // Le profil radial se prend dans la même lecture logique que le rebord : il
  // sert au contrôle de pose, et le mesurer ici évite que le premier affichage
  // de la bibliothèque ait à relire tous les GLB pour rattraper son retard.
  const pot = await noterPot({
    fichier: nom, ...rebord,
    profil: profilerPot(chemin, rebord) ?? undefined,
    octets: statSync(chemin).size,
    depose: Date.now(),
  });
  return NextResponse.json({ ok: true, pot }, { status: 201 });
}

export async function DELETE(req: NextRequest, ctx: { params: Promise<{ fichier: string }> }) {
  if (!bonHote(req)) return introuvable();
  const ok = await supprimerPot(decodeURIComponent((await ctx.params).fichier));
  return ok ? NextResponse.json({ ok: true }) : introuvable();
}
