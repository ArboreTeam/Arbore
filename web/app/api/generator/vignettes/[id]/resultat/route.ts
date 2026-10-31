import { NextRequest, NextResponse } from 'next/server';

import { livrerVignette } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { id } = await ctx.params;
  const c = await corps<{ reservation?: string; resultat?: Record<string, unknown> }>(req);
  if (!c?.reservation) {
    return NextResponse.json({ error: 'réservation requise' }, { status: 400 });
  }
  const ok = await livrerVignette(id, c.reservation, c.resultat ?? {});
  // 409 et non 404 : la tâche existe peut-être, mais elle a été reprise. Le
  // résultat arrive trop tard et on le jette — un rendu perdu vaut mieux qu'un
  // écrasement du travail de celui qui a repris.
  return ok ? NextResponse.json({ ok: true }) : NextResponse.json({ ok: false }, { status: 409 });
}
