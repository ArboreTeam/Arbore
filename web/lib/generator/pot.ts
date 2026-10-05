// Mesure du rebord d'un pot : où le poser, et à quelle échelle.
//
// C'est la moitié manquante du socle. La plante dit « mon pot faisait ce rayon,
// à cette hauteur » ; le pot dit « mon rebord fait ce rayon, à cette hauteur ».
// La composition se réduit alors à une similitude, sans aucun réglage à la main.
import { lireMaillage } from './glb';

export type Rebord = {
  /** Rayon du haut du pot, dans ses propres unités. */
  rayon: number;
  /** Hauteur du rebord. */
  y: number;
  /** Axe du pot, pour le centrer. */
  x: number;
  z: number;
  hauteur: number;
  triangles: number;
};

/**
 * Médiane d'un tableau, sans le trier en place.
 *
 * La médiane et non la moyenne : l'axe d'un pot ne doit pas être déplacé par
 * une anse, un bec ou une soucoupe.
 */
function mediane(v: number[]): number {
  if (v.length === 0) return 0;
  const t = [...v].sort((a, b) => a - b);
  const m = t.length >> 1;
  return t.length % 2 ? t[m] : (t[m - 1] + t[m]) / 2;
}

function centile(v: number[], p: number): number {
  if (v.length === 0) return 0;
  const t = [...v].sort((a, b) => a - b);
  return t[Math.min(t.length - 1, Math.max(0, Math.round((t.length - 1) * p)))];
}

/**
 * Mesure le rebord, ou rend `null` si le maillage n'en a pas d'exploitable.
 *
 * Refuser à l'ingestion vaut mieux que de le découvrir à l'essayage : un pot
 * sans rebord mesurable ne peut pas être posé, et le dire tout de suite évite
 * de ranger un objet inutilisable dans la bibliothèque.
 */
export function mesurerRebord(chemin: string): Rebord | null {
  let maillage;
  try {
    maillage = lireMaillage(chemin);
  } catch {
    return null;
  }

  const p = maillage.positions;
  const n = p.length / 3;
  if (n < 32) return null;

  let yMin = Infinity;
  let yMax = -Infinity;
  for (let i = 0; i < n; i += 1) {
    const y = p[i * 3 + 1];
    if (y < yMin) yMin = y;
    if (y > yMax) yMax = y;
  }
  const hauteur = yMax - yMin;
  if (!(hauteur > 0)) return null;

  // Le centre se lit sur la LÈVRE, pas sur tout le pot : c'est le rebord qu'on
  // alignera, et un pot dont la base est décentrée, ébréchée, ou qui traîne une
  // soucoupe, donnerait sinon un axe faux. Mesuré sur un pot extrait : la
  // médiane sur tout le maillage plaçait l'axe à z = −0,141 là où la lèvre le
  // met à −0,009.
  //
  // Milieu de l'emprise et non médiane : sur un anneau, la médiane des
  // coordonnées suit la densité de sommets, pas la géométrie — c'est le même
  // piège que l'axe du pot côté plante.
  const bande: number[] = [];
  for (let i = 0; i < n; i += 1) {
    if (p[i * 3 + 1] >= yMax - hauteur / 6) bande.push(i);
  }
  if (bande.length < 16) return null;

  let xMin = Infinity; let xMax = -Infinity;
  let zMin = Infinity; let zMax = -Infinity;
  for (let k = 0; k < bande.length; k += 1) {
    const x = p[bande[k] * 3];
    const z = p[bande[k] * 3 + 2];
    if (x < xMin) xMin = x;
    if (x > xMax) xMax = x;
    if (z < zMin) zMin = z;
    if (z > zMax) zMax = z;
  }
  const cx = (xMin + xMax) / 2;
  const cz = (zMin + zMax) / 2;

  // Le 95e centile plutôt que le maximum : un sommet isolé, une bavure de
  // maillage, donnerait un rayon trop grand et donc un pot trop petit à l'écran.
  const hautes: number[] = [];
  for (let k = 0; k < bande.length; k += 1) {
    const dx = p[bande[k] * 3] - cx;
    const dz = p[bande[k] * 3 + 2] - cz;
    hautes.push(Math.hypot(dx, dz));
  }

  const rayon = centile(hautes, 0.95);
  if (!(rayon > 0)) return null;

  // Un pot est plus large que haut, ou à peu près aussi haut que large. Au-delà
  // d'un rapport de 6 on tient autre chose : un tuteur, une tige, un décor.
  if (hauteur / (2 * rayon) > 6) return null;

  return {
    rayon: Number(rayon.toFixed(6)),
    y: Number(yMax.toFixed(6)),
    x: Number(cx.toFixed(6)),
    z: Number(cz.toFixed(6)),
    hauteur: Number(hauteur.toFixed(6)),
    triangles: maillage.triangles,
  };
}
