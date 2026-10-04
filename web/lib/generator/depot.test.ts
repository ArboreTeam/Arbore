import { describe, it, expect, beforeEach, afterAll } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BAC = mkdtempSync(join(tmpdir(), 'atelier-'));
process.env.GENERATOR_DATA_DIR = BAC;

import {
  EXPIRATION_MS, aRevoir, bilan, cheminArtefact, deposer, echouer, historique,
  lire, livrer, nomFichier, noterGraine, prendre, reinitialiser, trancher,
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

describe('dépôt — nomFichier, la garde des chemins venus de l ouvrier', () => {
  /**
   * L'ouvrier consigne des chemins ABSOLUS de sa propre machine. Les suivre
   * serait laisser une valeur arrivée par le réseau désigner le fichier à
   * lire. On n'en garde que le nom.
   */
  it('réduit un chemin Colab à son nom de fichier', () => {
    expect(nomFichier('/content/pipeline/resultats/nephrolepis/apercu_000.png'))
      .toBe('apercu_000.png');
    expect(nomFichier('/content/drive/MyDrive/x/sanspot_geometrie.glb'))
      .toBe('sanspot_geometrie.glb');
  });

  it('accepte un nom déjà nu', () => {
    expect(nomFichier('apercu_060.png')).toBe('apercu_060.png');
  });

  it('refuse tout ce qui pourrait sortir du dossier', () => {
    for (const hostile of [
      '..', '../etc/passwd', '/etc/passwd/..', 'a/../../b', '..%2fetc',
      '....//passwd', '.hidden', '-rf', '', '   ', '/',
    ]) {
      expect(nomFichier(hostile), hostile).toBeNull();
    }
  });

  /** Un séparateur Windows doit couper comme un slash, sinon il passe entier. */
  it('coupe aussi sur un antislash', () => {
    expect(nomFichier('C:\\travail\\plantes\\apercu_120.png')).toBe('apercu_120.png');
    expect(nomFichier('..\\..\\secret')).toBeNull();
  });

  it('refuse ce qui n est pas une chaîne', () => {
    for (const v of [null, undefined, 42, {}, [], true]) {
      expect(nomFichier(v)).toBeNull();
    }
  });

  /**
   * La garde de `nomFichier` et celle de `cheminArtefact` doivent être
   * d'accord : un nom accepté par la première ne doit jamais faire lever la
   * seconde, sinon la revue plante sur un artefact légitime.
   */
  it('tout nom qu elle accepte est accepté par cheminArtefact', () => {
    for (const bon of ['apercu_000.png', 'sanspot_couleur.glb', 'nephrolepis.glb',
                       'a.png', 'A_1-2.3.glb']) {
      const nom = nomFichier(bon);
      expect(nom).not.toBeNull();
      expect(() => cheminArtefact('plante', nom!)).not.toThrow();
    }
  });
});

describe('dépôt — ce que la revue reçoit', () => {
  beforeEach(() => reinitialiser());

  async function livrerAvecArtefacts() {
    await deposer('nephrolepis', '/img/nephrolepis.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, {
      graine: 1312, essai: 2, secondes: 165.2, triangles: 1764560, octets: 42_000_000,
      dominante: 0.998, grosses: 1, plans: 0.12, accepte: true, vram_go: 18.4,
      glb: '/content/resultats/nephrolepis/nephrolepis.glb',
      apercus: [
        '/content/resultats/nephrolepis/apercu_000.png',
        '/content/resultats/nephrolepis/apercu_060.png',
      ],
      candidats_pot: [
        { voie: 'geometrie', fichier: '/content/x/sanspot_geometrie.glb', sommet: 0.31,
          aire_retiree: 0.184, confiance_paroi: 0.62,
          apercus: ['/content/x/sanspot_geometrie_000.png'] },
        { voie: 'couleur', fichier: '/content/x/sanspot_couleur.glb', sommet: 0.28,
          aire_retiree: 0.217, confiance_paroi: 0.58, apercus: [] },
      ],
      arbitrage_requis: true,
    });
  }

  it('livre les mesures et des noms de fichiers, jamais des chemins', async () => {
    await livrerAvecArtefacts();
    const [v] = aRevoir();
    expect(v.plante).toBe('nephrolepis');
    expect(v.graine).toBe(1312);
    expect(v.triangles).toBe(1764560);
    expect(v.dominante).toBeCloseTo(0.998);
    expect(v.apercus).toEqual(['apercu_000.png', 'apercu_060.png']);
    expect(v.glb).toBe('nephrolepis.glb');
    expect(v.arbitrage).toBe(true);
    // Aucun chemin absolu ne doit survivre jusqu'à la page.
    expect(JSON.stringify(v)).not.toContain('/content');
  });

  it('normalise les candidats et leurs aperçus', async () => {
    await livrerAvecArtefacts();
    const [v] = aRevoir();
    expect(v.candidats).toHaveLength(2);
    expect(v.candidats[0]).toMatchObject({
      voie: 'geometrie', fichier: 'sanspot_geometrie.glb',
      aireRetiree: 0.184, confianceParoi: 0.62,
    });
    expect(v.candidats[0].apercus).toEqual(['sanspot_geometrie_000.png']);
    expect(v.candidats[1].apercus).toEqual([]);
  });

  /** Une livraison partielle ne doit pas faire planter la revue. */
  it('survit à un résultat incomplet', async () => {
    await deposer('maigre', '/m.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, { accepte: false });
    const [v] = aRevoir();
    expect(v.graine).toBeNull();
    expect(v.triangles).toBeNull();
    expect(v.apercus).toEqual([]);
    expect(v.candidats).toEqual([]);
    expect(v.glb).toBeNull();
  });

  it('écarte un aperçu au nom hostile sans écarter les autres', async () => {
    await deposer('mixte', '/m.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, {
      accepte: true, apercus: ['/x/apercu_000.png', '../../etc/passwd', '/x/apercu_060.png'],
    });
    expect(aRevoir()[0].apercus).toEqual(['apercu_000.png', 'apercu_060.png']);
  });
});

describe('dépôt — bilan', () => {
  beforeEach(() => reinitialiser());

  it('compte chaque état', async () => {
    expect(bilan()).toMatchObject({ enAttente: 0, enCours: 0, livrees: 0, echecs: 0 });

    await deposer('a', '/a.png');
    await deposer('b', '/b.png');
    expect(bilan().enAttente).toBe(2);

    const t = await prendre();
    expect(bilan()).toMatchObject({ enAttente: 1, enCours: 1 });

    await livrer(t!.id, t!.reservation!, { graine: 5, accepte: true });
    expect(bilan()).toMatchObject({ livrees: 1, grainesBrulees: 1 });

    const u = await prendre();
    await echouer(u!.id, u!.reservation!, 'panne');
    expect(bilan().echecs).toBe(1);

    await trancher('a', true, 'y=0.3');
    expect(bilan()).toMatchObject({ validees: 1, invalidees: 0 });
  });

  /** Une invalidation redépose : le bilan doit le montrer. */
  it('une invalidation remet une tâche en attente', async () => {
    await deposer('c', '/c.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, { graine: 9, accepte: true });
    expect(bilan().enAttente).toBe(0);
    await trancher('c', false);
    expect(bilan()).toMatchObject({ enAttente: 1, invalidees: 1 });
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
