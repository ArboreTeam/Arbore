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

/**
 * Empreintes SHA-256 des clés acceptées. Jamais les clés elles-mêmes.
 *
 * PLUSIEURS, séparées par des virgules ou des espaces, et c'est le point.
 * L'ouvrier des vignettes doit se connecter à l'atelier, et avec une empreinte
 * unique il faudrait lui confier la clé HUMAINE — donc écrire un mot de passe
 * de personne dans un fichier de secrets, et le rendre irrévocable sans
 * déconnecter cette personne.
 *
 * Avec une liste, le robot reçoit sa propre clé, révocable seule : on retire
 * son empreinte et lui seul perd l'accès.
 *
 * Une valeur unique reste acceptée telle quelle — rien à changer là où il n'y
 * a pas de robot.
 */
export function empreintesAttendues(): Set<string> {
  return new Set(
    secretDepuis('GENERATOR_KEY_HASH')
      .toLowerCase()
      .split(/[\s,]+/)
      .filter((e) => /^[0-9a-f]{64}$/.test(e)),
  );
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
  /**
   * Base PUBLIQUE de l'API, sans barre finale.
   *
   * Elle sert à fabriquer les URL d'images affichées dans le NAVIGATEUR. Elle
   * doit donc rester joignable depuis l'extérieur.
   */
  api: string;
  /**
   * Base à employer pour les appels `/internal/*`, sans barre finale.
   *
   * Séparée de `api`, et ce n'est pas du rangement (#696). `api` avait deux
   * publics à la fois — le navigateur, pour les images, et le robot, pour ses
   * appels — et les confondre mettait **Cloudflare dans le chemin d'un robot
   * interne**.
   *
   * Mesuré le 2026-11-02 sur dev, mêmes clés et même URL :
   *
   *     curl/8.5.0          -> 200
   *     Python-urllib/3.11  -> 403
   *
   * L'ouvrier prenait donc un 403 à chaque tâche. Déguiser son agent aurait
   * contourné une règle de bot en se faisant passer pour autre chose, et la
   * règle peut changer demain. Le trafic d'un robot qui tourne sur la MÊME
   * machine que le backend n'a aucune raison de sortir : `http://backend:8080`
   * ne quitte pas le pont Docker, évite le CDN, et épargne 2,6 Mo de
   * téléchargement et un envoi par plante — fois 123.
   *
   * Vide, elle retombe sur `api` : rien à changer là où les deux coïncident.
   */
  apiInterne: string;
  /** Clé d'API de CET environnement. Ne sort jamais du serveur. */
  cle: string;
  /**
   * Clé des routes internes de CET environnement (`X-Arbore-Internal-Key`).
   *
   * Exigée EN PLUS de `cle` par `/internal/*` : c'est ce qui permet de lister
   * le catalogue et de publier une vignette sans session Firebase (#696). Sans
   * elle, l'atelier n'a aucune façon de lire le catalogue — la clé d'API seule
   * prend un 401 sur `/plants`, mesuré.
   *
   * Vide est un état valide : l'aperçu le dira plutôt que de tomber.
   */
  interne: string;
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
 * `GET /models/thumbnails/:filename` est une route publique du backend. Les
 * clés ne servent qu'à lister le catalogue et à publier, et elles restent côté
 * serveur — jamais de `NEXT_PUBLIC_`.
 *
 * Format : un tableau JSON
 * `[{ "nom": "dev", "api": "https://…", "apiInterne": "http://backend:8080",
 *     "cle": "…", "interne": "…" }]`,
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
      .map((e) => {
        const api = e.api.replace(/\/+$/, '');
        return {
          nom: e.nom,
          api,
          // Retombe sur `api`, et non sur une chaîne vide : une configuration
          // écrite avant cette séparation doit continuer de fonctionner telle
          // quelle, exactement comme avant.
          apiInterne: typeof e.apiInterne === 'string' && e.apiInterne.trim()
            ? e.apiInterne.replace(/\/+$/, '')
            : api,
          cle: typeof e.cle === 'string' ? e.cle : '',
          interne: typeof e.interne === 'string' ? e.interne : '',
        };
      });
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
