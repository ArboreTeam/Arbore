// Service des artefacts de l'atelier : aperçus PNG et GLB coupés.
//
// Ces fichiers vivent sur le volume monté, hors de `public/` — Next ne peut
// donc pas les servir statiquement, et c'est tant mieux : ils doivent rester
// derrière la session, comme le reste de l'atelier.
import { createReadStream, createWriteStream, mkdirSync, renameSync, statSync, unlinkSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { NextRequest, NextResponse } from 'next/server';

import { cheminArtefact } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

// Liste blanche d'extensions, et non liste noire : on sert des aperçus et des
// maillages, rien d'autre. Un `.json` ou un `.env` qui traînerait dans le
// dossier d'une plante ne doit pas pouvoir sortir par cette route.
const TYPES: Record<string, string> = {
  '.png': 'image/png',
  '.glb': 'model/gltf-binary',
};

export async function GET(
  req: NextRequest,
  ctx: { params: Promise<{ plante: string; fichier: string }> },
) {
  if (!bonHote(req)) return introuvable();
  const { plante, fichier } = await ctx.params;

  const nom = decodeURIComponent(fichier);
  const ext = nom.slice(nom.lastIndexOf('.')).toLowerCase();
  const type = TYPES[ext];
  if (!type) return introuvable();

  let chemin: string;
  try {
    // `cheminArtefact` valide le nom de plante et refuse tout séparateur ou
    // `..` dans le fichier. C'est la seule fonction qui connaît la disposition
    // du volume, et la seule porte par laquelle un chemin se construit ici.
    chemin = cheminArtefact(plante, nom);
  } catch {
    return introuvable();
  }

  let taille: number;
  try {
    const st = statSync(chemin);
    if (!st.isFile()) return introuvable();
    taille = st.size;
  } catch {
    return introuvable();
  }

  // En flux, pas en mémoire : un GLB pèse 30 à 42 Mo, et les charger
  // entièrement pour les recracher ferait tenir trois requêtes simultanées
  // dans la limite de 768 Mo du conteneur.
  const flux = Readable.toWeb(createReadStream(chemin)) as ReadableStream<Uint8Array>;

  return new NextResponse(flux, {
    headers: {
      'Content-Type': type,
      'Content-Length': String(taille),
      // `no-store` et non une durée de vie : un nom d'aperçu est stable
      // (`apercu_000.png`) alors que son CONTENU change à chaque relance sur
      // une graine neuve. Mis en cache, la revue montrerait le maillage qu'on
      // vient de rejeter — et on invaliderait une plante sur la foi d'une
      // image périmée.
      'Cache-Control': 'no-store, must-revalidate',
      'X-Content-Type-Options': 'nosniff',
      'Content-Disposition': `inline; filename="${nom}"`,
    },
  });
}

/**
 * Dépôt d'un artefact par l'ouvrier, EN MORCEAUX.
 *
 * C'est la pièce qui ferme la chaîne. L'ouvrier tourne sur Colab et livrait ses
 * RÉSULTATS par HTTP, mais ses FICHIERS restaient chez lui : le volume était
 * vide, et la revue n'aurait affiché « aucun aperçu » pour chaque plante.
 *
 * Pourquoi en morceaux plutôt qu'en une requête. Trois plafonds se dressent sur
 * le trajet d'un GLB de 63 Mo, et le premier est silencieux :
 *
 *   - **Next tronque à 10 Mo** tout corps traversant le middleware, et le
 *     signale par un avertissement dans le journal, pas par une erreur. Mesuré :
 *     63 Mo envoyés, 10 Mo écrits, réponse 201. Exclure la route du middleware
 *     lèverait la troncature mais ouvrirait un chemin non authentifié.
 *   - **Cloudflare** coupe les corps de requête à 100 Mo sur le palier gratuit.
 *   - **Le conteneur** vit dans 768 Mo : tamponner un fichier entier en mémoire
 *     pour contourner le premier plafond reviendrait à frôler le troisième.
 *
 * Des morceaux de quelques mégaoctets ne rencontrent aucun des trois, et la
 * mémoire reste plate quelle que soit la taille du maillage.
 */

// Plafond de SÛRETÉ sur le fichier reconstitué, pas sur un morceau. Il protège
// le disque, pas la mémoire : rien n'oblige un client à s'arrêter.
const MAX_OCTETS = 200 * 1024 * 1024;

/** Nom du fichier d'assemblage. Préfixé d'un point : la revue ne le liste pas. */
function cheminPartiel(chemin: string): string {
  return join(dirname(chemin), `.${chemin.split('/').pop()}.partiel`);
}

export async function PUT(
  req: NextRequest,
  ctx: { params: Promise<{ plante: string; fichier: string }> },
) {
  if (!bonHote(req)) return introuvable();
  const { plante, fichier } = await ctx.params;

  const nom = decodeURIComponent(fichier);
  const ext = nom.slice(nom.lastIndexOf('.')).toLowerCase();
  if (!TYPES[ext]) return introuvable();

  let chemin: string;
  try {
    chemin = cheminArtefact(plante, nom);
  } catch {
    return introuvable();
  }

  const q = req.nextUrl.searchParams;
  const position = Number(q.get('position') ?? '0');
  const final = q.get('final') === '1';
  if (!Number.isInteger(position) || position < 0 || position > MAX_OCTETS) {
    return NextResponse.json({ error: 'position invalide' }, { status: 400 });
  }
  if (!req.body) {
    return NextResponse.json({ error: 'corps vide' }, { status: 400 });
  }

  const dossier = dirname(chemin);
  mkdirSync(dossier, { recursive: true });
  const partiel = cheminPartiel(chemin);

  // La position annoncée doit correspondre à ce qui est déjà écrit. Sans ce
  // contrôle, un morceau rejoué ou perdu produirait un fichier mal assemblé
  // que rien ne distinguerait d'un fichier sain — et la revue servirait un GLB
  // corrompu sans le dire.
  let dejaEcrit = 0;
  try {
    dejaEcrit = statSync(partiel).size;
  } catch {
    dejaEcrit = 0;
  }
  if (position !== dejaEcrit) {
    return NextResponse.json(
      { error: 'morceau hors séquence', attendu: dejaEcrit }, { status: 409 },
    );
  }

  try {
    let recus = dejaEcrit;
    const compteur = new TransformStream<Uint8Array, Uint8Array>({
      transform(bloc, ctrl) {
        recus += bloc.byteLength;
        if (recus > MAX_OCTETS) throw new Error('artefact trop lourd');
        ctrl.enqueue(bloc);
      },
    });
    await pipeline(
      Readable.fromWeb(req.body.pipeThrough(compteur) as Parameters<typeof Readable.fromWeb>[0]),
      createWriteStream(partiel, { flags: position === 0 ? 'w' : 'a' }),
    );

    if (!final) {
      return NextResponse.json({ ok: true, position: recus });
    }

    // Renommage, et seulement là : un téléversement interrompu ne laisse jamais
    // un GLB tronqué que la revue servirait comme entier. Le temporaire est
    // dans le dossier de destination, un renommage n'étant atomique que sur le
    // même système de fichiers.
    renameSync(partiel, chemin);
    return NextResponse.json({ ok: true, octets: recus }, { status: 201 });
  } catch {
    try {
      unlinkSync(partiel);
    } catch {
      // Le temporaire a pu ne jamais être créé.
    }
    return NextResponse.json({ error: 'téléversement interrompu' }, { status: 400 });
  }
}
