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
    coupe?: string;
    raison?: string;
    purge?: Purge;
  }>;
  /** Ce qu'on sait d'une source au-delà de son fichier. */
  sources?: Record<string, { sansPot?: boolean }>;
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
  /** Candidats livrés, par NOM de fichier : la disposition du volume ne sort pas. */
  candidats: Array<{ voie: string; fichier: string; aireRetiree: number | null }>;
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
 * Tout ce qui est livré avec au moins un fichier, verdict compris : une coupe
 * validée se reprend aussi, puisque c'est la coupe qui s'est améliorée et non
 * le jugement qui a changé. Les plantes dont la détection n'avait rien trouvé
 * sont incluses sans l'être — elles n'ont pas de fichier, donc rien d'où
 * repartir, et c'est une régénération qu'il leur faudrait.
 */
export function recoupables(): Recoupable[] {
  const etat = lire();
  const sorties: Recoupable[] = [];
  for (const t of etat.taches) {
    if (t.etat !== 'livree') continue;
    const bruts = Array.isArray(t.resultat?.candidats_pot) ? t.resultat.candidats_pot : [];
    if (bruts.length === 0) continue;
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
    if (candidats.length === 0) continue;
    sorties.push({
      id: t.id, plante: t.plante, candidats,
      mesure: bruts.every((b) => Boolean((b as Record<string, unknown>)?.residu)),
    });
  }
  return sorties;
}

export type Recoupe =
  | { ok: true; candidats: number; empreintes: number; coupePerdue: boolean }
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
    const coupe = etat.plantes[t.plante]?.coupe;
    return {
      ok: true, candidats: candidats.length, empreintes,
      coupePerdue: Boolean(coupe) && !noms.has(coupe!),
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
    if (sansPot) (s[fichier] ??= {}).sansPot = true;
    else delete s[fichier];
    return sansPot;
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
 * Plantes livrées dont le verdict reste à rendre.
 *
 * Rend tout ce que la revue affiche, mesures comprises : c'est le dépôt qui
 * connaît la disposition des artefacts, pas la page. Celle-ci ne voit que des
 * noms de fichiers, qu'elle passe à la route de service.
 */
export function aRevoir(): AVoir[] {
  const etat = lire();
  return etat.taches
    .filter((t) => t.etat === 'livree' && !etat.plantes[t.plante]?.verdict)
    .map((t) => {
      const r = t.resultat ?? {};
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
      };
    });
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

/** Pour les tests : repart d'un dépôt vide. */
export function reinitialiser() {
  chaine = Promise.resolve();
  // Pas de `existsSync(racine())` ici : `ecrire` crée déjà le dossier, et
  // Turbopack voyait dans cet appel un accès au système de fichiers à chemin
  // dynamique — il tracait alors tout le projet, `public/` compris, dans la
  // sortie serveur.
  ecrire(structuredClone(VIDE));
}
