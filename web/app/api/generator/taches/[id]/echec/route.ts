import { NextRequest, NextResponse } from 'next/server';

import { echouer } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { id } = await ctx.params;
  const c = await corps<{ reservation?: string; erreur?: string }>(req);
  if (!c?.reservation) {
    return NextResponse.json({ error: 'reservation requise' }, { status: 400 });
  }
  const ok = await echouer(id, c.reservation, c.erreur ?? 'inconnue');
  return ok
    ? NextResponse.json({ ok: true })
    : NextResponse.json({ error: 'reservation perimee' }, { status: 409 });
}
