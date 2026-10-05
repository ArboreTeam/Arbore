// Maillages construits pour les tests.
//
// Les mesures de cette famille — rebord, profil radial, contrôle de pose —
// décident de l'échelle et de la position d'un pot. On les vérifie donc sur des
// maillages dont on connaît les dimensions au chiffre près, plutôt que sur des
// fichiers dont on ne saurait dire s'ils sont justes.
//
// Hors du périmètre de l'application : rien ici n'est importé par du code servi.
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

/** Écrit un GLB minimal : positions en float32, indices en uint32. */
export function ecrireGlb(
  dossier: string, nom: string, sommets: number[], indices: number[],
): string {
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

  const chemin = join(dossier, nom);
  writeFileSync(chemin, Buffer.concat([entete, eJ, j, eB, b]));
  return chemin;
}

export type Tronc = {
  /** Rayon en bas, et en haut s'il diffère : un pot évasé ou conique. */
  r: number;
  rHaut?: number;
  y0: number;
  y1: number;
  cx?: number;
  cz?: number;
  cotes?: number;
  etages?: number;
};

/** Tronc de révolution creux, d'axe (cx, cz), de `y0` à `y1`. */
export function cylindre(
  { r, rHaut, y0, y1, cx = 0, cz = 0, cotes = 64, etages = 12 }: Tronc,
) {
  const s: number[] = [];
  const f: number[] = [];
  for (let e = 0; e <= etages; e += 1) {
    const t = e / etages;
    const y = y0 + (y1 - y0) * t;
    const rayon = rHaut === undefined ? r : r + (rHaut - r) * t;
    for (let k = 0; k < cotes; k += 1) {
      const a = (2 * Math.PI * k) / cotes;
      s.push(cx + rayon * Math.cos(a), y, cz + rayon * Math.sin(a));
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

/** Deux maillages bout à bout, indices décalés. */
export function joindre(
  a: { s: number[]; f: number[] }, b: { s: number[]; f: number[] },
) {
  const decalage = a.s.length / 3;
  return { s: [...a.s, ...b.s], f: [...a.f, ...b.f.map((i) => i + decalage)] };
}
