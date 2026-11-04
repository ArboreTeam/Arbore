import { NextRequest, NextResponse } from 'next/server';

import { environnement, environnements } from '@/lib/generator/config';
import {
  CLARTE_CIEL_MAX, REGLAGES_VIGNETTE, deposerVignettes, fileVignettes, reglagesValides,
} from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/** État de la file et réglages par défaut. Sert au tableau de bord. */
export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  return NextResponse.json({
    vignettes: fileVignettes(),
    defauts: REGLAGES_VIGNETTE,
    clarteCielMax: CLARTE_CIEL_MAX,
    // Les noms seuls : ni les clés, ni même les URL n'ont à sortir.
    environnements: environnements().map((e) => e.nom),
  });
}

/**
 * Dépose une tâche par plante.
 *
 * L'environnement est relu dans la configuration du SERVEUR : un nom reçu du
 * client ne sert qu'à choisir parmi ce qui est déclaré, jamais à fabriquer une
 * adresse.
 */
export async function POST(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  const c = await corps<{ env?: string; plantes?: unknown; reglages?: unknown }>(req);

  const env = typeof c?.env === 'string' ? environnement(c.env) : null;
  if (!env) {
    return NextResponse.json({ error: 'environnement inconnu' }, { status: 400 });
  }

  const plantes = Array.isArray(c?.plantes)
    ? c!.plantes.filter((p): p is string => typeof p === 'string' && /^[a-f0-9]{24}$/i.test(p))
    : [];
  if (!plantes.length) {
    return NextResponse.json({ error: 'aucune plante valide' }, { status: 400 });
  }

  const reglages = reglagesValides(c?.reglages as never);
  if (!reglages) {
    // Le refus le plus probable : un ciel trop clair. Le dire, plutôt que de
    // rendre 123 vignettes que l'app refusera ensuite en silence.
    return NextResponse.json(
      { error: `réglages refusés — le ciel doit rester sous ${CLARTE_CIEL_MAX} de clarté` },
      { status: 400 },
    );
  }

  const posees = await deposerVignettes(env.nom, plantes, reglages);
  return NextResponse.json({ posees: posees.length, ignorees: plantes.length - posees.length },
    { status: 201 });
}
