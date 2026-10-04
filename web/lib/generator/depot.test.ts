import { describe, it, expect, beforeEach, afterAll } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BAC = mkdtempSync(join(tmpdir(), 'atelier-'));
process.env.GENERATOR_DATA_DIR = BAC;

import {
  EXPIRATION_MS, aRevoir, cheminArtefact, deposer, echouer, historique,
  lire, livrer, noterGraine, prendre, reinitialiser, trancher,
} from './depot';

afterAll(() => rmSync(BAC, { recursive: true, force: true }));

describe('dépôt — file de tâches', () => {
  beforeEach(() => reinitialiser());

  it('rend les tâches dans l ordre de dépôt', async () => {
    await deposer('alpha', '/a.png');
    await deposer('beta', '/b.png');
    expect((await prendre())?.plante).toBe('alpha');
    expect((await prendre())?.plante).toBe('beta');
    expect(await prendre()).toBeNull();
  });

  it('deux prises concurrentes ne rendent jamais la même tâche', async () => {
    // Le cas qui compte : deux ouvriers ouverts en même temps. Sans
    // sérialisation, les deux liraient le même état et prendraient la même.
    await deposer('seule', '/s.png');
    const [a, b] = await Promise.all([prendre(), prendre()]);
    expect([a, b].filter(Boolean)).toHaveLength(1);
  });

  it('dix prises concurrentes sur dix tâches donnent dix plantes distinctes', async () => {
    for (let i = 0; i < 10; i += 1) await deposer(`p${i}`, `/p${i}.png`);
    const prises = await Promise.all(Array.from({ length: 10 }, () => prendre()));
    const noms = prises.map((p) => p?.plante);
    expect(new Set(noms).size).toBe(10);
  });

  it('remet en attente une réservation expirée', async () => {
    await deposer('lente', '/l.png');
    const t0 = Date.now();
    expect(await prendre(t0)).not.toBeNull();
    expect(await prendre(t0 + 1000)).toBeNull();          // encore réservée
    const reprise = await prendre(t0 + EXPIRATION_MS + 1);
    expect(reprise?.plante).toBe('lente');
    expect(reprise?.raison).toBe('reservation_expiree');
  });

  it('refuse la livraison d une tâche reprise ailleurs', async () => {
    // L ouvrier bloqué revient avec son résultat après expiration : on le jette
    // plutôt que d écraser le travail de celui qui a repris.
    await deposer('lente', '/l.png');
    const t0 = Date.now();
    const premier = await prendre(t0);
    const second = await prendre(t0 + EXPIRATION_MS + 1);   // repris par un autre
    // Même tâche, même identifiant — seule la réservation les distingue.
    expect(premier!.id).toBe(second!.id);
    expect(await livrer(premier!.id, premier!.reservation!, { graine: 1 })).toBe(false);
    expect(await livrer(second!.id, second!.reservation!, { graine: 2 })).toBe(true);
  });

  it('consigne un échec sans perdre la tâche', async () => {
    await deposer('cassee', '/c.png');
    const t = await prendre();
    expect(await echouer(t!.id, t!.reservation!, 'boum')).toBe(true);
    expect(lire().taches[0].etat).toBe('echec');
  });
});

describe('dépôt — graines', () => {
  beforeEach(() => reinitialiser());

  it('consigne sans doublon et dans l ordre', async () => {
    await noterGraine('p', 42);
    await noterGraine('p', 7);
    await noterGraine('p', 42);
    expect(historique('p')).toEqual([42, 7]);
  });

  it('la prise relit l historique AU MOMENT de la prise', async () => {
    // Une tâche déposée hier doit tenir compte des graines consommées depuis.
    await deposer('p', '/p.png');
    await noterGraine('p', 99);
    expect((await prendre())?.exclure).toEqual([99]);
  });

  it('survit à un échec : trois sessions, trois exclusions croissantes', async () => {
    // Sans cela, une relance après expiration retirerait la même graine et
    // reproduirait exactement la même panne.
    for (const g of [11, 22, 33]) {
      await deposer('p', '/p.png');
      const t = await prendre();
      expect(t?.exclure).toHaveLength([11, 22, 33].indexOf(g));
      await noterGraine('p', g);
      await echouer(t!.id, t!.reservation!, 'délai dépassé');
    }
    expect(historique('p')).toEqual([11, 22, 33]);
  });

  it('cloisonne les plantes', async () => {
    await noterGraine('a', 1);
    expect(historique('b')).toEqual([]);
  });
});

describe('dépôt — la graine livrée entre dans l historique', () => {
  beforeEach(() => reinitialiser());

  /**
   * L'ouvrier consigne la graine avant de générer, et c'est ce qui couvre les
   * échecs et les expirations. Mais cet appel-là peut échouer alors que la
   * génération réussit : le dépôt ne doit pas dépendre de la discipline du
   * client pour une invariante qui lui appartient — une graine rejetée perdue
   * de l'historique serait rejouée à l'identique au premier verdict négatif.
   */
  it('consigne la graine d une livraison même sans appel préalable', async () => {
    await deposer('sansaveu', '/s.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, { graine: 77, accepte: true });
    expect(historique('sansaveu')).toEqual([77]);
  });

  it('ne double pas une graine déjà consignée', async () => {
    await deposer('deuxfois', '/d.png');
    await noterGraine('deuxfois', 55);
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, { graine: 55, accepte: false });
    expect(historique('deuxfois')).toEqual([55]);
  });

  it('ignore une livraison sans graine exploitable', async () => {
    await deposer('muette', '/m.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, { accepte: true });
    expect(historique('muette')).toEqual([]);
  });

  /** Une réservation périmée n'écrit rien, pas même une graine. */
  it('une livraison refusée ne consigne aucune graine', async () => {
    await deposer('tardive', '/t.png');
    const premier = await prendre();
    const second = await prendre(Date.now() + EXPIRATION_MS + 1000);
    await livrer(premier!.id, premier!.reservation!, { graine: 99, accepte: true });
    expect(historique('tardive')).not.toContain(99);
    await livrer(second!.id, second!.reservation!, { graine: 100, accepte: true });
    expect(historique('tardive')).toEqual([100]);
  });
});

describe('dépôt — revue', () => {
  beforeEach(() => reinitialiser());

  async function livrerUne(plante: string, arbitrage: boolean) {
    await deposer(plante, `/${plante}.png`);
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, {
      graine: 5, accepte: true, apercus: ['a.png'],
      candidats_pot: arbitrage ? [{ voie: 'geometrie' }, { voie: 'couleur' }] : [{ voie: 'geometrie' }],
      arbitrage_requis: arbitrage,
    });
  }

  it('ne propose que les plantes livrées non tranchées', async () => {
    await livrerUne('vue', false);
    await deposer('pas_encore', '/x.png');
    const file = aRevoir();
    expect(file.map((f) => f.plante)).toEqual(['vue']);
  });

  it('signale l arbitrage quand deux candidats existent', async () => {
    await livrerUne('ambigue', true);
    expect(aRevoir()[0].arbitrage).toBe(true);
    expect(aRevoir()[0].candidats).toHaveLength(2);
  });

  it('une validation sort la plante de la file de revue', async () => {
    await livrerUne('ok', false);
    await trancher('ok', true, 'geometrie');
    expect(aRevoir()).toHaveLength(0);
    expect(lire().plantes.ok.coupe).toBe('geometrie');
  });

  it('une invalidation redépose une tâche, seul chemin qui remonte au GPU', async () => {
    await livrerUne('ratee', false);
    await trancher('ratee', false);
    const taches = lire().taches.filter((t) => t.etat === 'en_attente');
    expect(taches).toHaveLength(1);
    expect(taches[0].raison).toBe('invalidee_revue');
    expect(taches[0].graine).toBeNull();   // une graine neuve sera tirée
  });
});

describe('dépôt — chemins d artefacts', () => {
  it('refuse une traversée de répertoire', () => {
    for (const mauvais of ['../etc', 'a/b', 'p l']) {
      expect(() => cheminArtefact(mauvais, 'x.glb')).toThrow();
    }
    expect(() => cheminArtefact('ok', '../../etc/passwd')).toThrow();
  });

  it('accepte un nom de plante normal', () => {
    expect(cheminArtefact('nephrolepis', 'apercu_000.png')).toContain('nephrolepis');
  });
});
