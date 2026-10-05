// @vitest-environment node
//
// La bibliothèque de pots. Ce qui compte : qu'un pot non mesurable soit refusé
// À L'INGESTION et ne laisse rien derrière lui — une bibliothèque où certains
// pots ne se posent pas, sans que rien ne les distingue, serait pire que vide.
import { describe, it, expect, beforeEach, afterAll } from 'vitest';
import { mkdtempSync, rmSync, existsSync, writeFileSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BAC = mkdtempSync(join(tmpdir(), 'biblio-'));
process.env.GENERATOR_DATA_DIR = BAC;
process.env.GENERATOR_HOST = 'generator.arbore.app';

import { NextRequest } from 'next/server';

import { GET as liste } from './pots/route';
import { GET, PUT, DELETE } from './pots/[fichier]/route';
import { reinitialiser, lire } from '@/lib/generator/depot';

afterAll(() => rmSync(BAC, { recursive: true, force: true }));

const HOTE = 'generator.arbore.app';
const params = (fichier: string) => ({ params: Promise.resolve({ fichier }) });

function req(chemin: string, hote = HOTE) {
  return new NextRequest(`https://${hote}${chemin}`, { headers: { host: hote } });
}
function envoi(fichier: string, corps: Uint8Array, hote = HOTE) {
  return new NextRequest(`https://${hote}/api/generator/pots/${fichier}?position=0&final=1`,
    // Une seule conversion, ici : depuis TypeScript 5.7 les tableaux typés sont
    // génériques sur leur tampon, et `Uint8Array<ArrayBufferLike>` n'est plus
    // assignable à `BodyInit`. Le corps est bien un flux d'octets valide — c'est
    // le type qui s'est resserré, pas la valeur qui est fausse.
    { method: 'PUT', headers: { host: hote }, body: corps as unknown as BodyInit,
      duplex: 'half' });
}

/**
 * Cylindre creux, écrit en GLB minimal. Un pot dont on connaît les mesures.
 *
 * Rendu en `Uint8Array` et non en `Buffer` : `BodyInit` n'accepte pas le second
 * pour TypeScript, et `next build` le refuse là où vitest l'accepte.
 */
function glbCylindre(r: number, y0: number, y1: number): Uint8Array {
  const s: number[] = [];
  const f: number[] = [];
  const cotes = 48;
  const etages = 10;
  for (let e = 0; e <= etages; e += 1) {
    const y = y0 + ((y1 - y0) * e) / etages;
    for (let k = 0; k < cotes; k += 1) {
      const a = (2 * Math.PI * k) / cotes;
      s.push(r * Math.cos(a), y, r * Math.sin(a));
    }
  }
  for (let e = 0; e < etages; e += 1) {
    for (let k = 0; k < cotes; k += 1) {
      const a = e * cotes + k;
      const b = e * cotes + ((k + 1) % cotes);
      f.push(a, b, a + cotes, b, b + cotes, a + cotes);
    }
  }
  const pos = Buffer.from(Float32Array.from(s).buffer);
  const idx = Buffer.from(Uint32Array.from(f).buffer);
  const bin = Buffer.concat([pos, idx]);
  const meta = {
    asset: { version: '2.0' },
    buffers: [{ byteLength: bin.length }],
    bufferViews: [
      { buffer: 0, byteOffset: 0, byteLength: pos.length },
      { buffer: 0, byteOffset: pos.length, byteLength: idx.length },
    ],
    accessors: [
      { bufferView: 0, componentType: 5126, count: s.length / 3, type: 'VEC3' },
      { bufferView: 1, componentType: 5125, count: f.length, type: 'SCALAR' },
    ],
    meshes: [{ primitives: [{ attributes: { POSITION: 0 }, indices: 1 }] }],
  };
  let j = Buffer.from(JSON.stringify(meta), 'utf8');
  while (j.length % 4) j = Buffer.concat([j, Buffer.from(' ')]);
  const entete = Buffer.alloc(12);
  entete.writeUInt32LE(0x46546c67, 0);
  entete.writeUInt32LE(2, 4);
  entete.writeUInt32LE(12 + 8 + j.length + 8 + bin.length, 8);
  const eJ = Buffer.alloc(8); eJ.writeUInt32LE(j.length, 0); eJ.writeUInt32LE(0x4e4f534a, 4);
  const eB = Buffer.alloc(8); eB.writeUInt32LE(bin.length, 0); eB.writeUInt32LE(0x004e4942, 4);
  return new Uint8Array(Buffer.concat([entete, eJ, j, eB, bin]));
}

describe('bibliothèque de pots', () => {
  beforeEach(() => {
    reinitialiser();
    rmSync(join(BAC, 'pots'), { recursive: true, force: true });
  });

  it('dépose un pot, le mesure, et le liste', async () => {
    expect((await (await liste(req('/api/generator/pots'))).json()).pots).toEqual([]);

    const r = await PUT(envoi('terracotta.glb', glbCylindre(0.18, -0.4, -0.1)),
                        params('terracotta.glb'));
    expect(r.status).toBe(201);
    const { pot } = await r.json();
    expect(pot.rayon).toBeCloseTo(0.18, 2);
    expect(pot.y).toBeCloseTo(-0.1, 4);
    expect(pot.hauteur).toBeCloseTo(0.3, 4);

    const l = (await (await liste(req('/api/generator/pots'))).json()).pots;
    expect(l).toHaveLength(1);
    expect(l[0].fichier).toBe('terracotta.glb');
  });

  it('ressert le pot pour la visionneuse', async () => {
    const octets = glbCylindre(0.15, 0, 0.25);
    await PUT(envoi('blanc.glb', octets), params('blanc.glb'));
    const lu = await GET(req('/api/generator/pots/blanc.glb'), params('blanc.glb'));
    expect(lu.status).toBe(200);
    expect(lu.headers.get('content-type')).toBe('model/gltf-binary');
    expect(new Uint8Array(await lu.arrayBuffer())).toEqual(octets);
  });

  /**
   * LE cas de ce fichier. Un maillage qu'on ne sait pas poser ne doit pas
   * entrer dans la bibliothèque, ni laisser de fichier derrière lui.
   */
  it('refuse un maillage qui n est pas un pot, et n en garde rien', async () => {
    const mat = glbCylindre(0.02, 0, 1.0);        // six fois plus haut que large
    const r = await PUT(envoi('mat.glb', mat), params('mat.glb'));
    expect(r.status).toBe(422);
    expect((await r.json()).error).toContain('rebord');

    expect(existsSync(join(BAC, 'pots', 'mat.glb'))).toBe(false);
    expect((await (await liste(req('/api/generator/pots'))).json()).pots).toEqual([]);
    expect(lire().pots).toEqual({});
    // Pas davantage de résidu d'assemblage.
    expect(readdirSync(join(BAC, 'pots')).filter((f) => f.includes('partiel'))).toEqual([]);
  });

  it('refuse un fichier qui n est pas un GLB', async () => {
    const r = await PUT(envoi('texte.glb', new Uint8Array(Buffer.from('pas un glb'))),
                        params('texte.glb'));
    expect(r.status).toBe(422);
    expect(existsSync(join(BAC, 'pots', 'texte.glb'))).toBe(false);
  });

  it('n accepte que l extension glb', async () => {
    for (const nom of ['pot.png', 'pot.usdz', 'pot.json', 'pot']) {
      expect((await PUT(envoi(nom, glbCylindre(0.2, 0, 0.3)), params(nom))).status, nom).toBe(404);
    }
  });

  it('refuse d écrire ou de lire hors du dossier des pots', async () => {
    for (const hostile of ['../evade.glb', 'a/b.glb', '../../etc/x.glb', '.glb']) {
      expect((await PUT(envoi(hostile, glbCylindre(0.2, 0, 0.3)), params(hostile))).status,
             hostile).toBe(404);
      expect((await GET(req('/api/generator/pots/x'), params(hostile))).status, hostile).toBe(404);
    }
    expect(existsSync(join(BAC, 'evade.glb'))).toBe(false);
  });

  it('remplace un pot et sa mesure', async () => {
    await PUT(envoi('p.glb', glbCylindre(0.10, 0, 0.2)), params('p.glb'));
    expect(lire().pots!['p.glb'].rayon).toBeCloseTo(0.10, 2);
    await PUT(envoi('p.glb', glbCylindre(0.25, 0, 0.3)), params('p.glb'));
    expect(lire().pots!['p.glb'].rayon).toBeCloseTo(0.25, 2);
    expect((await (await liste(req('/api/generator/pots'))).json()).pots).toHaveLength(1);
  });

  it('supprime un pot et sa mesure', async () => {
    await PUT(envoi('partant.glb', glbCylindre(0.2, 0, 0.3)), params('partant.glb'));
    expect((await DELETE(req('/api/generator/pots/partant.glb'), params('partant.glb'))).status)
      .toBe(200);
    expect(existsSync(join(BAC, 'pots', 'partant.glb'))).toBe(false);
    expect(lire().pots).toEqual({});
    expect((await DELETE(req('/api/generator/pots/absent.glb'), params('absent.glb'))).status)
      .toBe(404);
  });

  /**
   * Un dépassement de taille et une coupure de lien se corrigent très
   * différemment : réduire le fichier, ou réessayer.
   */
  it('distingue un fichier trop lourd d une coupure', async () => {
    const trop = new NextRequest(
      `https://${HOTE}/api/generator/pots/gros.glb?position=0&final=1`,
      {
        method: 'PUT', headers: { host: HOTE }, duplex: 'half',
        body: new Uint8Array(70 * 1024 * 1024) as unknown as BodyInit,
      },
    );
    const r = await PUT(trop, params('gros.glb'));
    expect(r.status).toBe(413);
    expect((await r.json()).error).toContain('trop lourd');
    expect(existsSync(join(BAC, 'pots', 'gros.glb'))).toBe(false);
  });

  it('n existe pas depuis le site public', async () => {
    const pub = 'web.arbore.app';
    expect((await liste(req('/api/generator/pots', pub))).status).toBe(404);
    expect((await GET(req('/api/generator/pots/a.glb', pub), params('a.glb'))).status).toBe(404);
    expect((await PUT(envoi('a.glb', glbCylindre(0.2, 0, 0.3), pub), params('a.glb'))).status)
      .toBe(404);
    expect((await DELETE(req('/api/generator/pots/a.glb', pub), params('a.glb'))).status).toBe(404);
  });
});
