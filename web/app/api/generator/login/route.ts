import { NextRequest, NextResponse } from 'next/server';

import { adresseClient, empreinteAttendue, hoteAtelier, secretSession } from '@/lib/generator/config';
import { consommer, consulter, oublier } from '@/lib/generator/limite';
import { COOKIE_SESSION, DUREE_SESSION_S, emettre, empreinte } from '@/lib/generator/session';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';   // lit des fichiers de secrets : pas de Edge

const DELAI_CONSTANT_MS = 250;

/** Dort jusqu'à ce que la requête ait duré au moins `DELAI_CONSTANT_MS`.
 *
 * Répondre vite sur « clé absente » et lentement sur « clé comparée » dirait à
 * un attaquant où il en est. On aligne les deux chemins. */
async function repondreApres(debut: number) {
  const reste = DELAI_CONSTANT_MS - (Date.now() - debut);
  if (reste > 0) await new Promise((r) => setTimeout(r, reste));
}

export async function POST(req: NextRequest) {
  const debut = Date.now();

  // Première barrière : l'atelier n'existe que sur son hôte.
  if ((req.headers.get('host') || '').toLowerCase().split(':')[0] !== hoteAtelier()) {
    return NextResponse.json({ error: 'Not found' }, { status: 404 });
  }

  const attendue = empreinteAttendue();
  const secret = secretSession();
  if (!attendue || !secret) {
    // Mal configuré : on refuse plutôt que d'ouvrir. Un atelier sans clé
    // vaudrait un atelier sans porte.
    return NextResponse.json({ error: 'Atelier indisponible' }, { status: 503 });
  }

  const adresse = adresseClient(req.headers);
  const avant = consulter(adresse);
  if (!avant.autorise) {
    await repondreApres(debut);
    return NextResponse.json(
      { error: 'Trop de tentatives', attente: avant.attente },
      { status: 429, headers: { 'Retry-After': String(avant.attente) } },
    );
  }

  let fournie = '';
  try {
    const corps = await req.json();
    fournie = typeof corps?.cle === 'string' ? corps.cle : '';
  } catch {
    fournie = '';
  }

  const juste = fournie.length > 0 && (await empreinte(fournie)) === attendue;

  if (!juste) {
    // On ne consomme un essai QUE sur échec : une connexion réussie ne doit
    // pas rapprocher du blocage.
    const apres = consommer(adresse);
    await repondreApres(debut);
    return NextResponse.json(
      { error: 'Clé invalide', restants: apres.restants, attente: apres.attente },
      { status: 401 },
    );
  }

  oublier(adresse);
  const reponse = NextResponse.json({ ok: true });
  reponse.cookies.set(COOKIE_SESSION, await emettre(secret), {
    httpOnly: true,     // hors de portée du JavaScript de la page
    secure: true,       // jamais en clair
    sameSite: 'strict', // aucune requête inter-site ne porte la session
    path: '/',
    maxAge: DUREE_SESSION_S,
  });
  await repondreApres(debut);
  return reponse;
}
