import { NextRequest, NextResponse } from 'next/server';

import { deposer, lire } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/** État de la file. Sert au tableau de bord. */
export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  const etat = lire();
  return NextResponse.json({
    // On retire `reservation` : le jeton n'a de sens qu'entre la prise et la
    // livraison, et le tableau de bord n'a aucune raison de le diffuser.
    taches: etat.taches.map(({ resultat, reservation, ...reste }) => ({
      ...reste,
      // Le résultat porte des chemins d'artefacts : on n'expose que son
      // existence et son verdict, pas la disposition du volume.
      accepte: resultat ? Boolean((resultat as Record<string, unknown>).accepte) : null,
    })),
  });
}

/** Dépose une tâche. */
export async function POST(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  const c = await corps<{ plante?: string; image?: string; raison?: string; graine?: number }>(req);
  if (!c?.plante || !c?.image) {
    return NextResponse.json({ error: 'plante et image requises' }, { status: 400 });
  }
  const tache = await deposer(c.plante, c.image, c.raison ?? 'initiale', c.graine ?? null);
  return NextResponse.json(tache, { status: 201 });
}
