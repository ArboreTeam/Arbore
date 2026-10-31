import { NextRequest, NextResponse } from 'next/server';

import { environnement } from '@/lib/generator/config';
import { prendreVignette } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/**
 * Réserve la plus ancienne vignette en attente.
 *
 * `204` et non `404` quand la file est vide : ce n'est pas une erreur, c'est
 * un catalogue à jour. L'ouvrier boucle là-dessus.
 *
 * La réponse porte l'adresse de l'API visée et sa clé : l'ouvrier ne les
 * connaît pas et n'a pas à les porter en configuration, sinon il faudrait lui
 * donner celles de TOUS les environnements pour qu'il puisse en servir un.
 */
export async function POST(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  const tache = await prendreVignette();
  if (!tache) return new NextResponse(null, { status: 204 });

  const env = environnement(tache.env);
  if (!env) {
    // L'environnement a disparu de la configuration depuis le dépôt. Mieux
    // vaut ne rien servir que d'envoyer l'ouvrier publier à l'aveugle.
    return NextResponse.json(
      { error: `environnement ${tache.env} absent de la configuration` }, { status: 409 },
    );
  }
  return NextResponse.json({ ...tache, api: env.api, cle: env.cle });
}
