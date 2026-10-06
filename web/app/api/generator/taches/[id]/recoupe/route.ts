// Remplace les candidats de retrait d'une tâche déjà livrée.
//
// Pourquoi une route à part de `/resultat` : celle-là exige une réservation,
// parce qu'elle conclut une génération. Une recoupe ne génère rien — elle
// repart d'un GLB existant, ne coûte pas de GPU, et porte sur une tâche
// terminée que personne ne réserve plus. Lui imposer une réservation
// obligerait à rouvrir des tâches closes, donc à risquer d'en perdre le
// verdict.
import { NextRequest, NextResponse } from 'next/server';

import { recouper } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { id } = await ctx.params;
  const c = await corps<{ candidats?: unknown }>(req);
  if (!Array.isArray(c?.candidats)) {
    return NextResponse.json({ error: 'candidats requis' }, { status: 400 });
  }
  // Un tableau vide effacerait les candidats d'une plante posable sans que rien
  // ne le remplace : c'est une régression muette, pas une recoupe.
  if (c.candidats.length === 0) {
    return NextResponse.json({ error: 'aucun candidat' }, { status: 400 });
  }

  const r = await recouper(id, c.candidats);
  if (!r.ok) {
    return r.raison === 'introuvable'
      ? introuvable()
      : NextResponse.json({ error: 'tache non livree' }, { status: 409 });
  }
  return NextResponse.json(r);
}
