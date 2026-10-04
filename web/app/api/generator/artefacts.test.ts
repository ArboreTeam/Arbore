// @vitest-environment node
//
// La route des artefacts lit un fichier d'après deux segments d'URL. C'est le
// seul endroit de l'atelier où une valeur venue du réseau désigne un chemin,
// donc les cas hostiles sont la moitié de ces tests.
import { describe, it, expect, beforeEach, afterAll } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BAC = mkdtempSync(join(tmpdir(), 'artefacts-'));
process.env.GENERATOR_DATA_DIR = BAC;
process.env.GENERATOR_HOST = 'generator.arbore.app';

import { NextRequest } from 'next/server';

import { GET } from './artefacts/[plante]/[fichier]/route';

afterAll(() => rmSync(BAC, { recursive: true, force: true }));

const HOTE = 'generator.arbore.app';
const PNG = Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex');

function req(chemin: string, hote = HOTE) {
  return new NextRequest(`https://${hote}${chemin}`, { headers: { host: hote } });
}
const params = (plante: string, fichier: string) =>
  ({ params: Promise.resolve({ plante, fichier }) });

describe('route des artefacts', () => {
  beforeEach(() => {
    rmSync(join(BAC, 'plantes'), { recursive: true, force: true });
    mkdirSync(join(BAC, 'plantes', 'nephrolepis'), { recursive: true });
    writeFileSync(join(BAC, 'plantes', 'nephrolepis', 'apercu_000.png'), PNG);
    writeFileSync(join(BAC, 'plantes', 'nephrolepis', 'sanspot_geometrie.glb'), Buffer.from('glTF'));
    // Un fichier qui n'a aucune raison de sortir par cette route.
    writeFileSync(join(BAC, 'plantes', 'nephrolepis', 'notes.json'), '{"secret":1}');
    writeFileSync(join(BAC, 'secret.png'), PNG);
  });

  it('sert un aperçu avec le bon type', async () => {
    const r = await GET(req('/api/generator/artefacts/nephrolepis/apercu_000.png'),
                        params('nephrolepis', 'apercu_000.png'));
    expect(r.status).toBe(200);
    expect(r.headers.get('content-type')).toBe('image/png');
    expect(r.headers.get('content-length')).toBe(String(PNG.length));
    expect(Buffer.from(await r.arrayBuffer())).toEqual(PNG);
  });

  it('sert un GLB coupé', async () => {
    const r = await GET(req('/api/generator/artefacts/nephrolepis/sanspot_geometrie.glb'),
                        params('nephrolepis', 'sanspot_geometrie.glb'));
    expect(r.status).toBe(200);
    expect(r.headers.get('content-type')).toBe('model/gltf-binary');
  });

  /**
   * Le piège qui aurait fait invalider une plante à tort : un nom d'aperçu est
   * stable alors que son contenu change à chaque relance sur graine neuve.
   */
  it('interdit la mise en cache', async () => {
    const r = await GET(req('/api/generator/artefacts/nephrolepis/apercu_000.png'),
                        params('nephrolepis', 'apercu_000.png'));
    expect(r.headers.get('cache-control')).toContain('no-store');
    expect(r.headers.get('x-content-type-options')).toBe('nosniff');
  });

  it('rend 404 sur un artefact absent', async () => {
    const r = await GET(req('/api/generator/artefacts/nephrolepis/apercu_999.png'),
                        params('nephrolepis', 'apercu_999.png'));
    expect(r.status).toBe(404);
  });

  it('ne sert que les extensions de la liste blanche', async () => {
    for (const nom of ['notes.json', 'etat.json', 'x.env', 'x.ts', 'x']) {
      const r = await GET(req(`/api/generator/artefacts/nephrolepis/${nom}`),
                          params('nephrolepis', nom));
      expect(r.status, nom).toBe(404);
    }
  });

  /** Le cœur du sujet : aucun de ces appels ne doit lire hors du dossier. */
  it('refuse toute tentative de sortie du dossier de la plante', async () => {
    const cas: Array<[string, string]> = [
      ['nephrolepis', '../secret.png'],
      ['nephrolepis', '..%2Fsecret.png'],
      ['nephrolepis', '....//secret.png'],
      ['nephrolepis', '/etc/hosts'],
      ['..', 'secret.png'],
      ['../..', 'secret.png'],
      ['nephrolepis/../..', 'secret.png'],
      ['', 'apercu_000.png'],
      ['néphrolépis', 'apercu_000.png'],
      ['plantes', 'secret.png'],
    ];
    for (const [plante, fichier] of cas) {
      const r = await GET(req('/api/generator/artefacts/x/y'), params(plante, fichier));
      expect(r.status, `${plante} / ${fichier}`).toBe(404);
    }
  });

  it('n existe pas depuis le site public', async () => {
    const r = await GET(req('/api/generator/artefacts/nephrolepis/apercu_000.png', 'web.arbore.app'),
                        params('nephrolepis', 'apercu_000.png'));
    expect(r.status).toBe(404);
  });
});
