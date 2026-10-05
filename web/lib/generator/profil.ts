// Contrôle automatique de la pose d'un pot sous une plante.
//
// Essayer N pots sur M plantes à l'œil, c'est N×M maillages de soixante
// mégaoctets chargés et autant d'orbites à la souris. Or la composition est
// une similitude entièrement déterminée par le socle et le rebord : elle se
// vérifie par le calcul, sans rien afficher.
//
// Il suffit de comparer deux PROFILS RADIAUX. Celui du pot dit quelle place il
// offre à chaque profondeur sous sa lèvre ; celui de la plante dit ce qu'elle
// occupe encore sous sa ligne de coupe — le fond de son ancien pot, un anneau
// de rebord, des racines, tout ce que la coupe a laissé. Quand le second
// dépasse le premier, le résidu traverse la paroi et se voit.
//
// L'écran ne montre alors que les paires fautives, ce qui est le seul moyen de
// tenir une bibliothèque de cent pots.
import { lireMaillage } from './glb';

/**
 * Nombre de bandes d'un profil.
 *
 * Assez pour distinguer le galbe d'un cache-pot d'un anneau de résidu, assez
 * peu pour que le profil tienne dans l'état sans le gonfler : vingt-quatre
 * flottants par objet.
 */
export const BANDES = 24;

export type Profil = {
  /**
   * Rayon par bande, de la plus haute à la plus basse. `rayons[i]` vaut à la
   * profondeur `(i + 0.5) / BANDES × profondeur`.
   */
  rayons: number[];
  /** Hauteur couverte, dans les unités du maillage mesuré. */
  profondeur: number;
};

/** Ce qu'une plante occupe sous sa ligne de coupe. */
export type Empreinte = {
  /** Le résidu. Tous rayons nuls quand la coupe est nette. */
  residu: Profil;
  /** Hauteur du maillage coupé, pour juger de la proportion du pot posé. */
  hauteur: number;
};

function centile(v: number[], p: number): number {
  if (v.length === 0) return 0;
  const t = [...v].sort((a, b) => a - b);
  return t[Math.min(t.length - 1, Math.max(0, Math.round((t.length - 1) * p)))];
}

/**
 * Profil radial d'un nuage de points entre deux hauteurs.
 *
 * `combler` distingue les deux usages, et la distinction est le cœur du
 * contrôle. Pour un POT, une bande vide est un trou de maillage : la rendre
 * nulle ferait croire que la paroi s'arrête là et condamnerait des paires
 * saines, donc on prolonge la bande voisine. Pour un RÉSIDU, une bande vide
 * veut dire qu'il n'y a rien à cette profondeur, et c'est une mesure juste :
 * zéro.
 */
export function profilRadial(
  positions: Float32Array,
  cx: number, cz: number, yHaut: number, yBas: number,
  combler: boolean,
): Profil {
  const profondeur = yHaut - yBas;
  const rayons = new Array<number>(BANDES).fill(0);
  if (!(profondeur > 0)) return { rayons, profondeur: 0 };

  const seaux: number[][] = Array.from({ length: BANDES }, () => []);
  const n = positions.length / 3;
  for (let i = 0; i < n; i += 1) {
    const y = positions[i * 3 + 1];
    if (y > yHaut || y < yBas) continue;
    // Depuis le HAUT : la bande 0 est au niveau de la lèvre pour un pot, au
    // niveau de la coupe pour une plante. Les deux profils se comparent alors
    // bande à bande sans décalage à retenir.
    let b = Math.floor(((yHaut - y) / profondeur) * BANDES);
    if (b < 0) b = 0;
    if (b >= BANDES) b = BANDES - 1;
    const dx = positions[i * 3] - cx;
    const dz = positions[i * 3 + 2] - cz;
    seaux[b].push(Math.hypot(dx, dz));
  }

  for (let b = 0; b < BANDES; b += 1) {
    // Le 95e centile, comme pour le rebord : un sommet isolé ou une bavure de
    // maillage donnerait une paroi trop large, donc une alerte pour rien.
    rayons[b] = seaux[b].length >= 4 ? centile(seaux[b], 0.95) : -1;
  }

  if (combler) {
    // Prolonger vers le bas, puis vers le haut : une bande sans mesure hérite
    // de sa voisine renseignée la plus proche.
    let dernier = 0;
    for (let b = 0; b < BANDES; b += 1) {
      if (rayons[b] < 0) rayons[b] = dernier;
      else dernier = rayons[b];
    }
    for (let b = BANDES - 1; b >= 0; b -= 1) {
      if (rayons[b] === 0 && dernier > 0) rayons[b] = dernier;
      else if (rayons[b] > 0) dernier = rayons[b];
    }
  } else {
    for (let b = 0; b < BANDES; b += 1) if (rayons[b] < 0) rayons[b] = 0;
  }

  return {
    rayons: rayons.map((r) => Number(r.toFixed(6))),
    profondeur: Number(profondeur.toFixed(6)),
  };
}

/** Rayon du profil à une profondeur donnée, interpolé entre centres de bandes. */
export function rayonA(profil: Profil, profondeur: number): number {
  const { rayons } = profil;
  if (rayons.length === 0 || !(profil.profondeur > 0)) return 0;
  const t = (profondeur / profil.profondeur) * BANDES - 0.5;
  if (t <= 0) return rayons[0];
  if (t >= BANDES - 1) return rayons[BANDES - 1];
  const i = Math.floor(t);
  return rayons[i] + (rayons[i + 1] - rayons[i]) * (t - i);
}

/**
 * Profil d'un pot, de sa lèvre à son fond.
 *
 * Mesuré à l'ingestion et rangé avec le rebord : la bibliothèque est lue à
 * chaque affichage de l'atelier, et relire un GLB par pot à chaque fois
 * coûterait plus que tout le reste de la page.
 */
export function profilerPot(
  chemin: string, rebord: { x: number; z: number; y: number; hauteur: number },
): Profil | null {
  try {
    const m = lireMaillage(chemin);
    return profilRadial(m.positions, rebord.x, rebord.z,
                        rebord.y, rebord.y - rebord.hauteur, true);
  } catch {
    return null;
  }
}

/**
 * Empreinte d'une plante coupée : ce qu'elle laisse sous sa ligne de coupe.
 *
 * Le maillage descend plus bas que la coupe chaque fois que le retrait a été
 * partiel, et c'est le cas courant, pas l'exception : la paroi part, le fond et
 * l'anneau du rebord restent.
 */
export function profilerPlante(
  chemin: string, socle: { x: number; z: number; y: number },
): Empreinte | null {
  let m;
  try {
    m = lireMaillage(chemin);
  } catch {
    return null;
  }
  const p = m.positions;
  const n = p.length / 3;
  let yMin = Infinity;
  let yMax = -Infinity;
  for (let i = 0; i < n; i += 1) {
    const y = p[i * 3 + 1];
    if (y < yMin) yMin = y;
    if (y > yMax) yMax = y;
  }
  if (!(yMax > yMin)) return null;
  return {
    residu: profilRadial(p, socle.x, socle.z, socle.y, yMin, false),
    hauteur: Number((yMax - yMin).toFixed(6)),
  };
}

/**
 * Seuils du contrôle, tous en grandeurs SANS DIMENSION.
 *
 * Une plante et un pot sont mesurés dans des unités arbitraires — TRELLIS
 * normalise à une hauteur de 1 — et un seuil en longueur n'y voudrait rien
 * dire. Les valeurs viennent des 48 paires du premier lot, mesurées contre le
 * cache-pot de la bibliothèque.
 */
export const SEUILS = {
  /**
   * Largeur, en multiples du rayon du socle, au-delà de laquelle la matière
   * sous la coupe mérite un regard.
   *
   * Un SIGNAL, pas un verdict, et la nuance a été payée : mesuré d'abord comme
   * « aucun pot ne peut la cacher », puisque le rebord de tout pot est mis à
   * l'échelle du rayon du socle. C'est juste pour un reste de pot, et faux pour
   * du feuillage qui retombe sous la ligne du rebord — celui-là pend à
   * l'extérieur du pot, ce qui est exactement ce qu'il doit faire.
   *
   * Or cette mesure est AVEUGLE À LA COULEUR : elle lit les positions du GLB,
   * pas sa texture, et ne sait pas distinguer les deux. Mesuré en séparant le
   * vert, hors de l'application, sur trois plantes recoupées : l'Alocasia
   * Zebrina garde 14 591 triangles non verts à 1,23 rayon mais sur 0,036
   * d'épaisseur seulement — la lèvre de l'ancien pot — et 2 594 triangles verts
   * qui descendent à 0,22, dont le plus large atteint 1,22. Le feuillage seul
   * suffit donc à franchir le seuil.
   *
   * Sur le premier lot, 40 plantes sur 48 le franchissent ; combien sont de
   * vrais restes de pot reste à établir, et c'est l'ouvrier qui le dira,
   * puisque lui connaît la couleur.
   */
  largeur: 1.05,
  /** Débordement toléré hors de la paroi, en fraction du rayon du socle. */
  debordement: 0.05,
  /**
   * Hauteur du pot posé, rapportée à celle de la plante.
   *
   * Mesuré : de 0,096 (un Washingtonia d'un mètre dans un cache-pot d'un
   * dixième de sa hauteur) à 0,863 (un Pilea trapu dont le rebord large étire
   * le même cache-pot jusqu'à plus de la moitié du modèle), médiane 0,207.
   */
  proportionMin: 0.10,
  proportionMax: 0.55,
};

// ── Jugement d'une plante, pot indépendant ─────────────────────────────────

export type DefautPlante = 'matiere_large';

/**
 * Nombre de bandes vides consécutives à partir duquel on parle de creux.
 *
 * Trois sur vingt-quatre, soit un huitième de la profondeur du résidu. En
 * dessous, c'est de l'échantillonnage : les creux réels du premier lot en
 * couvraient treize et plus.
 */
export const VIDE_MIN = 3;

export type Jugement = {
  /** Plus grand rayon du résidu, en multiples du rayon du socle. */
  largeur: number;
  /** Profondeur du résidu, en fraction de la hauteur de la plante coupée. */
  profondeur: number;
  /**
   * Le profil a un trou : de la matière sous la coupe, du vide, puis de la
   * matière tout en bas.
   *
   * C'est la signature du retrait partiel, et c'est le cas COURANT, pas
   * l'exception — 39 paires sur 48 au premier lot. La paroi part, le fond de
   * l'ancien pot et son anneau de rebord restent.
   */
  creux: boolean;
  /** Longueur du plus long vide, en bandes. */
  vide: number;
  defauts: DefautPlante[];
};

/**
 * Ce qu'on peut dire d'une plante sans choisir de pot.
 *
 * À lire comme un signal à vérifier et non comme un verdict : faute de
 * couleur, cette mesure ne sépare pas un reste de pot d'un feuillage
 * retombant. Elle ne dispense donc pas de contrôler les paires — voir le
 * commentaire de `SEUILS.largeur`.
 */
export function jugerEmpreinte(
  socle: { rayon: number }, empreinte: Empreinte, seuils = SEUILS,
): Jugement {
  const { rayons } = empreinte.residu;
  let largeur = 0;
  let premier = -1;
  let dernier = -1;
  for (let i = 0; i < rayons.length; i += 1) {
    if (rayons[i] <= 0) continue;
    if (premier < 0) premier = i;
    dernier = i;
    const l = rayons[i] / socle.rayon;
    if (l > largeur) largeur = l;
  }

  // Le plus long vide ENTRE deux bandes pleines. Une bande isolée ne compte
  // pas : un maillage plus grossier que vingt-quatre bandes en laisse de
  // creuses sans qu'il manque pour autant de la matière, et le seuil de quatre
  // sommets par bande ne les attrape pas toutes. Les creux réels mesurés sur le
  // premier lot couvraient treize bandes et plus.
  let vide = 0;
  let courant = 0;
  for (let i = premier + 1; i < dernier; i += 1) {
    if (rayons[i] <= 0) courant += 1;
    else {
      if (courant > vide) vide = courant;
      courant = 0;
    }
  }
  if (courant > vide) vide = courant;

  const defauts: DefautPlante[] = [];
  if (largeur > seuils.largeur) defauts.push('matiere_large');

  return {
    largeur: Number(largeur.toFixed(4)),
    profondeur: empreinte.hauteur > 0
      ? Number((empreinte.residu.profondeur / empreinte.hauteur).toFixed(4))
      : 0,
    creux: vide >= VIDE_MIN,
    vide,
    defauts,
  };
}

// ── Contrôle d'une paire ───────────────────────────────────────────────────

export type Defaut = 'debordement' | 'sous_le_fond' | 'pot_trop_grand' | 'pot_trop_petit';

/** Ce que vaut une paire plante/pot, sans l'avoir regardée. */
export type Pose = {
  /** Facteur de la similitude : `socle.rayon / rebord.rayon`. */
  echelle: number;
  /** Hauteur du pot posé, rapportée à celle de la plante coupée. */
  proportion: number;
  /** Plus fort débordement du résidu hors de la paroi, en fraction du rayon du socle. */
  debordement: number;
  /** Où il se produit, en fraction de la hauteur du pot sous la lèvre. */
  ou: number;
  defauts: Defaut[];
};

/**
 * Contrôle une paire par le calcul.
 *
 * Deux défauts distincts, et les confondre ferait chercher la correction au
 * mauvais endroit. `debordement` : le résidu traverse la paroi, dans la
 * hauteur du pot. `sous_le_fond` : il descend plus bas que le fond du pot et
 * dépasse par-dessous — aucune échelle ne le corrige, puisque l'échelle est
 * imposée par le rayon du rebord.
 */
export function controlerPose(
  socle: { rayon: number }, rebord: { rayon: number; hauteur: number },
  empreinte: Empreinte, profilPot: Profil,
  seuils = SEUILS,
): Pose {
  const echelle = socle.rayon / rebord.rayon;
  const potProfondeur = rebord.hauteur * echelle;
  const { residu } = empreinte;

  let debordement = 0;
  let ou = 0;
  let sousLeFond = false;

  for (let i = 0; i < residu.rayons.length; i += 1) {
    const r = residu.rayons[i];
    if (r <= 0) continue;
    const d = ((i + 0.5) / BANDES) * residu.profondeur;
    if (d > potProfondeur) {
      sousLeFond = true;
      continue;
    }
    // Le profil du pot est dans SES unités : la profondeur se divise par
    // l'échelle pour l'y lire, et le rayon lu se multiplie par elle pour
    // revenir dans celles de la plante.
    const place = rayonA(profilPot, d / echelle) * echelle;
    const sortie = (r - place) / socle.rayon;
    if (sortie > debordement) {
      debordement = sortie;
      ou = potProfondeur > 0 ? d / potProfondeur : 0;
    }
  }

  const proportion = empreinte.hauteur > 0 ? potProfondeur / empreinte.hauteur : 0;
  const defauts: Defaut[] = [];
  if (debordement > seuils.debordement) defauts.push('debordement');
  if (sousLeFond) defauts.push('sous_le_fond');
  if (proportion > seuils.proportionMax) defauts.push('pot_trop_grand');
  else if (proportion < seuils.proportionMin) defauts.push('pot_trop_petit');

  return {
    echelle: Number(echelle.toFixed(4)),
    proportion: Number(proportion.toFixed(4)),
    debordement: Number(debordement.toFixed(4)),
    ou: Number(ou.toFixed(4)),
    defauts,
  };
}
