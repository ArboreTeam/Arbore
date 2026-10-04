// Service des artefacts de l'atelier : aperçus PNG et GLB coupés.
//
// Ces fichiers vivent sur le volume monté, hors de `public/` — Next ne peut
// donc pas les servir statiquement, et c'est tant mieux : ils doivent rester
// derrière la session, comme le reste de l'atelier.
import { createReadStream, statSync } from 'node:fs';
import { Readable } from 'node:stream';
import { NextRequest, NextResponse } from 'next/server';

import { cheminArtefact } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

// Liste blanche d'extensions, et non liste noire : on sert des aperçus et des
// maillages, rien d'autre. Un `.json` ou un `.env` qui traînerait dans le
// dossier d'une plante ne doit pas pouvoir sortir par cette route.
const TYPES: Record<string, string> = {
  '.png': 'image/png',
  '.glb': 'model/gltf-binary',
};

export async function GET(
  req: NextRequest,
  ctx: { params: Promise<{ plante: string; fichier: string }> },
) {
  if (!bonHote(req)) return introuvable();
  const { plante, fichier } = await ctx.params;

  const nom = decodeURIComponent(fichier);
  const ext = nom.slice(nom.lastIndexOf('.')).toLowerCase();
  const type = TYPES[ext];
  if (!type) return introuvable();

  let chemin: string;
  try {
    // `cheminArtefact` valide le nom de plante et refuse tout séparateur ou
    // `..` dans le fichier. C'est la seule fonction qui connaît la disposition
    // du volume, et la seule porte par laquelle un chemin se construit ici.
    chemin = cheminArtefact(plante, nom);
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

  // En flux, pas en mémoire : un GLB pèse 30 à 42 Mo, et les charger
  // entièrement pour les recracher ferait tenir trois requêtes simultanées
  // dans la limite de 768 Mo du conteneur.
  const flux = Readable.toWeb(createReadStream(chemin)) as ReadableStream<Uint8Array>;

  return new NextResponse(flux, {
    headers: {
      'Content-Type': type,
      'Content-Length': String(taille),
      // `no-store` et non une durée de vie : un nom d'aperçu est stable
      // (`apercu_000.png`) alors que son CONTENU change à chaque relance sur
      // une graine neuve. Mis en cache, la revue montrerait le maillage qu'on
      // vient de rejeter — et on invaliderait une plante sur la foi d'une
      // image périmée.
      'Cache-Control': 'no-store, must-revalidate',
      'X-Content-Type-Options': 'nosniff',
      'Content-Disposition': `inline; filename="${nom}"`,
    },
  });
}
