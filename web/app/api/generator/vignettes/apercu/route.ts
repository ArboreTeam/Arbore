import { NextRequest, NextResponse } from 'next/server';

import { environnement, environnements } from '@/lib/generator/config';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

type FicheDistante = {
  id?: string;
  name?: string;
  potless?: boolean;
  versions?: { model?: string; thumbnail?: string; thumbnailModel?: string };
};

/**
 * Catalogue d'un environnement, avec l'adresse publique de chaque vignette.
 *
 * Les images ne demandent aucun secret : `GET /models/thumbnails/:filename`
 * est une route publique du backend. Seule la LISTE est authentifiée, et ses
 * deux clés ne quittent pas le serveur.
 *
 * Deux adresses, et il faut les garder distinctes : la liste est demandée sur
 * `apiInterne`, depuis le serveur, tandis que les URL d'images sont bâties sur
 * `api` — c'est le NAVIGATEUR qui les charge, et lui ne joint pas
 * `http://backend:8080`.
 *
 * Elle passe par `GET /internal/plants` et non par `/plants` (#696). La
 * première version de cette route supposait que la clé d'API suffisait à
 * lister le catalogue : c'était faux, `/plants` vit sous `protected`, donc
 * derrière une session Firebase. L'aperçu rendait 502 à chaque appel. Mesuré
 * depuis le conteneur web : 401 avec la seule clé d'API.
 *
 * `?v=<empreinte>` sur l'URL d'image n'est pas décoratif : sans lui le
 * navigateur sert sa copie en cache et une vignette refaite reste
 * invisible — le symptôme exact qu'on cherche à rendre observable ici.
 *
 * Cette route rend le catalogue d'UN environnement, et la page en montre un à
 * la fois (#434).
 *
 * Le motif invoqué ici était faux. On lisait « les catalogues de dev et de prod
 * n'ont aucun identifiant en commun » ; le 2026-11-02, la liste des noms de
 * vignettes hachée sur les deux machines s'est révélée IDENTIQUE. Cela prouve
 * que les fichiers sont le même jeu, pas que les bases s'accordent — ils ont pu
 * être copiés en bloc. La restriction reste donc, par prudence et non par
 * impossibilité démontrée.
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

  // Dit explicitement plutôt que de laisser partir un appel qui prendra un
  // 503 : « clé interne non configurée » est une panne de provisionnement, pas
  // une panne du backend, et les deux ne se réparent pas au même endroit.
  if (!env.interne) {
    return NextResponse.json(
      { error: `clé interne absente pour ${env.nom} : ajouter \`interne\` à VIGNETTES_ENVIRONNEMENTS` },
      { status: 503 },
    );
  }

  let reponse: Response;
  try {
    reponse = await fetch(`${env.apiInterne}/internal/plants`, {
      headers: { 'X-API-Key': env.cle, 'X-Arbore-Internal-Key': env.interne },
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
      // Provenance de la vignette : la version du MODÈLE dont elle est issue.
      empreinteVignetteModele: f.versions?.thumbnailModel ?? null,
      // Périmée dès que la provenance ne correspond plus au modèle servi.
      //
      // Une provenance ABSENTE compte comme périmée : c'est l'état des
      // vignettes publiées avant #694, et de toute vignette republiée sans
      // déclaration. « Je ne sais pas d'où elle vient » doit se traduire par
      // « à refaire », jamais par « sans doute à jour ».
      perimee: (f.versions?.thumbnailModel ?? null) !== (f.versions?.model ?? null),
      url: `${env.api}/models/thumbnails/${f.id}.png`
        + (f.versions?.thumbnail ? `?v=${encodeURIComponent(f.versions.thumbnail)}` : ''),
    }))
    .sort((a, b) => a.nom.localeCompare(b.nom, 'fr'));

  return NextResponse.json({
    env: env.nom,
    total: plantes.length,
    sansVignette: plantes.filter((p) => !p.empreinteVignette).length,
    perimees: plantes.filter((p) => p.perimee).length,
    plantes,
  });
}
