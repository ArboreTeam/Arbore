// @vitest-environment node
//
// Tests d'intégration des routes de la file.
//
// Ils appellent les gestionnaires de route directement, avec de vraies
// `NextRequest` : ce qui est vérifié ici, c'est le contrat HTTP que l'ouvrier
// du notebook consomme — codes de retour, noms de champs, et surtout le trajet
// du jeton de réservation. Le dépôt a ses propres tests ; on ne les rejoue pas.
import { describe, it, expect, beforeEach, afterAll } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BAC = mkdtempSync(join(tmpdir(), 'routes-atelier-'));
process.env.GENERATOR_DATA_DIR = BAC;
process.env.GENERATOR_HOST = 'generator.arbore.app';

// Imports statiques, et non `await import()` : la cible TypeScript du projet
// est es5, qui n'admet pas d'`await` au niveau racine — `next build` échoue
// alors que vitest, lui, l'accepte sans broncher. Rien ne l'exige ici : le
// dépôt lit `GENERATOR_DATA_DIR` à l'appel, dans `racine()`, pas au
// chargement du module.
import { NextRequest } from 'next/server';

import { reinitialiser, EXPIRATION_MS, lire, prendre } from '@/lib/generator/depot';

import * as taches from './taches/route';
import * as prendreRoute from './taches/prendre/route';
import * as resultat from './taches/[id]/resultat/route';
import * as echec from './taches/[id]/echec/route';
import * as graines from './plantes/[plante]/graines/route';
import * as revue from './revue/route';
import * as verdict from './revue/[plante]/route';

afterAll(() => rmSync(BAC, { recursive: true, force: true }));

const HOTE = 'generator.arbore.app';

function req(chemin: string, corps?: unknown, hote = HOTE) {
  return new NextRequest(`https://${hote}${chemin}`, {
    method: corps === undefined ? 'GET' : 'POST',
    headers: { host: hote, 'content-type': 'application/json' },
    body: corps === undefined ? undefined : JSON.stringify(corps),
  });
}

const params = <T extends object>(p: T) => ({ params: Promise.resolve(p) });

/**
 * Pose l'image source de la plante.
 *
 * Le dépôt ne prend plus de chemin : il retrouve la source sur le volume. Une
 * plante sans image ne peut donc PAS être déposée, et c'est voulu — l'erreur
 * est rendue à l'appelant plutôt que découverte par l'ouvrier après 165 s de
 * GPU.
 */
function poserSource(plante: string) {
  mkdirSync(join(BAC, 'sources'), { recursive: true });
  writeFileSync(join(BAC, 'sources', `${plante}.png`), Buffer.alloc(32, 1));
}

describe('routes de la file — cycle de l ouvrier', () => {
  beforeEach(() => {
    reinitialiser();
    rmSync(join(BAC, 'sources'), { recursive: true, force: true });
  });

  it('dépose, prend, livre', async () => {
    poserSource('nephrolepis');
    const depot = await taches.POST(req('/api/generator/taches', { plante: 'nephrolepis' }));
    expect(depot.status).toBe(201);

    const prise = await prendreRoute.POST(req('/api/generator/taches/prendre', {}));
    expect(prise.status).toBe(200);
    const tache = await prise.json();
    expect(tache.plante).toBe('nephrolepis');
    expect(tache.reservation).toBeTruthy();
    // L'exclusion voyage avec la tâche : l'ouvrier n'a pas à la demander.
    expect(tache.exclure).toEqual([]);

    const livraison = await resultat.POST(
      req(`/api/generator/taches/${tache.id}/resultat`, {
        reservation: tache.reservation, graine: 42, accepte: true,
      }),
      params({ id: tache.id }),
    );
    expect(livraison.status).toBe(200);
  });

  it('rend 204 quand la file est vide, et non une erreur', async () => {
    const r = await prendreRoute.POST(req('/api/generator/taches/prendre', {}));
    expect(r.status).toBe(204);
    expect(await r.text()).toBe('');
  });

  it('refuse une livraison sans jeton de réservation', async () => {
    poserSource('a');
    await taches.POST(req('/api/generator/taches', { plante: 'a' }));
    const tache = await (await prendreRoute.POST(req('/api/generator/taches/prendre', {}))).json();

    const r = await resultat.POST(
      req(`/api/generator/taches/${tache.id}/resultat`, { graine: 1, accepte: true }),
      params({ id: tache.id }),
    );
    expect(r.status).toBe(400);
  });

  /**
   * Le défaut que les tests du dépôt ont trouvé, vu depuis l'HTTP : l'ouvrier
   * dont la réservation a expiré doit recevoir 409 et jeter son résultat, pas
   * écraser le travail de celui qui a repris la tâche.
   */
  it('rend 409 à une réservation périmée, en distinguant du 404', async () => {
    poserSource('lente');
    await taches.POST(req('/api/generator/taches', { plante: 'lente' }));
    const premier = await (await prendreRoute.POST(req('/api/generator/taches/prendre', {}))).json();

    // La tâche expire et un second ouvrier la reprend. Même identifiant.
    const second = await prendre(Date.now() + EXPIRATION_MS + 1000);
    expect(second!.id).toBe(premier.id);
    expect(second!.reservation).not.toBe(premier.reservation);

    const perime = await resultat.POST(
      req(`/api/generator/taches/${premier.id}/resultat`, {
        reservation: premier.reservation, graine: 1, accepte: true,
      }),
      params({ id: premier.id }),
    );
    expect(perime.status).toBe(409);

    const bon = await resultat.POST(
      req(`/api/generator/taches/${premier.id}/resultat`, {
        reservation: second!.reservation, graine: 2, accepte: true,
      }),
      params({ id: premier.id }),
    );
    expect(bon.status).toBe(200);
    expect(lire().taches[0].resultat?.graine).toBe(2);
  });

  it('enregistre un échec et le motif', async () => {
    poserSource('rate');
    await taches.POST(req('/api/generator/taches', { plante: 'rate' }));
    const t = await (await prendreRoute.POST(req('/api/generator/taches/prendre', {}))).json();

    const r = await echec.POST(
      req(`/api/generator/taches/${t.id}/echec`, {
        reservation: t.reservation, erreur: 'delai_max_depasse',
      }),
      params({ id: t.id }),
    );
    expect(r.status).toBe(200);
    expect(lire().taches[0].etat).toBe('echec');
    expect(lire().taches[0].erreur).toBe('delai_max_depasse');
  });

  it('refuse une tâche sans plante, ou dont l image n existe pas', async () => {
    expect((await taches.POST(req('/api/generator/taches', {}))).status).toBe(400);
    // Nommée mais sans source sur le volume : refusée ici, pas plus tard.
    expect((await taches.POST(req('/api/generator/taches', { plante: 'fantome' }))).status)
      .toBe(400);
    poserSource('reelle');
    expect((await taches.POST(req('/api/generator/taches', { plante: 'reelle' }))).status)
      .toBe(201);
  });

  it('ne rend pas 500 sur un corps qui n est pas du JSON', async () => {
    const brut = new NextRequest(`https://${HOTE}/api/generator/taches`, {
      method: 'POST', headers: { host: HOTE }, body: 'ceci n est pas du json',
    });
    expect((await taches.POST(brut)).status).toBe(400);
  });

  it('ne diffuse pas le jeton de réservation dans le tableau de bord', async () => {
    poserSource('x');
    await taches.POST(req('/api/generator/taches', { plante: 'x' }));
    await prendreRoute.POST(req('/api/generator/taches/prendre', {}));

    const corps = await (await taches.GET(req('/api/generator/taches'))).json();
    expect(corps.taches[0].etat).toBe('en_cours');
    expect(corps.taches[0]).not.toHaveProperty('reservation');
    // Ni les chemins d'artefacts : le tableau de bord n'a pas besoin de la
    // disposition du volume pour afficher un verdict.
    expect(corps.taches[0]).not.toHaveProperty('resultat');
  });
});

describe('routes de la file — historique des graines', () => {
  beforeEach(() => {
    reinitialiser();
    rmSync(join(BAC, 'sources'), { recursive: true, force: true });
  });

  it('consigne une graine avant génération et la rend à la prise suivante', async () => {
    const p = params({ plante: 'ficus' });
    expect((await (await graines.GET(req('/api/generator/plantes/ficus/graines'), p)).json()).graines)
      .toEqual([]);

    await graines.POST(req('/api/generator/plantes/ficus/graines', { graine: 7 }), p);
    await graines.POST(req('/api/generator/plantes/ficus/graines', { graine: 7 }), p);
    await graines.POST(req('/api/generator/plantes/ficus/graines', { graine: 9 }), p);

    const lues = await (await graines.GET(req('/api/generator/plantes/ficus/graines'), p)).json();
    expect(lues.graines).toEqual([7, 9]);

    // Et une tâche déposée APRÈS voit bien ces graines : l'exclusion est relue
    // à la prise, sinon une relance rejouerait la graine qui a échoué.
    poserSource('ficus');
    await taches.POST(req('/api/generator/taches', { plante: 'ficus' }));
    const t = await (await prendreRoute.POST(req('/api/generator/taches/prendre', {}))).json();
    expect(t.exclure).toEqual([7, 9]);
  });

  it('refuse une graine absente ou non numérique', async () => {
    const p = params({ plante: 'ficus' });
    expect((await graines.POST(req('/api/generator/plantes/ficus/graines', {}), p)).status).toBe(400);
    expect((await graines.POST(req('/api/generator/plantes/ficus/graines', { graine: 'sept' }), p)).status)
      .toBe(400);
  });
});

describe('routes de la file — revue', () => {
  beforeEach(() => {
    reinitialiser();
    rmSync(join(BAC, 'sources'), { recursive: true, force: true });
  });

  async function livrerUne(plante: string) {
    poserSource(plante);
    await taches.POST(req('/api/generator/taches', { plante }));
    const t = await (await prendreRoute.POST(req('/api/generator/taches/prendre', {}))).json();
    await resultat.POST(
      req(`/api/generator/taches/${t.id}/resultat`, {
        reservation: t.reservation, graine: 3, accepte: true,
        apercus: ['/data/generator/plantes/x/face.png'], arbitrage_requis: true,
      }),
      params({ id: t.id }),
    );
    return t;
  }

  it('présente les plantes livrées sans verdict, puis les retire', async () => {
    await livrerUne('monstera');
    let file = await (await revue.GET(req('/api/generator/revue'))).json();
    expect(file.file).toHaveLength(1);
    expect(file.file[0].plante).toBe('monstera');
    expect(file.file[0].arbitrage).toBe(true);

    const r = await verdict.POST(
      req('/api/generator/revue/monstera', { valide: true, coupe: 'y=0.31' }),
      params({ plante: 'monstera' }),
    );
    expect((await r.json()).verdict).toBe('validee');

    file = await (await revue.GET(req('/api/generator/revue'))).json();
    expect(file.file).toHaveLength(0);
  });

  it('une invalidation redépose une tâche sans graine imposée', async () => {
    await livrerUne('pilea');
    await verdict.POST(
      req('/api/generator/revue/pilea', { valide: false }),
      params({ plante: 'pilea' }),
    );

    const suivante = await (await prendreRoute.POST(req('/api/generator/taches/prendre', {}))).json();
    expect(suivante.plante).toBe('pilea');
    expect(suivante.raison).toBe('invalidee_revue');
    // Sans graine imposée : la graine rejetée est déjà dans l'exclusion, et la
    // réimposer reproduirait à l'identique le maillage qu'on vient de refuser.
    expect(suivante.graine).toBeNull();
    expect(suivante.exclure).toContain(3);
  });

  it('refuse un verdict qui ne tranche pas', async () => {
    await livrerUne('calathea');
    const p = params({ plante: 'calathea' });
    expect((await verdict.POST(req('/api/generator/revue/calathea', {}), p)).status).toBe(400);
    expect((await verdict.POST(req('/api/generator/revue/calathea', { valide: 'oui' }), p)).status)
      .toBe(400);
  });
});

/**
 * La protection croisée, au niveau des routes.
 *
 * Le middleware refuse déjà tout ce qui ne vient pas de l'hôte de l'atelier.
 * Ceci est une ceinture de plus : une route qui échapperait un jour au matcher
 * ne serait pas pour autant ouverte sur web.arbore.app.
 */
describe('routes de la file — hors de l hôte de l atelier', () => {
  beforeEach(() => {
    reinitialiser();
    rmSync(join(BAC, 'sources'), { recursive: true, force: true });
  });

  it('rend 404 sur chaque route depuis le site public', async () => {
    const autre = 'web.arbore.app';
    const appels: Array<[string, Promise<Response>]> = [
      ['taches GET', Promise.resolve(taches.GET(req('/api/generator/taches', undefined, autre)))],
      ['taches POST', taches.POST(req('/api/generator/taches', { plante: 'a', image: '/a.png' }, autre))],
      ['prendre', prendreRoute.POST(req('/api/generator/taches/prendre', {}, autre))],
      ['resultat', resultat.POST(
        req('/api/generator/taches/x/resultat', { reservation: 'r' }, autre), params({ id: 'x' }))],
      ['echec', echec.POST(
        req('/api/generator/taches/x/echec', { reservation: 'r' }, autre), params({ id: 'x' }))],
      ['graines GET', Promise.resolve(graines.GET(
        req('/api/generator/plantes/a/graines', undefined, autre), params({ plante: 'a' })))],
      ['graines POST', graines.POST(
        req('/api/generator/plantes/a/graines', { graine: 1 }, autre), params({ plante: 'a' }))],
      ['revue GET', Promise.resolve(revue.GET(req('/api/generator/revue', undefined, autre)))],
      ['verdict', verdict.POST(
        req('/api/generator/revue/a', { valide: true }, autre), params({ plante: 'a' }))],
    ];

    for (const [nom, appel] of appels) {
      expect((await appel).status, nom).toBe(404);
    }
    // Et rien n'a été écrit au passage.
    expect(lire().taches).toHaveLength(0);
  });
});
