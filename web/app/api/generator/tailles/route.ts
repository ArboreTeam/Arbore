// Attribution de la taille réelle d'une plante.
//
// Écrit par l'écran de l'atelier, pas par l'ouvrier : seul un humain sait quel
// diamètre fait le pot sur la photo d'origine. La vérification de
// vraisemblance vit dans le dépôt, pas ici — la route ne fait que convoyer.
import { NextRequest, NextResponse } from 'next/server';

import { mesurables, noterTaille } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  const liste = mesurables();
  return NextResponse.json({
    plantes: liste,
    // De quoi afficher l'avancement sans recompter côté écran.
    total: liste.length,
    attribuees: liste.filter((p) => p.taille).length,
    douteuses: liste.filter((p) => !p.potPlausible).length,
  });
}

export async function POST(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  let corps: unknown;
  try {
    corps = await req.json();
  } catch {
    return NextResponse.json({ ok: false, raison: 'corps_illisible' }, { status: 400 });
  }
  const c = (corps ?? {}) as Record<string, unknown>;
  const plante = typeof c.plante === 'string' ? c.plante.trim() : '';
  if (!plante) {
    return NextResponse.json({ ok: false, raison: 'plante_absente' }, { status: 400 });
  }

  // `taille: null` retire l'attribution : c'est le seul chemin pour revenir en
  // arrière après une saisie fautive.
  if (c.taille === null) {
    return NextResponse.json(await noterTaille(plante, null));
  }

  const t = (c.taille ?? {}) as Record<string, unknown>;
  const resultat = await noterTaille(plante, {
    hauteurCm: Number(t.hauteurCm),
    stade: t.stade as 'jeune' | 'adulte',
    ...(t.diametrePotCm !== undefined && t.diametrePotCm !== null
      ? { diametrePotCm: Number(t.diametrePotCm) }
      : {}),
  });
  return NextResponse.json(resultat, { status: resultat.ok ? 200 : 400 });
}
