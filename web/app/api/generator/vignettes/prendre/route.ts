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
 * La réponse porte l'adresse de l'API visée et ses DEUX clés — celle d'API et
 * celle des routes internes : l'ouvrier ne les connaît pas et n'a pas à les
 * porter en configuration, sinon il faudrait lui donner celles de TOUS les
 * environnements pour qu'il puisse en servir un.
 *
 * C'est aussi ce qui fait qu'un ouvrier branché sur dev n'a, à aucun instant,
 * de quoi écrire en production.
 */
export async function POST(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  // L'ouvrier annonce l'environnement qu'il sert. Sans ce filtre il
  // réserverait une tâche de production qu'il n'a pas de quoi publier, et la
  // tâche reviendrait en attente 20 minutes plus tard.
  const servi = req.nextUrl.searchParams.get('env') ?? undefined;
  const tache = await prendreVignette(Date.now(), servi);
  if (!tache) return new NextResponse(null, { status: 204 });

  const env = environnement(tache.env);
  if (!env) {
    // L'environnement a disparu de la configuration depuis le dépôt. Mieux
    // vaut ne rien servir que d'envoyer l'ouvrier publier à l'aveugle.
    return NextResponse.json(
      { error: `environnement ${tache.env} absent de la configuration` }, { status: 409 },
    );
  }
  if (!env.interne) {
    // Sans clé interne, l'ouvrier ne pourrait ni lire le catalogue ni publier.
    // Mieux vaut garder la tâche en attente que la lui remettre pour qu'il
    // échoue : un 409 la laisse réservable dès que le secret est posé.
    return NextResponse.json(
      { error: `clé interne absente pour ${tache.env}` }, { status: 409 },
    );
  }
  return NextResponse.json({
    ...tache, api: env.api, cle: env.cle, interne: env.interne,
  });
}
