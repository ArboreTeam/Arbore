import { NextRequest, NextResponse } from 'next/server';

import { deposer, lire, sources } from '@/lib/generator/depot';
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

/**
 * Dépose une tâche.
 *
 * `image` est facultative : sans elle, le serveur retrouve la source de la
 * plante sur le volume. C'est le chemin normal depuis l'atelier, et il garantit
 * qu'aucun client ne fabrique un chemin de fichier. Une image nommée mais
 * absente est refusée ICI plutôt que découverte par l'ouvrier 165 s de GPU plus
 * tard.
 */
export async function POST(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  const c = await corps<{ plante?: string; image?: string; raison?: string; graine?: number }>(req);
  if (!c?.plante) {
    return NextResponse.json({ error: 'plante requise' }, { status: 400 });
  }

  const dispo = sources();
  const source = c.image
    ? dispo.find((s) => s.fichier === c.image)
    : dispo.find((s) => s.plante === c.plante);
  if (!source) {
    return NextResponse.json(
      { error: c.image ? 'source introuvable' : `aucune image pour ${c.plante}` },
      { status: 400 },
    );
  }

  const tache = await deposer(
    c.plante, source.fichier, c.raison ?? 'initiale', c.graine ?? null, source.sansPot,
  );
  return NextResponse.json(tache, { status: 201 });
}
