// Dépôt de l'atelier — file de tâches, graines, artefacts.
//
// Toute la logique d'état vit ici ; les routes ne font que de l'HTTP. Ce module
// ne connaît ni requête, ni réponse, ni cookie — il se teste sans serveur.
//
// Stockage : un JSON pour l'état, des fichiers pour les artefacts, sur un
// volume monté. Les GLB pèsent 30 à 42 Mo pièce et ne sortent jamais d'ici ;
// seuls les aperçus, quelques dizaines de kilooctets, sont servis à la revue.
//
// Le jour où R2 prendra les GLB, c'est `cheminArtefact` qui changera, et elle
// seule : rien d'autre ne manipule d'octets.
import { mkdirSync, readFileSync, readdirSync, renameSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { BANDES, type Empreinte, type Profil } from './profil';

export type EtatTache = 'en_attente' | 'en_cours' | 'livree' | 'echec';

export type Tache = {
  id: string;
  plante: string;
  image: string;
  graine: number | null;
  raison: string;
  /**
   * Cette plante n'a pas de pot : l'ouvrier saute la détection.
   *
   * Porté par la TÂCHE et non relu depuis la source au moment où l'ouvrier la
   * prend : le drapeau doit valoir ce qu'il valait au dépôt, sinon une tâche
   * déposée hier changerait de sens parce qu'on a coché une case ce matin.
   */
  sansPot?: boolean;
  etat: EtatTache;
  depose: number;
  pris?: number;
  /** Identité de la réservation en cours. Voir `prendre`. */
  reservation?: string;
  livre?: number;
  resultat?: Record<string, unknown>;
  erreur?: string;
};

/** Ce qu'une purge a libéré, ou pourquoi elle ne s'est pas faite. */
export type Purge = {
  quand: number;
  fichiers: number;
  octets: number;
  garde?: string;
  /** Renseignée quand rien n'a été effacé alors qu'on s'y attendait. */
  raison?: string;
};

/** Un pot de la bibliothèque, avec le rebord mesuré à l'ingestion. */
export type Pot = {
  fichier: string;
  rayon: number;
  y: number;
  x: number;
  z: number;
  hauteur: number;
  triangles: number;
  octets: number;
  depose: number;
  /**
   * Profil radial de la lèvre au fond.
   *
   * Absent sur les pots rangés avant le contrôle de pose : il est alors
   * remesuré à la demande, car relire un GLB à chaque affichage de la
   * bibliothèque coûterait plus que tout le reste de la page.
   */
  profil?: Profil;
};

/**
 * Empreinte d'une plante coupée, mise en cache.
 *
 * La mesurer demande de relire un maillage de soixante mégaoctets. Faite à
 * chaque affichage, et pour chaque plante, elle rendrait l'écran inutilisable ;
 * `octets` sert de clé de fraîcheur, pour qu'une régénération la refasse.
 */
export type EmpreinteRangee = Empreinte & {
  octets: number;
  mesure: number;
};

export type Etat = {
  taches: Tache[];
  /** Bibliothèque de pots, indexée par nom de fichier. */
  pots?: Record<string, Pot>;
  plantes: Record<string, {
    graines: number[];
    /**
     * `ecartee` est un verdict à part entière, et non une invalidation muette.
     * Invalider veut dire « refais-la » ; écarter veut dire « n'y reviens
     * pas ». Quand le défaut vient de la SOURCE — une image dans l'image, une
     * étagère modélisée — relancer sur une graine neuve ne peut que reproduire
     * le défaut, et c'était pourtant la seule issue offerte.
     */
    verdict?: 'validee' | 'invalidee' | 'ecartee';
    /**
     * Quand la coupe a été refaite APRÈS le verdict.
     *
     * Le verdict porte sur une coupe précise ; une recoupe la remplace, et le
     * jugement rendu ne s'applique donc plus à ce qu'on sert. On ne l'efface
     * pas pour autant — c'est un jugement humain, et `ecartee` vise la source,
     * pas la coupe. On note seulement que la coupe a changé depuis, pour que la
     * revue puisse le proposer sans rien détruire.
     *
     * Sans ce champ, une passe de recoupe est invisible : mesuré le 2026-10-07,
     * 76 plantes sur 78 portaient un verdict, donc la liste à revoir était vide
     * alors que 58 coupes venaient d'être refaites.
     */
    recoupee?: number;
    /**
     * La taille réelle de l'exemplaire, et son stade.
     *
     * Une plante n'est pas redimensionnable : elle a la taille qu'elle a.
     * `hauteurCm` est donc mesurée DEPUIS LA TERRE, pas depuis le bas du pot —
     * le pot change, la plante non, et c'est la plante qu'on pose.
     *
     * Le stade ne vaut que deux valeurs. Pour une plante d'intérieur, qui
     * n'atteint presque jamais sa taille de pleine terre, « adulte » et
     * « mature » se confondent en pratique et un troisième terme ne se
     * remplirait pas de façon fiable.
     */
    taille?: {
      hauteurCm: number;
      stade: 'jeune' | 'adulte';
      /** Le diamètre de pot qui a servi d'étalon, quand la hauteur en vient. */
      diametrePotCm?: number;
      pose: number;
    };
    coupe?: string;
    /**
     * L'opérateur a REGARDÉ les candidats et n'en veut aucun.
     *
     * Sans ce champ, « j'ai tranché pour le maillage entier » et « on ne m'a
     * rien proposé » s'écrivent pareil : une plante validée sans `coupe`. Le
     * seul indice était le motif de purge, qui n'était pas fait pour ça.
     *
     * Mesuré le 2026-10-20 : 6 plantes validées portaient un candidat
     * exploitable sans coupe retenue, et rien ne disait si c'était un choix.
     * Aucun écran ne permettait d'y revenir, `aRevoir` écartant toute plante
     * déjà jugée.
     */
    sansCoupe?: boolean;
    raison?: string;
    purge?: Purge;
  }>;
  /** Ce qu'on sait d'une source au-delà de son fichier. */
  sources?: Record<string, {
    sansPot?: boolean;
    /**
     * Diamètre du pot, en centimètres, tel que la fiche d'origine le donne.
     *
     * C'est un FAIT, pas un jugement : il sert à pré-remplir la saisie de
     * taille au lieu de la laisser à l'œil. Mesuré sur 26 plantes ayant les
     * deux, la fiche et la saisie humaine concordent 26 fois sur 26 — tandis
     * que l'estimation visuelle libre s'est trompée 2 fois sur 3.
     *
     * L'opérateur reste libre de le changer : la fiche propose, elle ne
     * décide pas.
     */
    diametrePotCm?: number;
  }>;
  /** Empreintes mesurées, indexées par « plante/fichier ». */
  empreintes?: Record<string, EmpreinteRangee>;
};

const VIDE: Etat = { taches: [], plantes: {} };

/**
 * Au-delà de ce délai, une tâche réservée retourne en attente.
 *
 * Une session Colab meurt après ~90 min d'inactivité et 12 h au maximum, et un
 * appel CUDA bloquant ne s'interrompt pas depuis le processus : c'est donc
 * l'expiration de réservation qui tient lieu de délai maximum par plante.
 * Elle ne vaut que parce que les graines sont consignées AU TIRAGE — sans quoi
 * la reprise retirerait la même graine et rebloquerait à l'identique.
 */
export const EXPIRATION_MS = 30 * 60 * 1000;

export function racine(): string {
  return process.env.GENERATOR_DATA_DIR || '/data/generator';
}

function cheminEtat(): string {
  return join(racine(), 'etat.json');
}

/** Dossier des artefacts d'une plante. Seule fonction qui connaît la disposition. */
export function cheminArtefact(plante: string, fichier: string): string {
  if (!/^[a-z0-9_-]+$/i.test(plante) || fichier.includes('/') || fichier.includes('..')) {
    throw new Error('chemin refusé');
  }
  return join(racine(), 'plantes', plante, fichier);
}

/**
 * Taille d'un artefact, ou `null` s'il manque.
 *
 * Sert à annoncer le poids d'un GLB avant de le charger dans la visionneuse :
 * ils pèsent 30 à 70 Mo, et ouvrir ça sans prévenir sur une connexion moyenne
 * donne une page qui semble figée.
 */
export function tailleArtefact(plante: string, fichier: string): number | null {
  try {
    const st = statSync(cheminArtefact(plante, fichier));
    return st.isFile() ? st.size : null;
  } catch {
    return null;
  }
}

/** Les GLB présents dans le dossier d'une plante. */
function glbPresents(plante: string): string[] {
  try {
    return readdirSync(join(racine(), 'plantes', plante))
      .filter((f) => f.toLowerCase().endsWith('.glb'));
  } catch {
    return [];
  }
}

/**
 * Efface les maillages devenus inutiles, en gardant celui qui est nommé.
 *
 * Les GLB de l'atelier sont de la sciure : 150 Mo par plante, et 37 Go pour le
 * catalogue de 246 — davantage que le disque entier du VPS. Une fois le verdict
 * rendu, le maillage brut de 1,7 million de triangles et le candidat rejeté
 * n'ont plus d'usage. Les aperçus, eux, restent : 1,4 Mo par plante, et ce sont
 * eux qui disent ce qui a été jugé.
 *
 * Ne touche QU'AUX `.glb`, et jamais à un fichier nommé dans `garder`.
 * N'échoue jamais : une purge ratée ne doit pas empêcher d'enregistrer un
 * verdict, qui est la seule chose irremplaçable ici.
 */
export function purger(plante: string, garder: string[]): { supprimes: string[]; octets: number } {
  const garde = new Set(garder.filter((g): g is string => Boolean(g)));
  const supprimes: string[] = [];
  let octets = 0;
  for (const f of glbPresents(plante)) {
    if (garde.has(f)) continue;
    try {
      const chemin = cheminArtefact(plante, f);
      octets += statSync(chemin).size;
      unlinkSync(chemin);
      supprimes.push(f);
    } catch {
      // Un fichier déjà parti, ou un nom que `cheminArtefact` refuse : on
      // passe. Rien ici ne justifie d'interrompre le verdict.
    }
  }
  return { supprimes, octets };
}

// ── Bibliothèque de pots ───────────────────────────────────────────────────
//
// Dossier frère de `sources/` et `plantes/`. Un pot n'appartient à aucune
// plante : c'est tout l'objet de la fonction, pouvoir le poser sous n'importe
// laquelle.

/** Dossier des pots. Mêmes gardes que les sources, extension GLB seule. */
export function cheminPot(fichier: string): string {
  if (fichier.includes('/') || fichier.includes('\\') || fichier.includes('..')) {
    throw new Error('chemin refusé');
  }
  if (!/^[a-z0-9_-]+\.glb$/i.test(fichier)) {
    throw new Error('nom de pot refusé');
  }
  return join(racine(), 'pots', fichier);
}

export function pots(): Pot[] {
  const etat = lire();
  let presents: string[];
  try {
    presents = readdirSync(join(racine(), 'pots'))
      .filter((f) => f.toLowerCase().endsWith('.glb'));
  } catch {
    return [];
  }
  // On n'annonce que ce qui est À LA FOIS sur le disque ET mesuré. Un fichier
  // sans mesure ne serait pas posable, et une mesure sans fichier ne serait
  // pas chargeable : dans les deux cas l'écran montrerait un pot qui ne
  // marche pas.
  return presents
    .map((f) => etat.pots?.[f])
    .filter((p): p is Pot => Boolean(p))
    .sort((a, b) => a.fichier.localeCompare(b.fichier, 'fr'));
}

/** Range un pot mesuré. Remplace la mesure précédente s'il en avait une. */
export function noterPot(pot: Pot) {
  return muter((etat) => {
    (etat.pots ??= {})[pot.fichier] = pot;
    return pot;
  });
}

// ── Recoupe d'une plante déjà livrée ───────────────────────────────────────
//
// La coupe part d'un GLB déjà généré : elle se reprend donc sans une seconde
// de GPU, et les GLB coupés portent tous leur liste de triangles d'origine, si
// bien que le maillage complet est reconstructible même après la purge. Quand
// la détection s'améliore, on repasse sur le lot au lieu de le régénérer.
//
// Ce qui change : les candidats, rien d'autre. Pas le verdict, que l'opérateur
// a rendu ; pas les graines, qui restent brûlées.

/** Une plante sur laquelle la coupe peut être reprise. */
export type Recoupable = {
  id: string;
  plante: string;
  /**
   * Candidats livrés, par NOM de fichier : la disposition du volume ne sort pas.
   *
   * Ce que l'ouvrier a LIVRÉ, y compris les fichiers que la purge a depuis
   * emportés : c'est le journal de la passe, et il doit rester fidèle à ce qui
   * a été proposé. Seule `source` est garantie présente.
   */
  candidats: Array<{ voie: string; fichier: string; aireRetiree: number | null }>;
  /**
   * Le maillage à redescendre pour refaire la coupe, par NOM de fichier.
   *
   * Garanti SUR LE VOLUME au moment du relevé. Le premier candidat qui y est
   * encore quand il en reste un — les GLB coupés portent tous leur liste de
   * triangles d'origine, donc n'importe lequel suffit à retrouver l'entier —,
   * le maillage complet sinon.
   */
  source: string;
  /**
   * `source` est le maillage complet, et non un candidat.
   *
   * L'ouvrier doit le savoir, parce que le traitement n'est pas le même : il
   * n'y a aucune coupe antérieure à défaire avant de chercher le pot.
   */
  sourceEntiere: boolean;
  /** Les candidats portent-ils déjà une mesure de résidu, donc la coupe récente ? */
  mesure: boolean;
};

/**
 * Ce que la passe de recoupe a de quoi reprendre.
 *
 * Une liste à part de `/taches`, qui retire volontairement `resultat` pour ne
 * pas diffuser les chemins d'artefacts. L'ouvrier a besoin des NOMS de
 * fichiers pour redescendre un maillage ; il n'a pas besoin de savoir où le
 * volume les range, et ne l'apprend pas ici non plus.
 *
 * Tout ce qui est livré avec au moins un maillage, verdict compris : une coupe
 * validée se reprend aussi, puisque c'est la coupe qui s'est améliorée et non
 * le jugement qui a changé.
 *
 * Les plantes dont la détection n'a rien trouvé en sont. La source d'une
 * recoupe est un MAILLAGE, et le maillage complet en est un — c'est même celui
 * dont les candidats sont dérivés, donc la meilleure source possible. Mesuré
 * le 2026-10-20 sur le lot de 68 : les 12 plantes livrées avec
 * `candidats_pot: []` gardent toutes leur GLB complet, 42 à 65 Mo et près d'un
 * million de triangles. La purge n'avait rien à effacer chez elles, puisqu'il
 * n'y avait qu'un maillage à garder. Les écarter réclamait une régénération
 * GPU — 165 s et une graine brûlée — pour un fichier déjà sur le volume.
 *
 * C'EST LE VOLUME QUI TRANCHE, et non l'état. `trancher` ne conserve que la
 * coupe retenue et laisse les noms des autres candidats dans l'état : celui-ci
 * décrit ce qui a été livré, jamais ce qui reste. Mesuré le 2026-10-20 sur les
 * 64 tâches livrées avec candidat, 5 annonçaient un premier candidat absent du
 * volume — et les trois populations ne se traitent pas de la même façon :
 *
 * - un autre candidat était là (1 plante) : c'est lui la source ;
 * - tous les candidats avaient disparu mais le maillage complet était là
 *   (1 plante) : le repli joue, même si l'état annonce des candidats ;
 * - plus rien sur le disque (3 plantes) : la tâche est écartée. Les annoncer
 *   faisait télécharger dans le vide, et l'ouvrier les comptait en `sautees`
 *   sans que personne ne sache pourquoi. Celles-là demandent une régénération.
 */
export function recoupables(): Recoupable[] {
  const etat = lire();
  const sorties: Recoupable[] = [];
  for (const t of etat.taches) {
    if (t.etat !== 'livree') continue;
    // Pas de pot : rien à retirer, donc rien à reprendre.
    //
    // La source est relue MAINTENANT, contrairement au drapeau de la tâche qui
    // vaut ce qu'il valait au dépôt (voir `Tache.sansPot`). Les deux règles ne
    // se contredisent pas : geler le drapeau protège la reproductibilité d'une
    // GÉNÉRATION, alors qu'une recoupe est une décision prise aujourd'hui, avec
    // ce qu'on sait aujourd'hui. Cocher la case ce matin doit donc sortir la
    // plante de la file ce matin.
    //
    // Sans cette garde, l'ouvrier redescend le maillage — 55 Mo mesurés sur le
    // Yucca Rostrata — et fait tourner une détection dont la réponse ne peut
    // être qu'absurde. La boucle de livraison évitait déjà ce travail inutile ;
    // la passe de recoupe, non.
    // `nomFichier` et non `t.image` tel quel : `deposer` enregistre l'image
    // telle qu'on la lui donne, alors que `sources` est indexé par nom nu.
    const image = nomFichier(t.image);
    if (t.sansPot || (image && etat.sources?.[image]?.sansPot)) continue;
    const bruts = Array.isArray(t.resultat?.candidats_pot) ? t.resultat.candidats_pot : [];
    const candidats = bruts
      .map((b) => {
        const c = (b ?? {}) as Record<string, unknown>;
        return {
          voie: typeof c.voie === 'string' ? c.voie : 'inconnue',
          fichier: nomFichier(c.fichier),
          aireRetiree: nombre(c.aire_retiree),
        };
      })
      .filter((c): c is { voie: string; fichier: string; aireRetiree: number | null } =>
        c.fichier !== null);

    // Un seul relevé du dossier par tâche : les noms viennent de l'état, la
    // présence du disque, et on ne nomme à l'ouvrier qu'un fichier qu'il
    // pourra réellement redescendre.
    const presents = new Set(glbPresents(t.plante));
    const coupe = candidats.find((c) => presents.has(c.fichier));
    const complet = coupe ? null : nomFichier(t.resultat?.glb);
    const entier = complet !== null && presents.has(complet);
    if (!coupe && !entier) continue;

    sorties.push({
      id: t.id, plante: t.plante, candidats,
      source: coupe ? coupe.fichier : complet!,
      sourceEntiere: entier,
      // `[].every` vaut `true` : sans la garde sur le nombre, une plante sans
      // candidat s'annoncerait déjà mesurée, donc hors du compte `aRecouper`,
      // alors qu'elle est précisément celle qui reste à recouper.
      mesure: candidats.length > 0
        && bruts.every((b) => Boolean((b as Record<string, unknown>)?.residu)),
    });
  }
  return sorties;
}

export type Recoupe =
  | { ok: true; candidats: number; empreintes: number; coupePerdue: boolean;
      /** La plante portait un verdict : il ne juge plus la coupe en service. */
      aRejuger: boolean }
  | { ok: false; raison: 'introuvable' | 'pas_livree' };

export function recouper(id: string, candidats: unknown[]): Promise<Recoupe> {
  return muter((etat) => {
    const t = etat.taches.find((x) => x.id === id);
    if (!t) return { ok: false, raison: 'introuvable' } as Recoupe;
    // Une tâche en cours ou en échec n'a pas de maillage à recouper, et une
    // tâche en attente n'en a pas encore.
    if (t.etat !== 'livree') return { ok: false, raison: 'pas_livree' } as Recoupe;

    (t.resultat ??= {}).candidats_pot = candidats;

    // Les empreintes mises en cache décrivent les ANCIENNES coupes. La taille
    // du fichier suffirait à les périmer, mais la recoupe réécrit le GLB sous
    // le même nom et peut tomber sur la même taille : on les retire donc
    // franchement, plutôt que de parier sur un octet de différence.
    let empreintes = 0;
    for (const cle of Object.keys(etat.empreintes ?? {})) {
      if (cle.startsWith(`${t.plante}/`)) {
        delete etat.empreintes![cle];
        empreintes += 1;
      }
    }

    // La coupe retenue à la revue peut ne plus figurer parmi les candidats :
    // la nouvelle détection retire davantage, et la fenêtre de vraisemblance
    // peut écarter une voie qu'elle acceptait. Le dire plutôt que de laisser
    // l'atelier retomber silencieusement sur le premier candidat.
    const noms = new Set(candidats.map(
      (c) => nomFichier((c as Record<string, unknown>)?.fichier)));
    const p = etat.plantes[t.plante];
    const coupe = p?.coupe;

    // Le verdict reste, la coupe qu'il jugeait n'est plus là. On le dit, au
    // lieu de laisser la plante disparaître de la revue avec une coupe que
    // personne n'a vue.
    if (p?.verdict) p.recoupee = Date.now();

    return {
      ok: true, candidats: candidats.length, empreintes,
      coupePerdue: Boolean(coupe) && !noms.has(coupe!),
      aRejuger: Boolean(p?.verdict),
    } as Recoupe;
  });
}

// ── Empreintes des plantes ─────────────────────────────────────────────────

/** Clé de cache d'une empreinte : la plante et le GLB coupé qui la porte. */
export function cleEmpreinte(plante: string, fichier: string): string {
  return `${plante}/${fichier}`;
}

export function empreinteRangee(
  plante: string, fichier: string, octets: number,
): EmpreinteRangee | null {
  const e = lire().empreintes?.[cleEmpreinte(plante, fichier)];
  // La taille du fichier fait foi : une régénération sous une autre graine
  // rend l'empreinte précédente fausse, et rien d'autre ne le signalerait.
  return e && e.octets === octets ? e : null;
}

export function noterEmpreinte(
  plante: string, fichier: string, empreinte: EmpreinteRangee,
) {
  return muter((etat) => {
    (etat.empreintes ??= {})[cleEmpreinte(plante, fichier)] = empreinte;
    return empreinte;
  });
}

export function supprimerPot(fichier: string) {
  return muter((etat) => {
    try {
      unlinkSync(cheminPot(fichier));
    } catch {
      // Déjà parti : on nettoie quand même la mesure, qui ne sert plus.
    }
    if (!etat.pots?.[fichier]) return false;
    delete etat.pots[fichier];
    return true;
  });
}

// ── Images sources ─────────────────────────────────────────────────────────
//
// Elles vivaient sur Drive pendant le spike, et `tache.image` portait un chemin
// Colab. L'atelier ne pouvait alors pas déposer de tâche : il aurait écrit un
// chemin qu'il ne pouvait ni voir ni vérifier. Sur le volume, il le peut.
//
// Une source par plante, nommée par elle : c'est le nom de la plante qui fait
// l'identité dans tout l'atelier, de la file aux artefacts.

const EXT_SOURCE = new Set(['.png', '.jpg', '.jpeg', '.webp']);

/** Dossier des sources. Frère de `plantes/`, pas dedans : ce n'est pas un artefact. */
export function cheminSource(fichier: string): string {
  if (fichier.includes('/') || fichier.includes('\\') || fichier.includes('..')) {
    throw new Error('chemin refusé');
  }
  const ext = fichier.slice(fichier.lastIndexOf('.')).toLowerCase();
  if (!EXT_SOURCE.has(ext) || !/^[a-z0-9_-]+\.[a-z]+$/i.test(fichier)) {
    throw new Error('nom de source refusé');
  }
  return join(racine(), 'sources', fichier);
}

/** Nom de plante porté par un fichier source. */
export function planteDe(fichier: string): string {
  return fichier.slice(0, fichier.lastIndexOf('.'));
}

export type Source = {
  plante: string;
  fichier: string;
  octets: number;
  modifie: number;
  /** Une tâche non terminée existe déjà pour cette plante. */
  enFile: boolean;
  verdict?: 'validee' | 'invalidee' | 'ecartee';
  /** Cette plante n'a pas de pot : on ne cherchera pas à lui en retirer un. */
  sansPot: boolean;
};

/**
 * Les sources présentes, avec ce que l'état sait de chacune.
 *
 * Le croisement se fait ici et pas dans la page : savoir qu'une plante est déjà
 * en file est ce qui évite de la déposer deux fois, et c'est au dépôt de le
 * savoir, pas à l'écran.
 */
export function sources(): Source[] {
  const etat = lire();
  let fichiers: string[];
  try {
    fichiers = readdirSync(join(racine(), 'sources'));
  } catch {
    return [];
  }
  const vivantes = new Set(
    etat.taches.filter((t) => t.etat === 'en_attente' || t.etat === 'en_cours').map((t) => t.plante),
  );
  return fichiers
    .filter((f) => EXT_SOURCE.has(f.slice(f.lastIndexOf('.')).toLowerCase()))
    .map((fichier) => {
      const plante = planteDe(fichier);
      let octets = 0;
      let modifie = 0;
      try {
        const st = statSync(join(racine(), 'sources', fichier));
        octets = st.size;
        modifie = st.mtimeMs;
      } catch {
        // Fichier disparu entre le listage et la mesure : on le rend quand même,
        // la page affichera une taille nulle plutôt que de tout perdre.
      }
      return {
        plante, fichier, octets, modifie,
        enFile: vivantes.has(plante),
        verdict: etat.plantes[plante]?.verdict,
        sansPot: Boolean(etat.sources?.[fichier]?.sansPot),
      };
    })
    .sort((a, b) => a.plante.localeCompare(b.plante, 'fr'));
}

/**
 * Marque une source comme étant sans pot, ou le défait.
 *
 * L'ouvrier saute alors la détection, et la plante n'entre pas dans le
 * périmètre des pots personnalisés. Un palmier hors pot a reçu une proposition
 * de coupe sur le premier lot : la question n'aurait pas dû être posée.
 */
export function marquerSansPot(fichier: string, sansPot: boolean) {
  return muter((etat) => {
    const s = (etat.sources ??= {});
    if (sansPot) {
      (s[fichier] ??= {}).sansPot = true;
    } else {
      // Ne retirer QUE ce drapeau. Effacer l'entrée emporterait le diamètre
      // de la fiche, qui n'a rien à voir avec lui — décocher « sans pot »
      // perdrait silencieusement une donnée d'une autre nature.
      const e = s[fichier];
      if (e) {
        delete e.sansPot;
        // Une entrée vide ne porte plus d'information : on la retire pour que
        // l'état ne se peuple pas de coquilles.
        if (Object.keys(e).length === 0) delete s[fichier];
      }
    }
    return sansPot;
  });
}

/**
 * Enregistre le diamètre de pot donné par la fiche d'origine d'une source.
 *
 * Séparé de la saisie de taille à dessein : celle-ci est une décision de
 * l'opérateur, celui-là un fait rattaché à la source. Les confondre ferait
 * passer une donnée reçue pour un jugement, et on ne saurait plus lequel des
 * deux a produit une valeur.
 */
export function noterDiametreFiche(fichier: string, diametreCm: number | null) {
  return muter((etat) => {
    const s = (etat.sources ??= {});
    if (diametreCm === null || !Number.isFinite(diametreCm) || diametreCm <= 0) {
      const e = s[fichier];
      if (e) {
        delete e.diametrePotCm;
        if (Object.keys(e).length === 0) delete s[fichier];
      }
      return null;
    }
    const d = Math.round(diametreCm * 10) / 10;
    (s[fichier] ??= {}).diametrePotCm = d;
    return d;
  });
}

export type RetraitSource =
  | { ok: true; tachesRetirees: number }
  | { ok: false; raison: 'introuvable' | 'tache_en_cours' };

/**
 * Retire une source ET ses tâches en attente.
 *
 * Les laisser derrière soi n'était pas neutre : l'ouvrier les prenait et
 * échouait sur `image introuvable`, tardivement et par un échec plutôt que par
 * une décision. Constaté sur `Haworthia_Mix` et `Maranta_Leuconeura_Vert`.
 *
 * Refusé tant qu'une tâche est EN COURS : on ne tire pas le tapis sous les
 * pieds d'un ouvrier qui a déjà engagé le GPU dessus.
 *
 * Les artefacts déjà produits ne sont pas touchés : ils restent la trace de ce
 * qui a été jugé.
 */
export function supprimerSource(fichier: string): Promise<RetraitSource> {
  return muter((etat): RetraitSource => {
    const plante = planteDe(fichier);
    if (etat.taches.some((t) => t.plante === plante && t.etat === 'en_cours')) {
      return { ok: false, raison: 'tache_en_cours' };
    }
    try {
      unlinkSync(cheminSource(fichier));
    } catch {
      return { ok: false, raison: 'introuvable' };
    }
    const avant = etat.taches.length;
    etat.taches = etat.taches.filter(
      (t) => !(t.plante === plante && t.etat === 'en_attente'),
    );
    delete etat.sources?.[fichier];
    return { ok: true, tachesRetirees: avant - etat.taches.length };
  });
}

export function lire(): Etat {
  try {
    const brut = JSON.parse(readFileSync(cheminEtat(), 'utf8'));
    return {
      taches: brut.taches ?? [], plantes: brut.plantes ?? {},
      pots: brut.pots ?? {}, sources: brut.sources ?? {},
      empreintes: brut.empreintes ?? {},
    };
  } catch {
    return structuredClone(VIDE);
  }
}

/**
 * Écriture atomique : fichier temporaire puis renommage.
 *
 * Un `writeFileSync` direct laisse un JSON tronqué si le conteneur est arrêté
 * en plein milieu — et la file devient alors illisible, donc perdue. Le
 * renommage, lui, est atomique sur le même système de fichiers.
 */
function ecrire(etat: Etat) {
  const dossier = racine();
  mkdirSync(dossier, { recursive: true });
  const tmp = join(dossier, `.etat.${process.pid}.tmp`);
  writeFileSync(tmp, JSON.stringify(etat, null, 2), 'utf8');
  renameSync(tmp, cheminEtat());
}

/**
 * Sérialise les mutations.
 *
 * Node est mono-thread, mais une mutation est un lire-modifier-écrire traversé
 * par des `await` : deux requêtes concurrentes peuvent lire le même état et
 * la seconde écraserait la première. C'est précisément ce qui ferait prendre
 * la MÊME tâche à deux ouvriers.
 */
let chaine: Promise<unknown> = Promise.resolve();

export function muter<T>(operation: (etat: Etat) => T): Promise<T> {
  const suivant = chaine.then(() => {
    const etat = lire();
    const resultat = operation(etat);
    ecrire(etat);
    return resultat;
  });
  chaine = suivant.catch(() => undefined);
  return suivant;
}

// ── Opérations ─────────────────────────────────────────────────────────────

function identifiant(): string {
  return Math.random().toString(16).slice(2, 10) + Date.now().toString(16).slice(-4);
}

export function deposer(
  plante: string, image: string, raison = 'initiale',
  graine: number | null = null, sansPot = false,
) {
  return muter((etat) => {
    const tache: Tache = {
      id: identifiant(), plante, image, graine, raison,
      ...(sansPot ? { sansPot: true } : {}),
      etat: 'en_attente', depose: Date.now(),
    };
    etat.taches.push(tache);
    return tache;
  });
}

/** Remet en attente les réservations expirées. Appelé avant chaque prise. */
function reprendreExpirees(etat: Etat, maintenant: number): number {
  let reprises = 0;
  for (const t of etat.taches) {
    if (t.etat === 'en_cours' && maintenant - (t.pris ?? 0) > EXPIRATION_MS) {
      t.etat = 'en_attente';
      t.raison = 'reservation_expiree';
      delete t.pris;
      reprises += 1;
    }
  }
  return reprises;
}

export function prendre(maintenant = Date.now()) {
  return muter((etat) => {
    reprendreExpirees(etat, maintenant);
    const tache = etat.taches.find((t) => t.etat === 'en_attente');
    if (!tache) return null;
    tache.etat = 'en_cours';
    tache.pris = maintenant;
    // Chaque réservation reçoit une identité, et la livraison doit la
    // présenter. L'état seul ne suffit pas : une tâche expirée puis reprise
    // garde son identifiant, et l'ouvrier bloqué livrerait par-dessus le
    // travail de celui qui a repris — sans que rien ne le signale.
    tache.reservation = identifiant();
    // L'exclusion est relue MAINTENANT : une tâche déposée hier doit tenir
    // compte des graines consommées depuis.
    return { ...tache, exclure: etat.plantes[tache.plante]?.graines ?? [] };
  });
}

export function livrer(id: string, reservation: string, resultat: Record<string, unknown>) {
  return muter((etat) => {
    const t = etat.taches.find((x) => x.id === id);
    // Réservation expirée et tâche reprise ailleurs : le résultat arrive trop
    // tard. On le jette — une génération perdue vaut mieux qu'un écrasement.
    if (!t || t.etat !== 'en_cours' || t.reservation !== reservation) return false;
    delete t.reservation;
    t.etat = 'livree';
    t.resultat = resultat;
    t.livre = Date.now();
    // Le serveur tient son invariant lui-même : une graine qui a produit un
    // maillage ne doit jamais être retirée. L'ouvrier la consigne déjà avant
    // de générer, mais si cet appel-là échoue pendant que la génération
    // réussit, la graine rejetée disparaîtrait de l'historique — et une
    // invalidation en revue la rejouerait à l'identique.
    const graine = resultat.graine;
    if (typeof graine === 'number' && Number.isFinite(graine)) {
      const p = (etat.plantes[t.plante] ??= { graines: [] });
      if (!p.graines.includes(graine)) p.graines.push(graine);
    }
    return true;
  });
}

export function echouer(id: string, reservation: string, erreur: string) {
  return muter((etat) => {
    const t = etat.taches.find((x) => x.id === id);
    if (!t || t.reservation !== reservation) return false;
    delete t.reservation;
    t.etat = 'echec';
    t.erreur = erreur.slice(0, 500);
    return true;
  });
}

export function historique(plante: string): number[] {
  return lire().plantes[plante]?.graines ?? [];
}

/**
 * Consigne une graine. Appelée AVANT la génération, jamais après.
 *
 * `run()` est déterministe à graine fixée : une graine rejouée reproduit
 * exactement le maillage qu'on vient de rejeter. Consigner à la livraison
 * perdait les graines rejetées, et n'enregistrait rien du tout en cas d'échec
 * ou d'expiration — une relance retirait alors la même graine et reproduisait
 * la panne, indéfiniment.
 */
export function noterGraine(plante: string, graine: number) {
  return muter((etat) => {
    const p = (etat.plantes[plante] ??= { graines: [] });
    if (!p.graines.includes(graine)) p.graines.push(graine);
    return p.graines.length;
  });
}

/**
 * Réduit un chemin livré par l'ouvrier à son seul nom de fichier.
 *
 * L'ouvrier consigne des chemins ABSOLUS de sa propre machine — `/content/...`
 * sur Colab, un montage Drive ailleurs. Ils n'ont aucun sens ici, et les
 * suivre serait pire que sans effet : c'est une valeur venue du réseau qui
 * désignerait un fichier à lire. On n'en garde que le nom, et `cheminArtefact`
 * le valide ensuite.
 */
export function nomFichier(chemin: unknown): string | null {
  if (typeof chemin !== 'string' || !chemin) return null;
  const morceaux = chemin.split(/[\\/]/);
  // Un segment fait uniquement de points (`.`, `..`, `....`) n'a rien à faire
  // dans un chemin d'artefact. N'en garder que le nom final serait sûr — le
  // basename reste dans le dossier de la plante, et un fichier absent donne
  // un 404 — mais ce serait traiter comme normal ce qui ne l'est pas, et
  // masquer un ouvrier qui envoie n'importe quoi. On refuse.
  if (morceaux.some((m) => /^\.+$/.test(m))) return null;
  const nom = morceaux.pop() || '';
  return /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(nom) && !nom.includes('..') ? nom : null;
}

/**
 * Où poser un pot sous cette plante, en unités du modèle.
 *
 * C'est ce qui rendra possible une fonction de pot personnalisé : un pot de la
 * bibliothèque se met à l'échelle sur `rayon`, se centre sur (x, z) et pose son
 * rebord à `y`. Sans ces valeurs, il faudrait les redécouvrir à l'exécution,
 * sur un maillage d'un million de triangles, dans l'app.
 */
export type Socle = {
  x: number;
  z: number;
  y: number;
  rayon: number;
  hauteurModele: number;
};

/**
 * Le résidu tel que l'ouvrier l'a mesuré, le vert à part.
 *
 * Mesuré là-bas et pas ici, parce que là-bas seulement on connaît la couleur :
 * l'atelier ne lit que les positions du GLB et ne sait pas distinguer un reste
 * de pot d'un feuillage qui retombe. Absent sur les plantes livrées avant
 * cette mesure, et l'atelier retombe alors sur la sienne, aveugle à la
 * couleur.
 */
export type ResiduLivre = {
  profondeur: number;
  /** Hauteur du maillage GARDÉ, pour juger de la proportion du pot posé. */
  hauteur: number;
  /** Rayons par bande de ce qui n'est pas vert : les restes de pot. */
  pot: number[];
  /** Rayons par bande du vert : du feuillage, qui pend hors du pot. */
  vert: number[];
};

export type Candidat = {
  voie: string;
  sommet: number | null;
  aireRetiree: number | null;
  confianceParoi: number | null;
  /** Nom du GLB coupé, pour la visionneuse. */
  fichier: string | null;
  /** Aperçus de CE candidat, rendus par l'ouvrier. */
  apercus: string[];
  /** `null` tant que la plante date d'avant la mesure du socle. */
  socle: Socle | null;
  /** `null` tant que la plante date d'avant la mesure du résidu. */
  residu: ResiduLivre | null;
};

export type AVoir = {
  plante: string;
  graine: number | null;
  accepte: boolean;
  essai: number | null;
  secondes: number | null;
  triangles: number | null;
  octets: number | null;
  dominante: number | null;
  grosses: number | null;
  plans: number | null;
  apercus: string[];
  glb: string | null;
  candidats: Candidat[];
  arbitrage: boolean;
  livre: number | null;
  /**
   * Le verdict déjà rendu, quand la coupe a été refaite depuis.
   *
   * `undefined` pour une plante jamais jugée — le cas ordinaire de la revue.
   * Renseigné, il dit que l'opérateur a déjà tranché, mais sur une coupe qui
   * n'est plus celle qu'on sert.
   */
  jugee?: { verdict: 'validee' | 'invalidee' | 'ecartee'; recoupee: number };
};

function nombre(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/**
 * Le socle, ou `null`.
 *
 * Tout ou rien : un socle amputé d'une coordonnée poserait un pot de travers,
 * ce qui est pire qu'un pot absent. Les plantes générées avant cette mesure
 * n'en ont pas, et c'est un cas normal, pas une erreur.
 */
function socle(brut: unknown): Socle | null {
  const s = (brut ?? {}) as Record<string, unknown>;
  const champs = ['x', 'z', 'y', 'rayon', 'hauteur_modele'] as const;
  const lus = champs.map((k) => nombre(s[k]));
  if (lus.some((v) => v === null)) return null;
  const [x, z, y, rayon, hauteurModele] = lus as number[];
  // Un rayon nul ou négatif ne décrit aucun pot : la voie couleur ne mesure
  // aucune révolution et rend 0. Mieux vaut pas de socle qu'un socle faux.
  if (rayon <= 0) return null;
  return { x, z, y, rayon, hauteurModele };
}

/**
 * Le résidu livré, ou `null`.
 *
 * Tout ou rien, comme le socle : un profil amputé d'une bande ferait juger la
 * plante sur une mesure trompeuse, ce qui est pire que de ne pas la juger.
 */
function residuLivre(brut: unknown, bandes: number): ResiduLivre | null {
  const d = (brut ?? {}) as Record<string, unknown>;
  const prof = nombre(d.profondeur);
  const haut = nombre(d.hauteur);
  if (prof === null || haut === null || prof < 0 || haut <= 0) return null;
  const bande = (v: unknown): number[] | null => {
    if (!Array.isArray(v) || v.length !== bandes) return null;
    const lus = v.map(nombre);
    return lus.some((x) => x === null || x < 0) ? null : (lus as number[]);
  };
  const pot = bande(d.pot);
  const vert = bande(d.vert);
  if (!pot || !vert) return null;
  return { profondeur: prof, hauteur: haut, pot, vert };
}

function candidat(brut: unknown): Candidat {
  const c = (brut ?? {}) as Record<string, unknown>;
  return {
    voie: typeof c.voie === 'string' ? c.voie : 'inconnue',
    sommet: nombre(c.sommet),
    aireRetiree: nombre(c.aire_retiree),
    confianceParoi: nombre(c.confiance_paroi),
    fichier: nomFichier(c.fichier),
    apercus: (Array.isArray(c.apercus) ? c.apercus : []).map(nomFichier).filter((n): n is string => n !== null),
    socle: socle(c.socle),
    residu: residuLivre(c.residu, BANDES),
  };
}

/**
 * Ce que la revue affiche d'une tâche livrée.
 *
 * C'est le dépôt qui connaît la disposition des artefacts, pas la page. Celle-ci
 * ne voit que des noms de fichiers, qu'elle passe à la route de service.
 */
function vueDe(etat: Etat, t: Tache): AVoir {
  const r = t.resultat ?? {};
  const p = etat.plantes[t.plante];
  return {
    plante: t.plante,
    graine: nombre(r.graine),
    accepte: Boolean(r.accepte),
    essai: nombre(r.essai),
    secondes: nombre(r.secondes),
    triangles: nombre(r.triangles),
    octets: nombre(r.octets),
    dominante: nombre(r.dominante),
    grosses: nombre(r.grosses),
    plans: nombre(r.plans),
    apercus: (Array.isArray(r.apercus) ? r.apercus : [])
      .map(nomFichier).filter((n): n is string => n !== null),
    glb: nomFichier(r.glb),
    candidats: (Array.isArray(r.candidats_pot) ? r.candidats_pot : []).map(candidat),
    arbitrage: Boolean(r.arbitrage_requis),
    livre: nombre(t.livre),
    ...(p?.verdict && p.recoupee
      ? { jugee: { verdict: p.verdict, recoupee: p.recoupee } }
      : {}),
  };
}

/** Plantes livrées dont le verdict reste à rendre. */
export function aRevoir(): AVoir[] {
  const etat = lire();
  return etat.taches
    .filter((t) => {
      if (t.etat !== 'livree') return false;
      const p = etat.plantes[t.plante];
      // Jamais jugée : c'est le cas ordinaire. Jugée mais recoupée depuis : le
      // verdict ne porte plus sur la coupe en service, on la repropose.
      return !p?.verdict || Boolean(p.recoupee);
    })
    .map((t) => vueDe(etat, t));
}

/**
 * Plantes validées auxquelles aucune coupe n'a été retenue, alors qu'un
 * candidat exploitable existe encore sur le volume.
 *
 * Ce n'est pas une erreur : `AUCUN` est un choix à part entière dans l'écran
 * d'arbitrage, et retenir le maillage entier avec son pot d'origine est parfois
 * la bonne décision. Mais `trancher` ne consigne pas la différence entre « j'ai
 * regardé et je n'en veux aucun » et « on ne m'a rien proposé » : dans les deux
 * cas la plante ressort sans `coupe`. Le seul indice est le motif de purge, qui
 * dit avoir voulu garder le maillage entier.
 *
 * Donc on les repropose au lieu de les laisser dans un état qu'on ne sait plus
 * relire. Le verdict n'est PAS remis en cause — la plante reste validée ; seule
 * la coupe est en question.
 *
 * Elles sont exclues de `aRevoir`, qui écarte toute plante déjà jugée : sans
 * cette seconde file, l'écran de revue leur répond 404 et il n'existe aucun
 * chemin pour retenir une coupe après coup.
 */
export function coupeNonRetenue(): AVoir[] {
  const etat = lire();
  const presents = new Map<string, string[]>();
  return etat.taches
    .filter((t) => {
      if (t.etat !== 'livree') return false;
      const p = etat.plantes[t.plante];
      if (p?.verdict !== 'validee' || p.coupe || p.sansCoupe || p.recoupee) return false;
      // Un candidat dont le fichier a été purgé ne se retient plus : le
      // proposer mènerait à une visionneuse vide. On relit le volume, parce
      // que l'état annonce ce que l'ouvrier a livré, pas ce qui reste.
      const bruts = Array.isArray(t.resultat?.candidats_pot) ? t.resultat.candidats_pot : [];
      if (!presents.has(t.plante)) presents.set(t.plante, glbPresents(t.plante));
      const surDisque = presents.get(t.plante)!;
      return bruts.map(candidat).some(
        (c) => c.fichier !== null && c.socle !== null && surDisque.includes(c.fichier),
      );
    })
    .map((t) => vueDe(etat, t));
}

/** Une plante sur laquelle on peut essayer un pot. */
export type Posable = {
  plante: string;
  /** GLB à charger : la coupe retenue, ou le premier candidat si rien n'est tranché. */
  fichier: string;
  socle: Socle;
  /** Le résidu mesuré par l'ouvrier, quand la plante en porte un. */
  residu: ResiduLivre | null;
  verdict?: 'validee' | 'invalidee' | 'ecartee';
};

/**
 * Les plantes auxquelles on peut poser un pot.
 *
 * Il en faut deux choses : un maillage SANS son pot, et un socle qui dise où
 * poser le nouveau. Une plante validée sans retrait n'entre donc pas — elle a
 * gardé son pot d'origine, il n'y a pas de place pour un autre.
 *
 * Les plantes encore en revue sont incluses : on veut pouvoir essayer un pot
 * AVANT de trancher, puisque c'est parfois ce qui décide de la coupe à retenir.
 */
export function posables(): Posable[] {
  const etat = lire();
  const sorties: Posable[] = [];
  for (const t of etat.taches) {
    if (t.etat !== 'livree') continue;
    const p = etat.plantes[t.plante];
    // Invalidée : une autre génération viendra. Écartée : on n'y revient pas.
    // Dans les deux cas, pas de pot à lui poser.
    if (p?.verdict === 'invalidee' || p?.verdict === 'ecartee') continue;

    const bruts = Array.isArray(t.resultat?.candidats_pot) ? t.resultat.candidats_pot : [];
    const candidats = bruts.map(candidat).filter((c) => c.fichier && c.socle);
    if (candidats.length === 0) continue;

    // La coupe retenue prime : c'est elle qui sera livrée. Sinon le premier
    // candidat, pour pouvoir essayer avant de trancher.
    const retenu = candidats.find((c) => c.fichier === p?.coupe) ?? candidats[0];
    sorties.push({
      plante: t.plante,
      fichier: retenu.fichier!,
      socle: retenu.socle!,
      residu: retenu.residu,
      verdict: p?.verdict,
    });
  }
  return sorties.sort((a, b) => a.plante.localeCompare(b.plante, 'fr'));
}

/** Compteurs du tableau de bord. */
export function bilan() {
  const etat = lire();
  const par = (e: EtatTache) => etat.taches.filter((t) => t.etat === e).length;
  const plantes = Object.entries(etat.plantes);
  return {
    enAttente: par('en_attente'),
    enCours: par('en_cours'),
    livrees: par('livree'),
    echecs: par('echec'),
    validees: plantes.filter(([, p]) => p.verdict === 'validee').length,
    invalidees: plantes.filter(([, p]) => p.verdict === 'invalidee').length,
    grainesBrulees: plantes.reduce((n, [, p]) => n + p.graines.length, 0),
    octetsLiberes: plantes.reduce((n, [, p]) => n + (p.purge?.octets ?? 0), 0),
  };
}

/**
 * Enregistre un verdict humain. Une invalidation redépose une tâche : c'est le
 * seul chemin qui remonte vers le GPU, et il ne sert qu'au défaut qu'aucune
 * métrique ne voit — la géométrie inventée mais plausible.
 */
export type Verdict = 'validee' | 'invalidee' | 'ecartee';

export function trancher(plante: string, verdict: Verdict, coupe?: string, raison?: string) {
  return muter((etat) => {
    const p = (etat.plantes[plante] ??= { graines: [] });
    const valide = verdict === 'validee';
    p.verdict = verdict;
    // Le verdict qu'on vient de rendre porte sur la coupe en service : la
    // plante n'est plus en attente de re-jugement.
    delete p.recoupee;
    if (valide && coupe) p.coupe = coupe;
    if (raison) p.raison = raison.slice(0, 300);
    // Seule l'invalidation redépose. Écarter veut dire « n'y reviens pas » :
    // le défaut est dans la source, et une graine neuve le reproduirait.
    if (verdict === 'invalidee') {
      const source = etat.taches.filter((t) => t.plante === plante).at(-1);
      etat.taches.push({
        id: identifiant(), plante, image: source?.image ?? '',
        graine: null, raison: 'invalidee_revue',
        // Le drapeau suit la relance : une plante sans pot le reste.
        ...(source?.sansPot ? { sansPot: true } : {}),
        etat: 'en_attente', depose: Date.now(),
      });
    }

    // ── Purge des maillages devenus inutiles ──────────────────────────────
    //
    // Validée : on ne garde que ce qui sera livré — la coupe retenue, ou le
    // maillage complet quand aucun retrait n'a été proposé.
    // Invalidée : rien n'est gardé, le maillage est rejeté.
    const livree = etat.taches.filter((t) => t.plante === plante && t.etat === 'livree').at(-1);
    const complet = nomFichier(livree?.resultat?.glb);
    // Écartée comme invalidée : rien à conserver. Le maillage ne sera livré ni
    // maintenant ni plus tard.
    const aGarder = valide ? (nomFichier(coupe) ?? complet) : null;

    if (valide && !aGarder) {
      // Rien d'identifiable à conserver : on ne purge PAS. Effacer ici
      // supprimerait le seul maillage livrable de la plante.
      p.purge = { quand: Date.now(), fichiers: 0, octets: 0,
                  raison: 'aucun fichier à conserver identifié' };
    } else if (valide && !glbPresents(plante).includes(aGarder!)) {
      // Le fichier nommé n'est pas sur le disque. Purger quand même
      // effacerait la coupe retenue par-dessus le marché : 180 Mo de GPU
      // perdus sur une erreur de nom. On s'abstient et on le dit.
      p.purge = { quand: Date.now(), fichiers: 0, octets: 0, garde: aGarder!,
                  raison: `fichier à conserver introuvable : ${aGarder}` };
    } else {
      const purge = purger(plante, aGarder ? [aGarder] : []);
      p.purge = { quand: Date.now(), fichiers: purge.supprimes.length,
                  octets: purge.octets, garde: aGarder ?? undefined };
    }

    return p.verdict;
  });
}

export type Retenue =
  | { ok: true; coupe: string | null }
  | { ok: false; motif: 'non_validee' | 'candidat_inconnu' | 'candidat_absent' };

/**
 * Retient une coupe sur une plante DÉJÀ validée, sans toucher au verdict.
 *
 * `trancher` ne sait pas faire ça : il remet un verdict, et sur une plante
 * validée il n'y a rien à remettre. Passer par lui obligerait à rejouer le
 * jugement humain pour corriger une donnée qui n'en fait pas partie.
 *
 * `coupe` à `null` consigne le choix inverse — le maillage entier, avec son pot
 * d'origine — et retire la plante de la file, pour qu'elle n'y revienne pas
 * indéfiniment faute de savoir si quelqu'un a regardé.
 *
 * Aucune purge quand on retient `null`. Les 6 plantes concernées au moment où
 * ce chemin est écrit ne portent PLUS leur maillage entier sur le volume : seuls
 * les candidats coupés restent. Purger « tout sauf le maillage entier »
 * effacerait donc le seul maillage livrable de la plante. C'est la même raison
 * qui a fait s'abstenir la garde de `trancher`, et c'est ce qui a sauvé ces
 * fichiers.
 */
export function retenirCoupe(plante: string, coupe: string | null): Promise<Retenue> {
  return muter((etat) => {
    const p = etat.plantes[plante];
    if (p?.verdict !== 'validee') return { ok: false, motif: 'non_validee' } as const;

    if (coupe === null) {
      delete p.coupe;
      p.sansCoupe = true;
      return { ok: true, coupe: null } as const;
    }

    const nom = nomFichier(coupe);
    // Seul un candidat réellement livré par l'ouvrier peut être retenu. Sans
    // cette garde, un nom quelconque passerait et la purge garderait un
    // fichier qui n'est la coupe de rien.
    const livree = etat.taches.filter((t) => t.plante === plante && t.etat === 'livree').at(-1);
    const bruts = Array.isArray(livree?.resultat?.candidats_pot) ? livree.resultat.candidats_pot : [];
    const connu = bruts.map(candidat).some((c) => c.fichier === nom);
    if (!nom || !connu) return { ok: false, motif: 'candidat_inconnu' } as const;
    if (!glbPresents(plante).includes(nom)) return { ok: false, motif: 'candidat_absent' } as const;

    p.coupe = nom;
    delete p.sansCoupe;
    const purge = purger(plante, [nom]);
    p.purge = { quand: Date.now(), fichiers: purge.supprimes.length,
                octets: purge.octets, garde: nom };
    return { ok: true, coupe: nom } as const;
  });
}

/** Pour les tests : repart d'un dépôt vide. */
export function reinitialiser() {
  chaine = Promise.resolve();
  // Pas de `existsSync(racine())` ici : `ecrire` crée déjà le dossier, et
  // Turbopack voyait dans cet appel un accès au système de fichiers à chemin
  // dynamique — il tracait alors tout le projet, `public/` compris, dans la
  // sortie serveur.
  ecrire(structuredClone(VIDE));
}

// ── Taille réelle d'une plante ─────────────────────────────────────────────
//
// Une plante n'est pas redimensionnable : elle a la taille qu'elle a, et
// l'application doit la poser à cette taille-là. Reste à la connaître.
//
// LE POT EST UNE RÈGLE GRADUÉE. La coupe mesure le rayon de son rebord au
// millième, et les pots d'horticulture n'ont qu'une poignée de diamètres. Une
// seule valeur à fournir par plante — le diamètre réel — et l'échelle suit :
//
//     échelle = diamètre_pot_cm / (2 × rayon)
//
// Validé sur une plante dont la fiche donne hauteur ET diamètre : 3,7 %
// d'erreur sur la hauteur totale.
//
// LE RAPPORT HAUTEUR/DIAMÈTRE DU POT dit, lui, si ce qu'on a mesuré EST un
// pot. Un pot d'horticulture est à peu près aussi haut que large ; mesuré sur
// 59 plantes, la médiane est à 0,99 et 85 % tombent entre 0,70 et 1,15. Les
// aberrantes dénoncent les détections ratées : un Washingtonia à 2,94, c'est
// le tronc qui a été pris pour un pot ; un Pilea à 0,13, c'est l'étalement du
// feuillage.
//
// Les deux mesures sont indépendantes et se contrôlent l'une l'autre.

/** Diamètres de pots d'horticulture courants, en centimètres. */
export const DIAMETRES_POT = [10, 12, 14, 15, 17, 19, 21, 24, 27, 30] as const;

/**
 * Bande dans laquelle le rapport hauteur/diamètre décrit un vrai pot.
 *
 * Volontairement large : hors d'elle, on ne conclut pas que la mesure est
 * fausse, on signale qu'elle demande un œil.
 */
export const HD_POT = { min: 0.70, max: 1.15 } as const;

export type Mesurable = {
  plante: string;
  /** Rayon du rebord, en unités du modèle. `null` si aucune voie ne l'a mesuré. */
  rayon: number | null;
  hauteurModele: number | null;
  /** Part de la hauteur occupée par le pot, de 0 à 1. */
  sommet: number | null;
  /** Hauteur du végétal au-dessus de la terre, quand la coupe l'a mesurée. */
  hauteurVegetal: number | null;
  /** Rapport hauteur/diamètre du pot, et s'il décrit un pot plausible. */
  rapportHD: number | null;
  potPlausible: boolean;
  /**
   * Diamètre donné par la fiche d'origine, quand elle le porte.
   *
   * Sert à pré-remplir la saisie : c'est la source la plus fiable dont on
   * dispose, et la seule qui ne demande aucun jugement.
   */
  diametreFiche: number | null;
  taille: {
    hauteurCm: number; stade: 'jeune' | 'adulte';
    diametrePotCm?: number; pose: number;
  } | null;
};

/**
 * Les plantes livrées, avec de quoi leur attribuer une taille.
 *
 * On ne rend que des grandeurs du modèle : la conversion en centimètres a
 * besoin du diamètre de pot, que seul l'opérateur connaît.
 */
export function mesurables(): Mesurable[] {
  const etat = lire();
  const vus = new Set<string>();
  const sorties: Mesurable[] = [];
  // À l'envers : quand une plante porte deux tâches livrées — ça arrive, cf.
  // #639 — c'est la DERNIÈRE qui décrit ce qui est servi.
  for (let i = etat.taches.length - 1; i >= 0; i -= 1) {
    const t = etat.taches[i];
    if (t.etat !== 'livree' || vus.has(t.plante)) continue;
    vus.add(t.plante);

    const bruts = Array.isArray(t.resultat?.candidats_pot) ? t.resultat.candidats_pot : [];
    // La voie géométrie seule mesure une révolution ; la voie couleur rend un
    // rayon nul, qui ne peut servir d'étalon.
    const geo = bruts
      .map((b) => (b ?? {}) as Record<string, unknown>)
      .find((c) => c.voie === 'geometrie');
    const socle = (geo?.socle ?? {}) as Record<string, unknown>;
    const rayon = nombre(socle.rayon);
    const hauteurModele = nombre(socle.hauteur_modele);
    const sommet = nombre(geo?.sommet);
    const rapportHD = rayon && hauteurModele && sommet
      ? (sommet * hauteurModele) / (2 * rayon)
      : null;

    sorties.push({
      plante: t.plante,
      rayon: rayon && rayon > 0 ? rayon : null,
      hauteurModele,
      sommet,
      hauteurVegetal: nombre(socle.hauteur_vegetal),
      rapportHD,
      potPlausible: rapportHD !== null
        && rapportHD >= HD_POT.min && rapportHD <= HD_POT.max,
      // `nomFichier` et non `t.image` tel quel : `sources` est indexé par nom
      // nu, alors que la tâche garde l'image telle qu'on la lui a donnée.
      diametreFiche: nombre(etat.sources?.[nomFichier(t.image) ?? '']?.diametrePotCm),
      taille: etat.plantes[t.plante]?.taille ?? null,
    });
  }
  return sorties.sort((a, b) => a.plante.localeCompare(b.plante, 'fr'));
}

export type Taille = {
  hauteurCm: number;
  stade: 'jeune' | 'adulte';
  diametrePotCm?: number;
};

/**
 * Attribue — ou retire — la taille d'une plante.
 *
 * Refuse une hauteur absurde plutôt que de l'enregistrer : une plante
 * d'intérieur ne fait ni deux centimètres ni cinq mètres, et une valeur fausse
 * posée en base est plus coûteuse qu'un refus.
 */
export function noterTaille(plante: string, taille: Taille | null) {
  return muter((etat) => {
    const p = (etat.plantes[plante] ??= { graines: [] });
    if (taille === null) {
      delete p.taille;
      return { ok: true as const, taille: null };
    }
    const h = Number(taille.hauteurCm);
    if (!Number.isFinite(h) || h < 3 || h > 400) {
      return { ok: false as const, raison: 'hauteur_invraisemblable' };
    }
    if (taille.stade !== 'jeune' && taille.stade !== 'adulte') {
      return { ok: false as const, raison: 'stade_inconnu' };
    }
    const d = taille.diametrePotCm;
    p.taille = {
      hauteurCm: Math.round(h * 10) / 10,
      stade: taille.stade,
      ...(Number.isFinite(d) && (d as number) > 0
        ? { diametrePotCm: Math.round((d as number) * 10) / 10 }
        : {}),
      pose: Date.now(),
    };
    return { ok: true as const, taille: p.taille };
  });
}
