import { NextRequest, NextResponse } from 'next/server';

import { prendre } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/**
 * Réserve la plus ancienne tâche en attente.
 *
 * `204` et non `404` quand la file est vide : ce n'est pas une erreur, c'est un
 * atelier à jour. L'ouvrier boucle là-dessus et doit distinguer les deux sans
 * lire de corps.
 *
 * La réponse porte un jeton de réservation, qu'il faudra présenter pour livrer.
 * Sans lui, un ouvrier dont la réservation a expiré écraserait le travail de
 * celui qui a repris sa tâche — l'identifiant de tâche, lui, ne change pas.
 */
export async function POST(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  const tache = await prendre();
  if (!tache) return new NextResponse(null, { status: 204 });
  return NextResponse.json(tache);
}
