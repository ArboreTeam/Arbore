import { NextRequest, NextResponse } from 'next/server';

import { retenirCoupe } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/**
 * Retenir une coupe sur une plante déjà validée.
 *
 * Distincte de la route de verdict, parce que ce n'en est pas un : le jugement
 * humain sur le maillage a été rendu, et seule la coupe du pot reste à nommer.
 * Les faire passer par la même porte obligerait à rejouer le verdict pour
 * corriger une donnée qui n'en fait pas partie.
 *
 * `coupe: null` consigne le choix inverse — garder le maillage entier avec son
 * pot d'origine. C'est une décision, pas une absence de décision, et c'est ce
 * qui retire la plante de la file.
 */
export async function POST(req: NextRequest, ctx: { params: Promise<{ plante: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { plante } = await ctx.params;
  const c = await corps<{ coupe?: string | null }>(req);

  // `undefined` et `null` ne disent pas la même chose : le premier est un corps
  // mal formé, le second le choix explicite de ne retenir aucune coupe.
  if (c === null || !('coupe' in c)) {
    return NextResponse.json(
      { error: 'coupe requise : un nom de fichier, ou null pour aucune' }, { status: 400 },
    );
  }
  const demande = c.coupe;
  if (demande !== null && typeof demande !== 'string') {
    return NextResponse.json({ error: 'coupe doit être une chaîne ou null' }, { status: 400 });
  }

  const r = await retenirCoupe(plante, demande);
  if (!r.ok) {
    // `non_validee` est un conflit d'état, pas une requête fautive : la plante
    // existe, elle n'est simplement pas dans l'état qui autorise ce geste.
    return NextResponse.json({ error: r.motif }, { status: r.motif === 'non_validee' ? 409 : 404 });
  }
  return NextResponse.json({ ok: true, coupe: r.coupe });
}
