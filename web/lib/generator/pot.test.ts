// @vitest-environment node
//
// La mesure du rebord décide de l'échelle à laquelle un pot sera posé. On la
// vérifie donc sur des maillages CONSTRUITS, dont on connaît les dimensions au
// chiffre près, plutôt que sur des fichiers dont on ne saurait dire s'ils sont
// justes. Les constructeurs sont dans `maillages.essai`, partagés avec le
// contrôle de pose qui s'appuie sur les mêmes formes.
import { describe, it, expect, afterAll } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { lireMaillage } from './glb';
import { cylindre, ecrireGlb } from './maillages.essai';
import { mesurerRebord } from './pot';

const BAC = mkdtempSync(join(tmpdir(), 'pots-'));
afterAll(() => rmSync(BAC, { recursive: true, force: true }));

const glb = (nom: string, s: number[], f: number[]) => ecrireGlb(BAC, nom, s, f);

describe('lecture d un GLB', () => {
  it('rend les positions et compte les triangles', () => {
    const { s, f } = cylindre({ r: 0.2, y0: 0, y1: 0.3 });
    const m = lireMaillage(glb('simple.glb', s, f));
    expect(m.positions.length / 3).toBe(s.length / 3);
    expect(m.triangles).toBe(f.length / 3);
  });

  /**
   * Le cas qui compte : un GLB dont la liste de triangles ne désigne qu'une
   * part des sommets. C'est ce que produit `_ecrire`, et mesurer sur TOUS les
   * sommets donnait la boîte de la plante entière là où on veut celle du pot.
   */
  it('ignore les sommets qu aucun triangle ne référence', () => {
    const { s, f } = cylindre({ r: 0.2, y0: 0, y1: 0.3 });
    const orphelins = [0, 99, 0, 1, 99, 1, 2, 99, 2];     // très au-dessus
    const m = lireMaillage(glb('orphelins.glb', [...s, ...orphelins], f));
    expect(m.positions.length / 3).toBe(s.length / 3);
    let yMax = -Infinity;
    for (let i = 0; i < m.positions.length / 3; i += 1) {
      yMax = Math.max(yMax, m.positions[i * 3 + 1]);
    }
    expect(yMax).toBeCloseTo(0.3, 5);
  });

  it('refuse ce qui n est pas un GLB', () => {
    const chemin = join(BAC, 'faux.glb');
    writeFileSync(chemin, Buffer.from('ceci n est pas un glb'));
    expect(() => lireMaillage(chemin)).toThrow();
  });
});

describe('mesure du rebord d un pot', () => {
  it('retrouve le rayon, la hauteur et l axe d un cylindre connu', () => {
    const { s, f } = cylindre({ r: 0.18, y0: -0.4, y1: -0.1, cx: 0.05, cz: -0.02 });
    const r = mesurerRebord(glb('connu.glb', s, f))!;
    expect(r).not.toBeNull();
    expect(r.rayon).toBeCloseTo(0.18, 2);
    expect(r.y).toBeCloseTo(-0.1, 4);
    expect(r.hauteur).toBeCloseTo(0.3, 4);
    expect(r.x).toBeCloseTo(0.05, 2);
    expect(r.z).toBeCloseTo(-0.02, 2);
  });

  /** Un pot évasé : c'est le HAUT qui donne le rayon, pas la base. */
  it('mesure la lèvre et non la base sur un pot évasé', () => {
    const s: number[] = [];
    const f: number[] = [];
    const cotes = 64;
    const etages = 12;
    for (let e = 0; e <= etages; e += 1) {
      const t = e / etages;
      const r = 0.10 + 0.08 * t;                 // 0.10 en bas, 0.18 en haut
      for (let k = 0; k < cotes; k += 1) {
        const a = (2 * Math.PI * k) / cotes;
        s.push(r * Math.cos(a), -0.3 + 0.3 * t, r * Math.sin(a));
      }
    }
    for (let e = 0; e < etages; e += 1) {
      for (let k = 0; k < cotes; k += 1) {
        const a = e * cotes + k;
        const b = e * cotes + ((k + 1) % cotes);
        f.push(a, b, a + cotes, b, b + cotes, a + cotes);
      }
    }
    const r = mesurerRebord(glb('evase.glb', s, f))!;
    expect(r.rayon).toBeGreaterThan(0.16);
    expect(r.rayon).toBeLessThanOrEqual(0.181);
    expect(r.y).toBeCloseTo(0, 4);
  });

  /**
   * Refuser à l'ingestion vaut mieux que découvrir à l'essayage qu'un objet
   * n'est pas posable.
   */
  it('refuse ce qui n est pas un pot', () => {
    // Un mât : six fois plus haut que large.
    const mat = cylindre({ r: 0.02, y0: 0, y1: 1.0 });
    expect(mesurerRebord(glb('mat.glb', mat.s, mat.f))).toBeNull();

    // Une dalle plate, sans hauteur.
    const plat = cylindre({ r: 0.2, y0: 0, y1: 0, etages: 1 });
    expect(mesurerRebord(glb('plat.glb', plat.s, plat.f))).toBeNull();

    // Trop peu de sommets pour mesurer quoi que ce soit.
    expect(mesurerRebord(glb('maigre.glb', [0, 0, 0, 1, 0, 0, 0, 1, 0], [0, 1, 2])))
      .toBeNull();
  });

  it('ne lève jamais sur un fichier illisible', () => {
    const chemin = join(BAC, 'cassé.glb');
    writeFileSync(chemin, Buffer.from('glTF mais tronqué'));
    expect(mesurerRebord(chemin)).toBeNull();
    expect(mesurerRebord(join(BAC, 'inexistant.glb'))).toBeNull();
  });
});
