import { NextRequest, NextResponse } from 'next/server';

import { trancher, type Verdict } from '@/lib/generator/depot';
import { bonHote, corps, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/**
 * Verdict humain, parmi trois.
 *
 * `validee` retient une coupe. `invalidee` redépose sans graine imposée : c'est
 * le seul chemin qui remonte vers le GPU, et il ne sert qu'au défaut qu'aucune
 * métrique ne voit — la géométrie inventée mais plausible.
 *
 * `ecartee` ne redépose pas. Quand le défaut vient de la SOURCE — une image
 * dans l'image, une étagère sous le pot qui s'est modélisée — relancer sur une
 * graine neuve ne peut que reproduire le défaut. Sans ce troisième verdict,
 * une plante ratée n'avait aucune issue.
 */
const VERDICTS = ['validee', 'invalidee', 'ecartee'] as const;

export async function POST(req: NextRequest, ctx: { params: Promise<{ plante: string }> }) {
  if (!bonHote(req)) return introuvable();
  const { plante } = await ctx.params;
  const c = await corps<{
    verdict?: string; valide?: boolean; coupe?: string; raison?: string;
  }>(req);

  // `valide` reste accepté : le notebook et les scripts d'essai l'emploient, et
  // casser leur contrat pour ajouter un troisième verdict serait disproportionné.
  const demande = c?.verdict
    ?? (typeof c?.valide === 'boolean' ? (c.valide ? 'validee' : 'invalidee') : undefined);
  if (!demande || !(VERDICTS as readonly string[]).includes(demande)) {
    return NextResponse.json(
      { error: `verdict requis parmi ${VERDICTS.join(', ')}` }, { status: 400 },
    );
  }

  const verdict = await trancher(plante, demande as Verdict, c?.coupe, c?.raison);
  return NextResponse.json({ ok: true, verdict });
}
