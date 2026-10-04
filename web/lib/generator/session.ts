// Session de l'atelier de génération 3D — jeton signé, sans état serveur.
//
// Le cookie porte sa propre expiration et une signature HMAC : le serveur n'a
// aucune table de sessions à tenir, et un redémarrage du conteneur n'invalide
// rien. C'est ce qu'on veut pour un outil interne qu'on redéploie souvent.
//
// Web Crypto et non `node:crypto` : ce module est appelé depuis le middleware,
// qui s'exécute sur le runtime Edge où `node:crypto` n'existe pas.

const ENCODEUR = new TextEncoder();

/** Durée de vie d'une session. Au-delà, il faut resaisir la clé. */
export const DUREE_SESSION_S = 12 * 60 * 60;

export const COOKIE_SESSION = 'arbore_generator';

function base64url(octets: Uint8Array): string {
  // Boucle indexée et non `for…of` : la cible TypeScript du projet n'itère pas
  // les tableaux typés sans `downlevelIteration`, et changer la cible pour ce
  // seul module affecterait toute l'application.
  let s = '';
  for (let i = 0; i < octets.length; i += 1) s += String.fromCharCode(octets[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function debase64url(s: string): Uint8Array {
  const b = atob(s.replace(/-/g, '+').replace(/_/g, '/'));
  const out = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i += 1) out[i] = b.charCodeAt(i);
  return out;
}

/**
 * Comparaison à temps constant.
 *
 * Un `===` sur des chaînes s'arrête au premier caractère différent : le temps
 * de réponse révèle alors combien de caractères sont corrects, et une signature
 * se reconstruit octet par octet. Ici le temps ne dépend que de la longueur.
 */
function memeSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function cle(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    ENCODEUR.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function signer(charge: string, secret: string): Promise<string> {
  const sig = await crypto.subtle.sign('HMAC', await cle(secret), ENCODEUR.encode(charge));
  return base64url(new Uint8Array(sig));
}

/** Empreinte SHA-256 en hexadécimal — sert à comparer la clé saisie. */
export async function empreinte(valeur: string): Promise<string> {
  const h = await crypto.subtle.digest('SHA-256', ENCODEUR.encode(valeur));
  return Array.from(new Uint8Array(h))
    .map((o) => o.toString(16).padStart(2, '0'))
    .join('');
}

/** Émet un jeton valable `DUREE_SESSION_S` secondes. */
export async function emettre(secret: string, maintenant = Date.now()): Promise<string> {
  const charge = base64url(
    ENCODEUR.encode(JSON.stringify({ v: 1, exp: Math.floor(maintenant / 1000) + DUREE_SESSION_S })),
  );
  return `${charge}.${await signer(charge, secret)}`;
}

/**
 * Vérifie un jeton. Renvoie `false` pour toute anomalie — signature invalide,
 * expiration dépassée, format inattendu — sans distinguer les cas : un message
 * d'erreur précis renseignerait un attaquant sur ce qu'il doit corriger.
 */
export async function verifier(
  jeton: string | undefined,
  secret: string,
  maintenant = Date.now(),
): Promise<boolean> {
  if (!jeton || !secret) return false;
  const point = jeton.lastIndexOf('.');
  if (point <= 0) return false;

  const charge = jeton.slice(0, point);
  const signature = jeton.slice(point + 1);
  if (!memeSecret(signature, await signer(charge, secret))) return false;

  try {
    const { exp } = JSON.parse(new TextDecoder().decode(debase64url(charge)));
    return typeof exp === 'number' && exp * 1000 > maintenant;
  } catch {
    return false;
  }
}
