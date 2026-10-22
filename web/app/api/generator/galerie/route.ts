import { NextRequest, NextResponse } from 'next/server';

import { galerie } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/**
 * Tout ce que l'atelier a produit, tranché ou non.
 *
 * La revue ne montre que ce qui attend un jugement. Cette route montre le
 * reste : une plante validée il y a trois semaines reste consultable, et le
 * décalage entre son verdict et la coupe réellement sur le volume devient
 * visible.
 */
export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  return NextResponse.json({ plantes: galerie() });
}
