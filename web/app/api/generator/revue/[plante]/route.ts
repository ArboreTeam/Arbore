import { NextRequest, NextResponse } from 'next/server';

import { trancher } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/**
 * Verdict humain.
 *
 * Une invalidation redépose une tâche sans graine imposée : c'est le seul
 * chemin qui remonte vers le GPU, et il ne sert qu'au défaut qu'aucune
 * métrique ne voit — la géométrie inventée mais plausible.
 */
export async function POST(req: NextRequest, ctx: { params: Promise<{ plante: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { plante } = await ctx.params;
  const c = await corps<{ valide?: boolean; coupe?: string }>(req);
  if (typeof c?.valide !== 'boolean') {
    return NextResponse.json({ error: 'valide requis' }, { status: 400 });
  }
  const verdict = await trancher(plante, c.valide, c.coupe);
  return NextResponse.json({ ok: true, verdict });
}
