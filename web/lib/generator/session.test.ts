import { describe, it, expect } from 'vitest';

import { DUREE_SESSION_S, emettre, empreinte, verifier } from './session';

const SECRET = 'secret-de-test-assez-long-pour-etre-realiste';

describe('session de l atelier', () => {
  it('accepte un jeton qu elle vient d émettre', async () => {
    expect(await verifier(await emettre(SECRET), SECRET)).toBe(true);
  });

  it('refuse un jeton signé avec un autre secret', async () => {
    // Le cas qui compte : une image déployée avec un secret différent ne doit
    // pas accepter les sessions de l'ancienne.
    expect(await verifier(await emettre('autre-secret'), SECRET)).toBe(false);
  });

  it('refuse une charge utile modifiée', async () => {
    const jeton = await emettre(SECRET);
    const [charge, signature] = jeton.split('.');
    const falsifie = `${charge.slice(0, -2)}XY.${signature}`;
    expect(await verifier(falsifie, SECRET)).toBe(false);
  });

  it('refuse une signature tronquée', async () => {
    const jeton = await emettre(SECRET);
    expect(await verifier(jeton.slice(0, -4), SECRET)).toBe(false);
  });

  it('refuse un jeton expiré', async () => {
    const t0 = Date.now();
    const jeton = await emettre(SECRET, t0);
    expect(await verifier(jeton, SECRET, t0 + DUREE_SESSION_S * 1000 - 1000)).toBe(true);
    expect(await verifier(jeton, SECRET, t0 + DUREE_SESSION_S * 1000 + 1000)).toBe(false);
  });

  it('refuse l absence de jeton, et l absence de secret', async () => {
    expect(await verifier(undefined, SECRET)).toBe(false);
    expect(await verifier('', SECRET)).toBe(false);
    // Secret vide : une configuration manquante ne doit pas ouvrir la porte.
    expect(await verifier(await emettre(SECRET), '')).toBe(false);
  });

  it('refuse une chaîne qui n a pas la forme attendue', async () => {
    for (const bidon of ['abc', '.', 'a.b.c.d', 'sans-point']) {
      expect(await verifier(bidon, SECRET)).toBe(false);
    }
  });

  it('calcule une empreinte SHA-256 stable et connue', async () => {
    // Vecteur de référence : évite qu un changement d algorithme passe inaperçu
    // et invalide silencieusement toutes les clés déjà déployées.
    expect(await empreinte('abc')).toBe(
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
});
