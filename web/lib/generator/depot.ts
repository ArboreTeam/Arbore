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
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export type EtatTache = 'en_attente' | 'en_cours' | 'livree' | 'echec';

export type Tache = {
  id: string;
  plante: string;
  image: string;
  graine: number | null;
  raison: string;
  etat: EtatTache;
  depose: number;
  pris?: number;
  /** Identité de la réservation en cours. Voir `prendre`. */
  reservation?: string;
  livre?: number;
  resultat?: Record<string, unknown>;
  erreur?: string;
};

export type Etat = {
  taches: Tache[];
  plantes: Record<string, { graines: number[]; verdict?: 'validee' | 'invalidee'; coupe?: string }>;
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

export function lire(): Etat {
  try {
    const brut = JSON.parse(readFileSync(cheminEtat(), 'utf8'));
    return { taches: brut.taches ?? [], plantes: brut.plantes ?? {} };
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

export function deposer(plante: string, image: string, raison = 'initiale', graine: number | null = null) {
  return muter((etat) => {
    const tache: Tache = {
      id: identifiant(), plante, image, graine, raison,
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

/** Plantes livrées dont le verdict reste à rendre. */
export function aRevoir() {
  const etat = lire();
  return etat.taches
    .filter((t) => t.etat === 'livree' && !etat.plantes[t.plante]?.verdict)
    .map((t) => ({
      plante: t.plante,
      graine: (t.resultat?.graine as number) ?? null,
      accepte: Boolean(t.resultat?.accepte),
      apercus: (t.resultat?.apercus as string[]) ?? [],
      candidats: (t.resultat?.candidats_pot as unknown[]) ?? [],
      arbitrage: Boolean(t.resultat?.arbitrage_requis),
    }));
}

/**
 * Enregistre un verdict humain. Une invalidation redépose une tâche : c'est le
 * seul chemin qui remonte vers le GPU, et il ne sert qu'au défaut qu'aucune
 * métrique ne voit — la géométrie inventée mais plausible.
 */
export function trancher(plante: string, valide: boolean, coupe?: string) {
  return muter((etat) => {
    const p = (etat.plantes[plante] ??= { graines: [] });
    p.verdict = valide ? 'validee' : 'invalidee';
    if (valide && coupe) p.coupe = coupe;
    if (!valide) {
      const source = etat.taches.filter((t) => t.plante === plante).at(-1);
      etat.taches.push({
        id: identifiant(), plante, image: source?.image ?? '',
        graine: null, raison: 'invalidee_revue',
        etat: 'en_attente', depose: Date.now(),
      });
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
