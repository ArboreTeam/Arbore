import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createHash } from 'node:crypto';

import { empreintesAttendues, environnement, environnements } from './config';

const sha = (v: string) => createHash('sha256').update(v).digest('hex');
const HUMAINE = sha('cle-humaine-dev');
const ROBOT = sha('cle-ouvrier-vignettes');

describe('config — clés acceptées par l atelier', () => {
  beforeEach(() => { delete process.env.GENERATOR_KEY_HASH; });
  afterEach(() => { delete process.env.GENERATOR_KEY_HASH; });

  it('accepte une empreinte unique, comme avant', () => {
    process.env.GENERATOR_KEY_HASH = HUMAINE;
    expect(empreintesAttendues()).toEqual(new Set([HUMAINE]));
  });

  it('accepte plusieurs empreintes, pour donner sa propre clé au robot', () => {
    // Le point de ce changement : sans liste, il faudrait confier la clé
    // HUMAINE à l'ouvrier — donc écrire un mot de passe de personne dans un
    // fichier de secrets, et le rendre irrévocable sans déconnecter cette
    // personne.
    process.env.GENERATOR_KEY_HASH = `${HUMAINE},${ROBOT}`;
    const lues = empreintesAttendues();
    expect(lues.has(HUMAINE)).toBe(true);
    expect(lues.has(ROBOT)).toBe(true);
  });

  it('tolère espaces et sauts de ligne autour des séparateurs', () => {
    process.env.GENERATOR_KEY_HASH = `  ${HUMAINE} ,\n  ${ROBOT}  `;
    expect(empreintesAttendues().size).toBe(2);
  });

  it('majuscules acceptées : une empreinte est insensible à la casse', () => {
    process.env.GENERATOR_KEY_HASH = HUMAINE.toUpperCase();
    expect(empreintesAttendues()).toEqual(new Set([HUMAINE]));
  });

  it('écarte ce qui n est pas une empreinte SHA-256', () => {
    // Une valeur tronquée, ou la CLÉ posée là par erreur à la place de son
    // empreinte, ne doit pas devenir une clé acceptée.
    process.env.GENERATOR_KEY_HASH = `cle-en-clair, ${HUMAINE}, ${HUMAINE.slice(0, 40)}`;
    expect(empreintesAttendues()).toEqual(new Set([HUMAINE]));
  });

  it('une configuration vide n accepte rien', () => {
    // L'atelier répond alors 503. Un atelier sans clé vaudrait un atelier
    // sans porte.
    process.env.GENERATOR_KEY_HASH = '   ';
    expect(empreintesAttendues().size).toBe(0);
  });
});

describe('config — environnements des vignettes', () => {
  beforeEach(() => { delete process.env.VIGNETTES_ENVIRONNEMENTS; });
  afterEach(() => { delete process.env.VIGNETTES_ENVIRONNEMENTS; });

  it('rend une liste vide quand rien n est déclaré', () => {
    expect(environnements()).toEqual([]);
    expect(environnement('dev')).toBeNull();
  });

  it('une configuration illisible ne fait pas tomber l atelier', () => {
    // Lever ici ferait tomber l'atelier entier pour une virgule en trop.
    process.env.VIGNETTES_ENVIRONNEMENTS = '{ pas du json';
    expect(environnements()).toEqual([]);
  });

  it('retire la barre finale de l adresse', () => {
    process.env.VIGNETTES_ENVIRONNEMENTS = JSON.stringify(
      [{ nom: 'dev', api: 'https://api-dev.arbore.app/', cle: 'k' }],
    );
    expect(environnement('dev')?.api).toBe('https://api-dev.arbore.app');
  });

  it('ignore une entrée sans nom ou sans adresse', () => {
    process.env.VIGNETTES_ENVIRONNEMENTS = JSON.stringify([
      { nom: 'dev', api: 'https://a' },
      { nom: 'cassee' },
      { api: 'https://b' },
    ]);
    expect(environnements().map((e) => e.nom)).toEqual(['dev']);
  });

  it('lit la clé interne', () => {
    process.env.VIGNETTES_ENVIRONNEMENTS = JSON.stringify(
      [{ nom: 'dev', api: 'https://a', cle: 'k', interne: 'i' }],
    );
    expect(environnement('dev')?.interne).toBe('i');
  });

  // Une entrée sans `interne` reste VALIDE, et rend une chaîne vide. C'est
  // l'état de toute configuration écrite avant #696, et l'atelier doit la
  // charger pour pouvoir dire « clé interne absente » dans son aperçu — une
  // entrée rejetée ici deviendrait un « environnement inconnu », diagnostic
  // beaucoup plus difficile à relier à la vraie cause.
  it('une entrée sans clé interne reste chargée, clé vide', () => {
    process.env.VIGNETTES_ENVIRONNEMENTS = JSON.stringify(
      [{ nom: 'dev', api: 'https://a', cle: 'k' }],
    );
    expect(environnement('dev')?.interne).toBe('');
    expect(environnements().map((e) => e.nom)).toEqual(['dev']);
  });

  // Les clés ne doivent jamais arriver dans le navigateur. Le seul endroit qui
  // les expose est la remise de tâche à l'ouvrier, derrière une session.
  it('un type inattendu pour interne ne traverse pas', () => {
    process.env.VIGNETTES_ENVIRONNEMENTS = JSON.stringify(
      [{ nom: 'dev', api: 'https://a', cle: 'k', interne: { fuite: true } }],
    );
    expect(environnement('dev')?.interne).toBe('');
  });
});
