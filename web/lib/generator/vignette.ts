// Règles des vignettes, SANS dépendance à Node.
//
// Ce module existe pour une raison précise : la page de l'atelier doit
// calculer la clarté d'un ciel dans le NAVIGATEUR, pour le dire avant l'envoi,
// alors que `depot.ts` importe `node:fs`. Dupliquer la formule en ferait une
// seconde source — et le jour où le seuil de l'app bouge, l'une des deux
// resterait en arrière sans que rien ne le signale.

/**
 * Réglages de rendu d'une vignette, passés tels quels à `rendre.py`.
 *
 * Portés par la TÂCHE et non relus au moment où l'ouvrier la prend : une
 * tâche déposée ce matin doit rendre avec les réglages de ce matin, sinon
 * changer une couleur en cours de passe donnerait un catalogue bicolore sans
 * que rien ne le signale.
 */
export type ReglagesVignette = {
  ciel: string;
  herbe: string;
  echantillons: number;
  puissanceCle: number;
  ambiante: number;
  teinteSol: number;
};

/**
 * Plafond de clarté du ciel, repris de `rendre.py`.
 *
 * `hasLegacyWhiteWallDarkFloor` REFUSE une vignette dès que deux de ses cinq
 * points hauts dépassent 225 — le symptôme de l'ancien design, mur blanc sur
 * sol sombre. L'app la télécharge alors, l'examine, la refuse, et garde
 * l'ancienne image SANS que rien ne le signale.
 *
 * Le fond de l'app lui-même, `#F0EEEA`, mesure 238 : la couleur la plus
 * évidente à choisir est précisément celle qui ferait rejeter tout le
 * catalogue. On refuse donc au dépôt, plutôt que de le découvrir sur 123
 * fichiers.
 */
export const CLARTE_CIEL_MAX = 215;

/** Réglages par défaut, alignés sur ceux de `rendre.py`. */
export const REGLAGES_VIGNETTE: ReglagesVignette = {
  ciel: '#D5CBB8',
  herbe: '#628A4B',
  echantillons: 64,
  puissanceCle: 4.0,
  ambiante: 0.4,
  teinteSol: 0.84,
};

/** Clarté Rec. 709 d'un `#RRGGBB`, la formule de `sampledBrightness`. */
export function clarte(hexa: string): number {
  const m = /^#?([0-9a-f]{6})$/i.exec(hexa.trim());
  if (!m) return NaN;
  const n = parseInt(m[1], 16);
  return 0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255);
}

/** Réglages reçus d'un client, complétés et validés. `null` si refusés. */
export function reglagesValides(
  recu: Partial<ReglagesVignette> | undefined,
): ReglagesVignette | null {
  const r = { ...REGLAGES_VIGNETTE, ...(recu ?? {}) };
  for (const couleur of [r.ciel, r.herbe]) {
    if (!Number.isFinite(clarte(couleur))) return null;
  }
  if (clarte(r.ciel) > CLARTE_CIEL_MAX) return null;
  if (!Number.isInteger(r.echantillons) || r.echantillons < 1 || r.echantillons > 256) return null;
  for (const n of [r.puissanceCle, r.ambiante, r.teinteSol]) {
    if (!Number.isFinite(n) || n < 0 || n > 100) return null;
  }
  return r;
}
