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
