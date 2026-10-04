import { NextRequest, NextResponse } from 'next/server';

import { historique, noterGraine } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function GET(req: NextRequest, ctx: { params: Promise<{ plante: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { plante } = await ctx.params;
  return NextResponse.json({ graines: historique(plante) });
}

/**
 * Consigne une graine tirée.
 *
 * Appelée AVANT la génération. L'écriture doit donc être immédiate : si
 * l'ouvrier meurt pendant son calcul, la graine doit rester brûlée, sans quoi
 * la relance la retirerait et reproduirait la panne — `run()` étant
 * déterministe à graine fixée.
 */
export async function POST(req: NextRequest, ctx: { params: Promise<{ plante: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { plante } = await ctx.params;
  const c = await corps<{ graine?: number }>(req);
  if (typeof c?.graine !== 'number' || !Number.isFinite(c.graine)) {
    return NextResponse.json({ error: 'graine requise' }, { status: 400 });
  }
  const total = await noterGraine(plante, Math.trunc(c.graine));
  return NextResponse.json({ ok: true, total });
}
