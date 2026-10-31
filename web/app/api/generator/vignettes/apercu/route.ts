import { NextRequest, NextResponse } from 'next/server';

import { environnement, environnements } from '@/lib/generator/config';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

type FicheDistante = {
  id?: string;
  name?: string;
  potless?: boolean;
  versions?: { model?: string; thumbnail?: string };
};

/**
 * Catalogue d'un environnement, avec l'adresse publique de chaque vignette.
 *
 * Les images ne demandent aucun secret : `GET /models/thumbnails/:filename`
 * est une route publique du backend. Seule la LISTE passe par la clé, et
 * celle-ci ne quitte pas le serveur.
 *
 * `?v=<empreinte>` sur l'URL d'image n'est pas décoratif : sans lui le
 * navigateur sert sa copie en cache et une vignette refaite reste
 * invisible — le symptôme exact qu'on cherche à rendre observable ici.
 *
 * Une comparaison « la même plante dans les deux environnements » n'est PAS
 * possible aujourd'hui : mesuré le 2026-10-31, les catalogues de dev et de
 * prod n'ont aucun identifiant en commun (#434). Cette route rend donc le
 * catalogue d'UN environnement, et la page en montre un à la fois.
 */
export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();

  const nom = req.nextUrl.searchParams.get('env') ?? '';
  const env = environnement(nom);
  if (!env) {
    return NextResponse.json(
      { error: 'environnement inconnu', connus: environnements().map((e) => e.nom) },
      { status: 400 },
    );
  }

  let reponse: Response;
  try {
    reponse = await fetch(`${env.api}/plants`, {
      headers: { 'X-API-Key': env.cle },
      cache: 'no-store',
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    // Injoignable : on le DIT. Rendre une liste vide ferait passer une panne
    // de réseau pour un catalogue sans vignettes.
    return NextResponse.json({ error: `${env.nom} injoignable` }, { status: 502 });
  }
  if (!reponse.ok) {
    return NextResponse.json(
      { error: `${env.nom} a répondu ${reponse.status}` }, { status: 502 },
    );
  }

  const lu: unknown = await reponse.json().catch(() => null);
  const fiches: FicheDistante[] = Array.isArray(lu)
    ? lu
    : Array.isArray((lu as { plants?: unknown })?.plants)
      ? (lu as { plants: FicheDistante[] }).plants
      : [];

  const plantes = fiches
    .filter((f): f is FicheDistante & { id: string } => typeof f.id === 'string')
    .map((f) => ({
      id: f.id,
      nom: f.name ?? f.id,
      potless: Boolean(f.potless),
      empreinteModele: f.versions?.model ?? null,
      empreinteVignette: f.versions?.thumbnail ?? null,
      url: `${env.api}/models/thumbnails/${f.id}.png`
        + (f.versions?.thumbnail ? `?v=${encodeURIComponent(f.versions.thumbnail)}` : ''),
    }))
    .sort((a, b) => a.nom.localeCompare(b.nom, 'fr'));

  return NextResponse.json({
    env: env.nom,
    total: plantes.length,
    sansVignette: plantes.filter((p) => !p.empreinteVignette).length,
    plantes,
  });
}
