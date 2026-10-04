// @vitest-environment node
//
// La route des artefacts lit un fichier d'après deux segments d'URL. C'est le
// seul endroit de l'atelier où une valeur venue du réseau désigne un chemin,
// donc les cas hostiles sont la moitié de ces tests.
import { describe, it, expect, beforeEach, afterAll } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BAC = mkdtempSync(join(tmpdir(), 'artefacts-'));
process.env.GENERATOR_DATA_DIR = BAC;
process.env.GENERATOR_HOST = 'generator.arbore.app';

import { NextRequest } from 'next/server';

import { GET, PUT } from './artefacts/[plante]/[fichier]/route';

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

describe('téléversement d un artefact', () => {
  function put(plante: string, nom: string, corps: BodyInit | null,
               opts: { position?: number; final?: boolean; hote?: string } = {}) {
    const hote = opts.hote ?? HOTE;
    const p = new URLSearchParams();
    p.set('position', String(opts.position ?? 0));
    if (opts.final ?? true) p.set('final', '1');
    return new NextRequest(
      `https://${hote}/api/generator/artefacts/${plante}/${nom}?${p}`,
      {
        // `duplex` est exigé par undici dès qu'un corps est un flux, et le
        // type de RequestInit l'accepte désormais : aucune suppression
        // d'erreur n'est nécessaire ici. Ne pas en remettre une — devenue
        // inutile, elle fait échouer `next build`, qui la signale comme telle
        // alors que vitest l'ignore.
        method: 'PUT', headers: { host: hote }, body: corps, duplex: 'half',
      },
    );
  }
  const sur = (plante: string, nom: string) => join(BAC, 'plantes', plante, nom);

  it('écrit un aperçu en une seule requête et le ressert à l identique', async () => {
    const r = await PUT(put('nouvelle', 'apercu_000.png', PNG),
                        params('nouvelle', 'apercu_000.png'));
    expect(r.status).toBe(201);
    expect((await r.json()).octets).toBe(PNG.length);

    const lu = await GET(req('/api/generator/artefacts/nouvelle/apercu_000.png'),
                         params('nouvelle', 'apercu_000.png'));
    expect(Buffer.from(await lu.arrayBuffer())).toEqual(PNG);
  });

  /** Le cas réel : un GLB qui dépasse les plafonds, envoyé en plusieurs fois. */
  it('assemble un fichier envoyé en trois morceaux', async () => {
    const morceaux = [Buffer.from('glTF____'), Buffer.from('PARTIE_DEUX'), Buffer.from('FIN!')];
    let position = 0;

    for (let i = 0; i < morceaux.length; i += 1) {
      const dernier = i === morceaux.length - 1;
      const r = await PUT(
        put('gros', 'sanspot_geometrie.glb', morceaux[i], { position, final: dernier }),
        params('gros', 'sanspot_geometrie.glb'));
      expect(r.status, `morceau ${i}`).toBe(dernier ? 201 : 200);
      position += morceaux[i].length;

      // Tant que ce n'est pas fini, RIEN ne doit être visible sous le vrai nom :
      // la revue servirait sinon un maillage amputé sans rien signaler.
      expect(existsSync(sur('gros', 'sanspot_geometrie.glb')), `visible au morceau ${i}`)
        .toBe(dernier);
    }

    expect(readFileSync(sur('gros', 'sanspot_geometrie.glb')).toString())
      .toBe('glTF____PARTIE_DEUXFIN!');
  });

  /**
   * Sans ce contrôle, un morceau rejoué ou perdu produirait un fichier mal
   * assemblé que rien ne distinguerait d'un fichier sain.
   */
  it('refuse un morceau hors séquence et dit où il en est', async () => {
    await PUT(put('desordre', 'a.glb', Buffer.from('12345'), { position: 0, final: false }),
              params('desordre', 'a.glb'));

    const trop_loin = await PUT(
      put('desordre', 'a.glb', Buffer.from('xx'), { position: 999, final: true }),
      params('desordre', 'a.glb'));
    expect(trop_loin.status).toBe(409);
    expect((await trop_loin.json()).attendu).toBe(5);

    const rejoue = await PUT(
      put('desordre', 'a.glb', Buffer.from('xx'), { position: 0, final: true }),
      params('desordre', 'a.glb'));
    expect(rejoue.status).toBe(409);

    // Et la bonne position reprend là où on en était.
    const suite = await PUT(
      put('desordre', 'a.glb', Buffer.from('678'), { position: 5, final: true }),
      params('desordre', 'a.glb'));
    expect(suite.status).toBe(201);
    expect(readFileSync(sur('desordre', 'a.glb')).toString()).toBe('12345678');
  });

  it('crée le dossier de la plante au passage', async () => {
    expect(existsSync(join(BAC, 'plantes', 'inedite'))).toBe(false);
    const r = await PUT(put('inedite', 'sanspot_couleur.glb', Buffer.from('glTF____')),
                        params('inedite', 'sanspot_couleur.glb'));
    expect(r.status).toBe(201);
  });

  it('remplace un artefact existant', async () => {
    await PUT(put('nephrolepis', 'apercu_000.png', Buffer.from('neuf')),
              params('nephrolepis', 'apercu_000.png'));
    expect(readFileSync(sur('nephrolepis', 'apercu_000.png')).toString()).toBe('neuf');
  });

  it('refuse une extension hors liste blanche', async () => {
    for (const nom of ['notes.json', 'script.sh', 'x.env', 'sansext']) {
      const r = await PUT(put('nephrolepis', nom, Buffer.from('x')), params('nephrolepis', nom));
      expect(r.status, nom).toBe(404);
    }
    expect(existsSync(sur('nephrolepis', 'script.sh'))).toBe(false);
  });

  it('refuse d écrire hors du dossier de la plante', async () => {
    const cas: Array<[string, string]> = [
      ['nephrolepis', '../evade.png'], ['..', 'evade.png'],
      ['nephrolepis/..', 'evade.png'], ['néphrolépis', 'a.png'],
    ];
    for (const [plante, fichier] of cas) {
      const r = await PUT(put('x', 'y.png', Buffer.from('x')), params(plante, fichier));
      expect(r.status, `${plante} / ${fichier}`).toBe(404);
    }
    expect(existsSync(join(BAC, 'evade.png'))).toBe(false);
  });

  it('refuse une position absurde', async () => {
    for (const position of [-1, 1.5, Number.NaN, 9e9]) {
      const r = await PUT(put('nephrolepis', 'a.png', PNG, { position }),
                          params('nephrolepis', 'a.png'));
      expect(r.status, String(position)).toBe(400);
    }
  });

  it('ne laisse aucun fichier derrière un flux qui casse', async () => {
    const casse = new ReadableStream<Uint8Array>({
      start(ctrl) {
        ctrl.enqueue(new Uint8Array([103, 108, 84, 70]));
        ctrl.error(new Error('lien coupé'));
      },
    });
    const r = await PUT(put('nephrolepis', 'tronque.glb', casse),
                        params('nephrolepis', 'tronque.glb'));
    expect(r.status).toBe(400);
    expect(existsSync(sur('nephrolepis', 'tronque.glb'))).toBe(false);
    expect(readdirSync(join(BAC, 'plantes', 'nephrolepis')).filter((f) => f.includes('partiel')))
      .toEqual([]);
  });

  it('n existe pas depuis le site public', async () => {
    const r = await PUT(put('nephrolepis', 'a.png', PNG, { hote: 'web.arbore.app' }),
                        params('nephrolepis', 'a.png'));
    expect(r.status).toBe(404);
  });
});
