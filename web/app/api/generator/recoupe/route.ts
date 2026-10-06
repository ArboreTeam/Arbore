// Ce que la passe de recoupe a de quoi reprendre.
//
// Une liste à part de `/taches`, qui retire volontairement `resultat` pour ne
// pas diffuser les chemins d'artefacts — et c'est ce qui a fait sauter les 79
// plantes au premier essai de la passe : elle lisait des candidats toujours
// vides. Ici on rend les NOMS de fichiers, dont l'ouvrier a besoin pour
// redescendre un maillage, et rien de la disposition du volume.
import { NextRequest, NextResponse } from 'next/server';

import { recoupables } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  const liste = recoupables();
  return NextResponse.json({
    plantes: liste,
    // De quoi dire en une ligne ce qui reste à faire, sans recompter côté
    // ouvrier ni côté écran.
    aRecouper: liste.filter((p) => !p.mesure).length,
  });
}
