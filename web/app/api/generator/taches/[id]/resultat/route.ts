import { NextRequest, NextResponse } from 'next/server';

import { livrer } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { id } = await ctx.params;
  const c = await corps<{ reservation?: string } & Record<string, unknown>>(req);
  if (!c?.reservation) {
    return NextResponse.json({ error: 'reservation requise' }, { status: 400 });
  }
  const { reservation, ...resultat } = c;
  const accepte = await livrer(id, reservation, resultat);
  if (!accepte) {
    // 409 et non 404 : la tâche existe, c'est la réservation qui a expiré et
    // la tâche a été reprise. L'ouvrier doit le distinguer d'une erreur de
    // chemin, et jeter son résultat sans réessayer.
    return NextResponse.json({ error: 'reservation perimee' }, { status: 409 });
  }
  return NextResponse.json({ ok: true });
}
