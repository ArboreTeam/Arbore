// Configuration de l'atelier, côté serveur uniquement.
//
// Jamais de NEXT_PUBLIC_ ici : ces valeurs ne doivent pas atteindre le
// navigateur. Les variantes `_PATH` reprennent le motif déjà en place côté
// backend (#338, #543) — une variable d'environnement est lisible par
// `docker inspect` et dans /proc/<pid>/environ, un fichier monté ne l'est pas.
import { readFileSync } from 'node:fs';

function secretDepuis(nom: string): string {
  const chemin = process.env[`${nom}_PATH`];
  if (chemin) {
    try {
      return readFileSync(chemin, 'utf8').trim();
    } catch {
      return '';
    }
  }
  return (process.env[nom] ?? '').trim();
}

/** Empreinte SHA-256 hexadécimale de la clé d'accès. Jamais la clé elle-même. */
export function empreinteAttendue(): string {
  return secretDepuis('GENERATOR_KEY_HASH').toLowerCase();
}

/** Secret de signature des cookies de session. */
export function secretSession(): string {
  return secretDepuis('GENERATOR_SESSION_SECRET');
}

/** Hôte servant l'atelier. Tout ce qui n'en vient pas doit recevoir un 404. */
export function hoteAtelier(): string {
  return (process.env.GENERATOR_HOST || 'generator.arbore.app').toLowerCase();
}

/**
 * Adresse du client.
 *
 * nginx pose `X-Real-IP` depuis `$http_cf_connecting_ip`, et le pare-feu
 * d'origine n'accepte que les plages Cloudflare : l'en-tête ne peut donc pas
 * être forgé par un client, puisque Cloudflare le réécrit et qu'aucun autre
 * chemin n'atteint l'origine. Sans cela, on compterait les essais de nginx —
 * une seule adresse pour tout le monde, et le quota serait épuisé par le
 * premier venu.
 */
export function adresseClient(entetes: Headers): string {
  const direct = entetes.get('cf-connecting-ip') || entetes.get('x-real-ip');
  if (direct) return direct.trim();
  const chaine = entetes.get('x-forwarded-for');
  if (chaine) return chaine.split(',')[0].trim();
  return 'inconnue';
}

/** Un environnement dont l'atelier peut montrer, et refaire, les vignettes. */
export type Environnement = {
  nom: string;
  /** Base de l'API, sans barre finale. */
  api: string;
  /** Clé d'API de CET environnement. Ne sort jamais du serveur. */
  cle: string;
};

/**
 * Environnements déclarés, pour l'aperçu et le rendu des vignettes.
 *
 * Déclarés explicitement plutôt que devinés : l'atelier ne connaissait
 * jusqu'ici qu'un seul backend, par `BACKEND_API_URL`, et il est déployé par
 * environnement. Montrer dev ET prod depuis une seule page suppose de nommer
 * les deux.
 *
 * Les IMAGES, elles, ne demandent aucun secret :
 * `GET /models/thumbnails/:filename` est une route publique du backend. La clé
 * ne sert qu'à lister le catalogue, et elle reste côté serveur — jamais de
 * `NEXT_PUBLIC_`.
 *
 * Format : un tableau JSON `[{ "nom": "dev", "api": "https://…", "cle": "…" }]`,
 * de préférence monté par `_PATH` plutôt que posé en variable, qu'un
 * `docker inspect` suffit à lire.
 */
export function environnements(): Environnement[] {
  const brut = secretDepuis('VIGNETTES_ENVIRONNEMENTS');
  if (!brut) return [];
  try {
    const lu: unknown = JSON.parse(brut);
    if (!Array.isArray(lu)) return [];
    return lu
      .filter((e): e is Environnement =>
        Boolean(e) && typeof e === 'object'
        && typeof (e as Environnement).nom === 'string'
        && typeof (e as Environnement).api === 'string')
      .map((e) => ({
        nom: e.nom,
        api: e.api.replace(/\/+$/, ''),
        cle: typeof e.cle === 'string' ? e.cle : '',
      }));
  } catch {
    // Une configuration illisible rend une liste vide, et la page le dira.
    // Lever ici ferait tomber l'atelier entier pour une virgule en trop.
    return [];
  }
}

/** Un environnement par son nom, ou `null`. Ne jamais faire confiance au client. */
export function environnement(nom: string): Environnement | null {
  return environnements().find((e) => e.nom === nom) ?? null;
}
