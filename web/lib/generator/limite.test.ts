import { describe, it, expect, beforeEach } from 'vitest';

import { FENETRE_MS, MAX_ESSAIS, consommer, consulter, oublier, reinitialiser } from './limite';

const IP = '203.0.113.7';

describe('anti-force-brute du formulaire de clé', () => {
  beforeEach(() => reinitialiser());

  it('laisse passer trois essais puis bloque le quatrième', () => {
    for (let i = 0; i < MAX_ESSAIS; i += 1) {
      expect(consulter(IP).autorise).toBe(true);
      consommer(IP);
    }
    const verdict = consulter(IP);
    expect(verdict.autorise).toBe(false);
    expect(verdict.restants).toBe(0);
    expect(verdict.attente).toBeGreaterThan(0);
  });

  it('consulter ne consomme pas', () => {
    // Sinon un simple affichage du formulaire épuiserait le quota.
    for (let i = 0; i < 20; i += 1) consulter(IP);
    expect(consulter(IP).restants).toBe(MAX_ESSAIS);
  });

  it('libère les essais une heure plus tard, un par un', () => {
    const t0 = Date.now();
    for (let i = 0; i < MAX_ESSAIS; i += 1) consommer(IP, t0 + i * 1000);
    expect(consulter(IP, t0 + 1000).autorise).toBe(false);

    // Le plus ancien sort de la fenêtre : un essai se libère, pas les trois.
    const apres = consulter(IP, t0 + FENETRE_MS + 1);
    expect(apres.autorise).toBe(true);
    expect(apres.restants).toBe(1);
  });

  it('une connexion réussie efface les essais', () => {
    consommer(IP); consommer(IP);
    oublier(IP);
    expect(consulter(IP).restants).toBe(MAX_ESSAIS);
  });

  it('compte par adresse, sans contaminer les voisines', () => {
    for (let i = 0; i < MAX_ESSAIS; i += 1) consommer(IP);
    expect(consulter(IP).autorise).toBe(false);
    expect(consulter('198.51.100.4').autorise).toBe(true);
  });

  it('annonce une attente qui décroît avec le temps', () => {
    const t0 = Date.now();
    for (let i = 0; i < MAX_ESSAIS; i += 1) consommer(IP, t0);
    const tot = consulter(IP, t0).attente;
    const tard = consulter(IP, t0 + 30 * 60 * 1000).attente;
    expect(tard).toBeLessThan(tot);
    expect(tard).toBeGreaterThan(0);
  });
});
