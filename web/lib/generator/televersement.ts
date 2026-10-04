// Réception d'un fichier en morceaux.
//
// Partagée par les artefacts et les images sources : la logique de découpe est
// délicate — position, assemblage, publication atomique — et la dupliquer
// reviendrait à la corriger deux fois, ou une seule.
//
// Pourquoi en morceaux plutôt qu'en une requête : trois plafonds se dressent
// sur le trajet d'un fichier de plusieurs dizaines de mégaoctets, et le premier
// est silencieux.
//
//   - **Next tronque à 10 Mo** tout corps traversant le middleware, et le
//     signale par un avertissement de journal, pas par une erreur. Mesuré :
//     63 Mo envoyés, 10 Mo écrits, réponse 201. Exclure la route du middleware
//     lèverait la troncature mais ouvrirait un chemin non authentifié.
//   - **Cloudflare** coupe les corps de requête à 100 Mo sur le palier gratuit.
//   - **Le conteneur** vit dans 768 Mo : tamponner un fichier entier en mémoire
//     pour contourner le premier reviendrait à frôler le troisième.
import { createWriteStream, mkdirSync, renameSync, statSync, unlinkSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { NextRequest, NextResponse } from 'next/server';

/** Nom du fichier d'assemblage. Préfixé d'un point : rien ne le liste. */
function cheminPartiel(chemin: string): string {
  return join(dirname(chemin), `.${chemin.split('/').pop()}.partiel`);
}

/**
 * Écrit un morceau, et publie le fichier au dernier.
 *
 * `maxOctets` est un plafond de SÛRETÉ sur le fichier reconstitué, pas sur un
 * morceau : il protège le disque, rien n'obligeant un client à s'arrêter.
 */
export async function recevoirMorceau(
  req: NextRequest,
  chemin: string,
  maxOctets: number,
): Promise<NextResponse> {
  const q = req.nextUrl.searchParams;
  const position = Number(q.get('position') ?? '0');
  const final = q.get('final') === '1';

  if (!Number.isInteger(position) || position < 0 || position > maxOctets) {
    return NextResponse.json({ error: 'position invalide' }, { status: 400 });
  }
  if (!req.body) {
    return NextResponse.json({ error: 'corps vide' }, { status: 400 });
  }

  mkdirSync(dirname(chemin), { recursive: true });
  const partiel = cheminPartiel(chemin);

  // La position annoncée doit correspondre à ce qui est déjà écrit. Sans ce
  // contrôle, un morceau rejoué ou perdu produirait un fichier mal assemblé que
  // rien ne distinguerait d'un fichier sain.
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
        if (recus > maxOctets) throw new Error('fichier trop lourd');
        ctrl.enqueue(bloc);
      },
    });
    await pipeline(
      Readable.fromWeb(req.body.pipeThrough(compteur) as Parameters<typeof Readable.fromWeb>[0]),
      createWriteStream(partiel, { flags: position === 0 ? 'w' : 'a' }),
    );

    if (!final) return NextResponse.json({ ok: true, position: recus });

    // Renommage, et seulement là : une interruption ne laisse jamais un fichier
    // tronqué sous son vrai nom. Le temporaire est dans le dossier de
    // destination, un renommage n'étant atomique que sur le même système de
    // fichiers.
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
