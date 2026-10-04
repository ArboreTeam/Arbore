// Garde commune aux routes de l'atelier.
//
// Le middleware a déjà exigé une session valide et refusé tout ce qui ne vient
// pas de l'hôte de l'atelier. Ce contrôle-ci est une ceinture de plus : une
// route qui échapperait un jour au matcher du middleware ne serait pas pour
// autant ouverte.
import { NextRequest, NextResponse } from 'next/server';

import { hoteAtelier } from './config';

export function bonHote(req: NextRequest): boolean {
  return (req.headers.get('host') || '').toLowerCase().split(':')[0] === hoteAtelier();
}

export function introuvable() {
  return NextResponse.json({ error: 'Not found' }, { status: 404 });
}

/** Lit un corps JSON sans jamais laisser une exception remonter en 500. */
export async function corps<T = Record<string, unknown>>(req: NextRequest): Promise<T | null> {
  try {
    return (await req.json()) as T;
  } catch {
    return null;
  }
}
