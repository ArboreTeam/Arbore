// @vitest-environment node
//
// La mesure du rebord décide de l'échelle à laquelle un pot sera posé. On la
// vérifie donc sur des maillages CONSTRUITS, dont on connaît les dimensions au
// chiffre près, plutôt que sur des fichiers dont on ne saurait dire s'ils sont
// justes.
import { describe, it, expect, afterAll } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { lireMaillage } from './glb';
import { mesurerRebord } from './pot';

const BAC = mkdtempSync(join(tmpdir(), 'pots-'));
afterAll(() => rmSync(BAC, { recursive: true, force: true }));

/** Écrit un GLB minimal : positions en float32, indices en uint32. */
function ecrireGlb(nom: string, sommets: number[], indices: number[]): string {
  const pos = Buffer.from(Float32Array.from(sommets).buffer);
  const idx = Buffer.from(Uint32Array.from(indices).buffer);
  const bin = Buffer.concat([pos, idx]);

  const meta = {
    asset: { version: '2.0' },
    buffers: [{ byteLength: bin.length }],
    bufferViews: [
      { buffer: 0, byteOffset: 0, byteLength: pos.length },
      { buffer: 0, byteOffset: pos.length, byteLength: idx.length },
    ],
    accessors: [
      { bufferView: 0, componentType: 5126, count: sommets.length / 3, type: 'VEC3' },
      { bufferView: 1, componentType: 5125, count: indices.length, type: 'SCALAR' },
    ],
    meshes: [{ primitives: [{ attributes: { POSITION: 0 }, indices: 1 }] }],
  };
  let j = Buffer.from(JSON.stringify(meta), 'utf8');
  while (j.length % 4) j = Buffer.concat([j, Buffer.from(' ')]);
  let b = bin;
  while (b.length % 4) b = Buffer.concat([b, Buffer.from([0])]);

  const entete = Buffer.alloc(12);
  entete.writeUInt32LE(0x46546c67, 0);
  entete.writeUInt32LE(2, 4);
  entete.writeUInt32LE(12 + 8 + j.length + 8 + b.length, 8);
  const eJ = Buffer.alloc(8); eJ.writeUInt32LE(j.length, 0); eJ.writeUInt32LE(0x4e4f534a, 4);
  const eB = Buffer.alloc(8); eB.writeUInt32LE(b.length, 0); eB.writeUInt32LE(0x004e4942, 4);

  const chemin = join(BAC, nom);
  writeFileSync(chemin, Buffer.concat([entete, eJ, j, eB, b]));
  return chemin;
}

/** Cylindre creux d'axe (cx, cz), de rayon r, de `y0` à `y1`. */
function cylindre(
  { r, y0, y1, cx = 0, cz = 0, cotes = 64, etages = 12 }:
  { r: number; y0: number; y1: number; cx?: number; cz?: number; cotes?: number; etages?: number },
) {
  const s: number[] = [];
  const f: number[] = [];
  for (let e = 0; e <= etages; e += 1) {
    const y = y0 + ((y1 - y0) * e) / etages;
    for (let k = 0; k < cotes; k += 1) {
      const a = (2 * Math.PI * k) / cotes;
      s.push(cx + r * Math.cos(a), y, cz + r * Math.sin(a));
    }
  }
  for (let e = 0; e < etages; e += 1) {
    for (let k = 0; k < cotes; k += 1) {
      const a = e * cotes + k;
      const b = e * cotes + ((k + 1) % cotes);
      f.push(a, b, a + cotes, b, b + cotes, a + cotes);
    }
  }
  return { s, f };
}

describe('lecture d un GLB', () => {
  it('rend les positions et compte les triangles', () => {
    const { s, f } = cylindre({ r: 0.2, y0: 0, y1: 0.3 });
    const m = lireMaillage(ecrireGlb('simple.glb', s, f));
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
    const m = lireMaillage(ecrireGlb('orphelins.glb', [...s, ...orphelins], f));
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
    const r = mesurerRebord(ecrireGlb('connu.glb', s, f))!;
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
    const r = mesurerRebord(ecrireGlb('evase.glb', s, f))!;
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
    expect(mesurerRebord(ecrireGlb('mat.glb', mat.s, mat.f))).toBeNull();

    // Une dalle plate, sans hauteur.
    const plat = cylindre({ r: 0.2, y0: 0, y1: 0, etages: 1 });
    expect(mesurerRebord(ecrireGlb('plat.glb', plat.s, plat.f))).toBeNull();

    // Trop peu de sommets pour mesurer quoi que ce soit.
    expect(mesurerRebord(ecrireGlb('maigre.glb', [0, 0, 0, 1, 0, 0, 0, 1, 0], [0, 1, 2])))
      .toBeNull();
  });

  it('ne lève jamais sur un fichier illisible', () => {
    const chemin = join(BAC, 'cassé.glb');
    writeFileSync(chemin, Buffer.from('glTF mais tronqué'));
    expect(mesurerRebord(chemin)).toBeNull();
    expect(mesurerRebord(join(BAC, 'inexistant.glb'))).toBeNull();
  });
});
