// Anti-force-brute du formulaire de clé.
//
// Trois tentatives par heure et par adresse, fenêtre glissante. Une clé unique
// partagée n'a ni compte à verrouiller ni second facteur : la seule défense
// contre l'essai systématique est de rendre les essais coûteux en temps.
//
// L'état vit en mémoire du processus, et disparaît au redémarrage du conteneur.
// C'est un affaiblissement assumé : un attaquant ne peut pas provoquer de
// redémarrage, et la contrepartie — une table en base pour un outil interne —
// coûterait plus qu'elle ne protège. Si la chaîne passait à plusieurs
// instances, il faudrait le déplacer côté Redis ou Mongo.

export const MAX_ESSAIS = 3;
export const FENETRE_MS = 60 * 60 * 1000;

const essais = new Map<string, number[]>();

/** Purge les traces trop vieilles — sinon la table croît indéfiniment. */
function nettoyer(maintenant: number) {
  // `forEach` et non `for…of` : voir la note de session.ts sur la cible
  // TypeScript. Les suppressions se font après le parcours, modifier une Map
  // pendant qu'on la parcourt étant une mauvaise habitude même quand V8 le
  // tolère.
  const aEffacer: string[] = [];
  essais.forEach((dates: number[], adresse: string) => {
    const recents = dates.filter((d: number) => maintenant - d < FENETRE_MS);
    if (recents.length) essais.set(adresse, recents);
    else aEffacer.push(adresse);
  });
  aEffacer.forEach((adresse) => essais.delete(adresse));
}

export type Verdict = {
  autorise: boolean;
  restants: number;
  /** Secondes avant qu'un essai se libère. Zéro si des essais restent. */
  attente: number;
};

/**
 * Consulte SANS consommer. Appelé avant de vérifier la clé, pour refuser tôt.
 */
export function consulter(adresse: string, maintenant = Date.now()): Verdict {
  nettoyer(maintenant);
  const dates = (essais.get(adresse) ?? []).filter((d: number) => maintenant - d < FENETRE_MS);
  const restants = Math.max(0, MAX_ESSAIS - dates.length);
  if (restants > 0) return { autorise: true, restants, attente: 0 };
  const plusAncien = Math.min(...dates);
  return {
    autorise: false,
    restants: 0,
    attente: Math.ceil((FENETRE_MS - (maintenant - plusAncien)) / 1000),
  };
}

/**
 * Consomme un essai. N'est appelé que sur ÉCHEC : une connexion réussie ne doit
 * pas rapprocher du blocage, sans quoi l'usage normal s'auto-verrouille.
 */
export function consommer(adresse: string, maintenant = Date.now()): Verdict {
  const dates = (essais.get(adresse) ?? []).filter((d: number) => maintenant - d < FENETRE_MS);
  dates.push(maintenant);
  essais.set(adresse, dates);
  return consulter(adresse, maintenant);
}

/** Efface les essais d'une adresse — après une connexion réussie. */
export function oublier(adresse: string) {
  essais.delete(adresse);
}

/** Pour les tests : repart d'une table vide. */
export function reinitialiser() {
  essais.clear();
}
