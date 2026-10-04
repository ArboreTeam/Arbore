// @vitest-environment node
//
// Les images d'entrée. Ce qui compte ici : qu'on ne puisse déposer ni lire ni
// effacer autre chose qu'une image, et nulle part ailleurs que dans `sources/`.
import { describe, it, expect, beforeEach, afterAll } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BAC = mkdtempSync(join(tmpdir(), 'sources-'));
process.env.GENERATOR_DATA_DIR = BAC;
process.env.GENERATOR_HOST = 'generator.arbore.app';

import { NextRequest } from 'next/server';

import { GET as liste } from './sources/route';
import { GET, PUT, DELETE } from './sources/[fichier]/route';
import * as taches from './taches/route';
import { reinitialiser } from '@/lib/generator/depot';

afterAll(() => rmSync(BAC, { recursive: true, force: true }));

const HOTE = 'generator.arbore.app';
const IMG = Buffer.from('89504e470d0a1a0a', 'hex');
const params = (fichier: string) => ({ params: Promise.resolve({ fichier }) });

function req(chemin: string, hote = HOTE) {
  return new NextRequest(`https://${hote}${chemin}`, { headers: { host: hote } });
}
function envoi(fichier: string, corps: BodyInit | null, hote = HOTE) {
  return new NextRequest(
    `https://${hote}/api/generator/sources/${fichier}?position=0&final=1`,
    { method: 'PUT', headers: { host: hote }, body: corps, duplex: 'half' },
  );
}

describe('images sources', () => {
  beforeEach(() => {
    reinitialiser();
    rmSync(join(BAC, 'sources'), { recursive: true, force: true });
  });

  it('dépose une image, la liste, et la ressert à l identique', async () => {
    expect((await (await liste(req('/api/generator/sources'))).json()).sources).toEqual([]);

    const r = await PUT(envoi('nephrolepis.png', IMG), params('nephrolepis.png'));
    expect(r.status).toBe(201);

    const l = (await (await liste(req('/api/generator/sources'))).json()).sources;
    expect(l).toHaveLength(1);
    expect(l[0]).toMatchObject({ plante: 'nephrolepis', fichier: 'nephrolepis.png', enFile: false });

    const lu = await GET(req('/api/generator/sources/nephrolepis.png'), params('nephrolepis.png'));
    expect(lu.status).toBe(200);
    expect(lu.headers.get('content-type')).toBe('image/png');
    expect(Buffer.from(await lu.arrayBuffer())).toEqual(IMG);
  });

  it('accepte png, jpg et webp, et rien d autre', async () => {
    for (const bon of ['a.png', 'b.jpg', 'c.jpeg', 'd.webp']) {
      expect((await PUT(envoi(bon, IMG), params(bon))).status, bon).toBe(201);
    }
    for (const mauvais of ['x.glb', 'x.svg', 'x.json', 'x.php', 'x.sh', 'sansext']) {
      expect((await PUT(envoi(mauvais, IMG), params(mauvais))).status, mauvais).toBe(404);
    }
  });

  it('refuse d écrire ou de lire hors du dossier des sources', async () => {
    for (const hostile of ['../evade.png', '..%2Fevade.png', 'a/b.png', '../../etc/x.png', '.png']) {
      expect((await PUT(envoi(hostile, IMG), params(hostile))).status, hostile).toBe(404);
      expect((await GET(req('/api/generator/sources/x'), params(hostile))).status, hostile).toBe(404);
    }
    expect(existsSync(join(BAC, 'evade.png'))).toBe(false);
  });

  it('remplace une source par un meilleur détourage', async () => {
    await PUT(envoi('monstera.png', IMG), params('monstera.png'));
    await PUT(envoi('monstera.png', Buffer.from('mieux')), params('monstera.png'));
    expect(readFileSync(join(BAC, 'sources', 'monstera.png')).toString()).toBe('mieux');
  });

  /** Retirer une source ne doit pas effacer ce qui a déjà été jugé. */
  it('supprime une source sans toucher aux artefacts', async () => {
    await PUT(envoi('calathea.png', IMG), params('calathea.png'));
    mkdirSync(join(BAC, 'plantes', 'calathea'), { recursive: true });
    writeFileSync(join(BAC, 'plantes', 'calathea', 'apercu_000.png'), IMG);

    expect((await DELETE(req('/api/generator/sources/calathea.png'), params('calathea.png'))).status)
      .toBe(200);
    expect(existsSync(join(BAC, 'sources', 'calathea.png'))).toBe(false);
    expect(existsSync(join(BAC, 'plantes', 'calathea', 'apercu_000.png'))).toBe(true);

    expect((await DELETE(req('/api/generator/sources/absente.png'), params('absente.png'))).status)
      .toBe(404);
  });

  /**
   * Le point de la bascule : le dépôt ne prend plus de chemin. Une plante sans
   * image est refusée AU DÉPÔT, pas découverte par l'ouvrier après 165 s de GPU.
   */
  it('le dépôt d une tâche exige une source présente', async () => {
    const sans = await taches.POST(new NextRequest(`https://${HOTE}/api/generator/taches`, {
      method: 'POST', headers: { host: HOTE, 'content-type': 'application/json' },
      body: JSON.stringify({ plante: 'inconnue' }),
    }));
    expect(sans.status).toBe(400);
    expect((await sans.json()).error).toContain('inconnue');

    await PUT(envoi('connue.png', IMG), params('connue.png'));
    const avec = await taches.POST(new NextRequest(`https://${HOTE}/api/generator/taches`, {
      method: 'POST', headers: { host: HOTE, 'content-type': 'application/json' },
      body: JSON.stringify({ plante: 'connue' }),
    }));
    expect(avec.status).toBe(201);
    expect((await avec.json()).image).toBe('connue.png');
  });

  it('la liste signale une plante déjà en file', async () => {
    await PUT(envoi('enfile.png', IMG), params('enfile.png'));
    await taches.POST(new NextRequest(`https://${HOTE}/api/generator/taches`, {
      method: 'POST', headers: { host: HOTE, 'content-type': 'application/json' },
      body: JSON.stringify({ plante: 'enfile' }),
    }));
    const l = (await (await liste(req('/api/generator/sources'))).json()).sources;
    expect(l[0].enFile).toBe(true);
  });

  it('n existe pas depuis le site public', async () => {
    const pub = 'web.arbore.app';
    expect((await liste(req('/api/generator/sources', pub))).status).toBe(404);
    expect((await GET(req('/api/generator/sources/a.png', pub), params('a.png'))).status).toBe(404);
    expect((await PUT(envoi('a.png', IMG, pub), params('a.png'))).status).toBe(404);
    expect((await DELETE(req('/api/generator/sources/a.png', pub), params('a.png'))).status).toBe(404);
  });
});
