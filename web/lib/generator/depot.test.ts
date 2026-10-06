import { describe, it, expect, beforeEach, afterAll } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BAC = mkdtempSync(join(tmpdir(), 'atelier-'));
process.env.GENERATOR_DATA_DIR = BAC;

import { mkdirSync, writeFileSync, readdirSync } from 'node:fs';

import {
  EXPIRATION_MS, aRevoir, bilan, cheminArtefact, cleEmpreinte, deposer, echouer,
  empreinteRangee, historique, cheminSource, lire, livrer, marquerSansPot,
  nomFichier, noterEmpreinte, noterGraine, planteDe, posables, prendre, purger,
  recoupables, recouper, reinitialiser, sources, supprimerSource, trancher,
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
    await trancher('ok', 'validee', 'geometrie');
    expect(aRevoir()).toHaveLength(0);
    expect(lire().plantes.ok.coupe).toBe('geometrie');
  });

  it('une invalidation redépose une tâche, seul chemin qui remonte au GPU', async () => {
    await livrerUne('ratee', false);
    await trancher('ratee', 'invalidee');
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

describe('dépôt — le socle, pour poser un pot', () => {
  beforeEach(() => reinitialiser());

  async function livrerAvecSocle(plante: string, socle: unknown) {
    await deposer(plante, `/${plante}.png`);
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, {
      graine: 1, accepte: true,
      candidats_pot: [{ voie: 'geometrie', fichier: `/x/sanspot_geometrie.glb`, socle }],
    });
    return aRevoir()[0].candidats[0];
  }

  it('traverse l API quand il est complet', async () => {
    const c = await livrerAvecSocle('bonne', {
      x: -0.0002, z: -0.0876, y: -0.147, rayon: 0.15226, hauteur_modele: 0.92103,
    });
    expect(c.socle).toEqual({
      x: -0.0002, z: -0.0876, y: -0.147, rayon: 0.15226, hauteurModele: 0.92103,
    });
  });

  /**
   * Tout ou rien : un socle amputé d'une coordonnée poserait un pot de
   * travers, ce qui est pire qu'un pot absent.
   */
  it('est refusé en entier dès qu une valeur manque', async () => {
    for (const partiel of [
      { x: 0, z: 0, y: 0, rayon: 0.1 },
      { x: 0, z: 0, rayon: 0.1, hauteur_modele: 1 },
      { x: 'zéro', z: 0, y: 0, rayon: 0.1, hauteur_modele: 1 },
      { x: 0, z: 0, y: 0, rayon: Number.NaN, hauteur_modele: 1 },
    ]) {
      const c = await livrerAvecSocle(`p${Math.random().toString(36).slice(2, 7)}`, partiel);
      expect(c.socle, JSON.stringify(partiel)).toBeNull();
    }
  });

  /** La voie couleur ne mesure aucune révolution et rend un rayon nul. */
  it('refuse un rayon nul ou négatif', async () => {
    expect((await livrerAvecSocle('nulle', { x: 0, z: 0, y: 0, rayon: 0, hauteur_modele: 1 })).socle)
      .toBeNull();
    expect((await livrerAvecSocle('negative', { x: 0, z: 0, y: 0, rayon: -1, hauteur_modele: 1 })).socle)
      .toBeNull();
  });

  /** Les plantes d avant la mesure : cas normal, pas une erreur. */
  it('vaut null quand l ouvrier n en envoie pas', async () => {
    expect((await livrerAvecSocle('ancienne', undefined)).socle).toBeNull();
  });
});

describe('dépôt — écarter une plante', () => {
  beforeEach(() => reinitialiser());

  async function livrer_une(plante: string) {
    await deposer(plante, `/${plante}.png`);
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, { graine: 7, accepte: true });
  }

  /**
   * Invalider veut dire « refais-la », écarter veut dire « n'y reviens pas ».
   * Quand le défaut vient de la SOURCE — image dans l'image, étagère modélisée —
   * une graine neuve ne peut que le reproduire.
   */
  it('ne redépose pas, contrairement à l invalidation', async () => {
    await livrer_une('ratee');
    await trancher('ratee', 'ecartee', undefined, 'étagère modélisée sous le pot');
    expect(lire().taches.filter((t) => t.etat === 'en_attente')).toEqual([]);
    expect(lire().plantes.ratee.verdict).toBe('ecartee');
    expect(lire().plantes.ratee.raison).toContain('étagère');

    await livrer_une('refaire');
    await trancher('refaire', 'invalidee');
    expect(lire().taches.filter((t) => t.etat === 'en_attente')).toHaveLength(1);
  });

  it('sort de la revue et des posables', async () => {
    await deposer('sortie', '/s.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, {
      graine: 1, accepte: true,
      candidats_pot: [{ voie: 'geometrie', fichier: '/x/sanspot_geometrie.glb',
                        socle: { x: 0, z: 0, y: 0, rayon: 0.1, hauteur_modele: 1 } }],
    });
    expect(posables()).toHaveLength(1);
    await trancher('sortie', 'ecartee');
    expect(aRevoir()).toEqual([]);
    expect(posables()).toEqual([]);
  });

  it('ne garde aucun maillage, comme une invalidation', async () => {
    mkdirSync(join(BAC, 'plantes', 'nette'), { recursive: true });
    writeFileSync(cheminArtefact('nette', 'nette.glb'), Buffer.alloc(512));
    writeFileSync(cheminArtefact('nette', 'apercu_000.png'), Buffer.alloc(64));
    await deposer('nette', '/n.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, { graine: 1, accepte: true, glb: '/x/nette.glb' });

    await trancher('nette', 'ecartee');
    expect(readdirSync(join(BAC, 'plantes', 'nette'))).toEqual(['apercu_000.png']);
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

    await trancher('a', 'validee', 'y=0.3');
    expect(bilan()).toMatchObject({ validees: 1, invalidees: 0 });
  });

  /** Une invalidation redépose : le bilan doit le montrer. */
  it('une invalidation remet une tâche en attente', async () => {
    await deposer('c', '/c.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, { graine: 9, accepte: true });
    expect(bilan().enAttente).toBe(0);
    await trancher('c', 'invalidee');
    expect(bilan()).toMatchObject({ enAttente: 1, invalidees: 1 });
  });
});

describe('dépôt — purge des maillages après verdict', () => {
  /**
   * Le calcul qui justifie cette purge : 150 Mo par plante, 246 plantes au
   * catalogue, soit 37 Go — plus que le disque entier du VPS, et bien plus que
   * les 10 Go gratuits de R2. Les GLB sont de la sciure une fois le verdict
   * rendu ; les aperçus, eux, pèsent 1,4 Mo et disent ce qui a été jugé.
   */
  const GLB = Buffer.alloc(2048, 7);
  const PNG = Buffer.alloc(128, 3);

  function poser(plante: string, fichiers: string[]) {
    mkdirSync(join(BAC, 'plantes', plante), { recursive: true });
    for (const f of fichiers) {
      writeFileSync(cheminArtefact(plante, f), f.endsWith('.glb') ? GLB : PNG);
    }
  }
  const restants = (plante: string) => readdirSync(join(BAC, 'plantes', plante)).sort();

  async function livrerAvec(plante: string, candidats: string[]) {
    await deposer(plante, `/img/${plante}.png`);
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, {
      graine: 7, accepte: true, glb: `/content/x/${plante}.glb`,
      apercus: [`/content/x/apercu_000.png`],
      candidats_pot: candidats.map((v) => ({ voie: v, fichier: `/content/x/sanspot_${v}.glb` })),
    });
  }

  beforeEach(() => reinitialiser());

  it('ne garde que la coupe retenue, et jamais les aperçus', async () => {
    poser('monstera', ['monstera.glb', 'sanspot_geometrie.glb', 'sanspot_couleur.glb',
                       'apercu_000.png', 'apercu_090.png']);
    await livrerAvec('monstera', ['geometrie', 'couleur']);

    await trancher('monstera', 'validee', 'sanspot_geometrie.glb');

    expect(restants('monstera')).toEqual(
      ['apercu_000.png', 'apercu_090.png', 'sanspot_geometrie.glb']);
    const p = lire().plantes.monstera;
    expect(p.purge?.fichiers).toBe(2);
    expect(p.purge?.octets).toBe(2 * GLB.length);
    expect(p.purge?.garde).toBe('sanspot_geometrie.glb');
  });

  /** Validée sans retrait : c'est le maillage complet qui est livrable. */
  it('garde le maillage complet quand aucune coupe n est retenue', async () => {
    poser('cactus', ['cactus.glb', 'apercu_000.png']);
    await livrerAvec('cactus', []);

    await trancher('cactus', 'validee');

    expect(restants('cactus')).toEqual(['apercu_000.png', 'cactus.glb']);
    expect(lire().plantes.cactus.purge?.fichiers).toBe(0);
  });

  it('efface tout à l invalidation : le maillage est rejeté', async () => {
    poser('rate', ['rate.glb', 'sanspot_geometrie.glb', 'apercu_000.png']);
    await livrerAvec('rate', ['geometrie']);

    await trancher('rate', 'invalidee');

    expect(restants('rate')).toEqual(['apercu_000.png']);
    expect(lire().plantes.rate.purge?.fichiers).toBe(2);
  });

  /**
   * LE cas qui compte. Si le nom à conserver ne correspond à aucun fichier,
   * purger quand même effacerait la coupe retenue par-dessus le marché : 180 Mo
   * de GPU perdus sur une erreur de nom. On s'abstient, et on le consigne.
   */
  it('ne purge RIEN si le fichier à conserver est introuvable', async () => {
    poser('prudente', ['prudente.glb', 'sanspot_geometrie.glb', 'apercu_000.png']);
    await livrerAvec('prudente', ['geometrie']);

    await trancher('prudente', 'validee', 'sanspot_inexistant.glb');

    expect(restants('prudente')).toEqual(
      ['apercu_000.png', 'prudente.glb', 'sanspot_geometrie.glb']);
    const p = lire().plantes.prudente;
    expect(p.purge?.fichiers).toBe(0);
    expect(p.purge?.raison).toContain('introuvable');
    // Le verdict, lui, est bien enregistré : une purge empêchée ne doit pas
    // empêcher la seule chose irremplaçable.
    expect(p.verdict).toBe('validee');
  });

  it('refuse un nom de coupe qui tenterait de sortir du dossier', async () => {
    poser('hostile', ['hostile.glb', 'apercu_000.png']);
    await livrerAvec('hostile', []);
    await trancher('hostile', 'validee', '../../etc/passwd');
    // `nomFichier` rejette, on retombe sur le maillage complet, qui est gardé.
    expect(restants('hostile')).toEqual(['apercu_000.png', 'hostile.glb']);
  });

  it('un dossier absent ne fait pas échouer le verdict', async () => {
    await deposer('fantome', '/f.png');
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, { graine: 1, accepte: true });
    await expect(trancher('fantome', 'invalidee')).resolves.toBe('invalidee');
  });

  it('purger ne touche jamais aux aperçus', () => {
    poser('images', ['a.glb', 'b.glb', 'apercu_000.png', 'sanspot_geometrie_000.png']);
    const r = purger('images', []);
    expect(r.supprimes.sort()).toEqual(['a.glb', 'b.glb']);
    expect(restants('images')).toEqual(['apercu_000.png', 'sanspot_geometrie_000.png']);
  });

  it('le bilan cumule la place reprise', async () => {
    poser('p1', ['p1.glb', 'sanspot_geometrie.glb', 'apercu_000.png']);
    await livrerAvec('p1', ['geometrie']);
    await trancher('p1', 'validee', 'sanspot_geometrie.glb');
    expect(bilan().octetsLiberes).toBe(GLB.length);
  });
});

describe('dépôt — images sources', () => {
  /**
   * Elles vivaient sur Drive pendant le spike, et `tache.image` portait un
   * chemin Colab : l'atelier ne pouvait pas déposer de tâche, il aurait écrit
   * un chemin qu'il ne pouvait ni voir ni vérifier. Sur le volume, il le peut.
   */
  const IMG = Buffer.alloc(64, 9);

  function poserSource(fichier: string) {
    mkdirSync(join(BAC, 'sources'), { recursive: true });
    writeFileSync(join(BAC, 'sources', fichier), IMG);
  }

  beforeEach(() => {
    reinitialiser();
    rmSync(join(BAC, 'sources'), { recursive: true, force: true });
  });

  it('accepte les formats d image attendus', () => {
    for (const bon of ['nephrolepis.png', 'Acer_Palmatum.jpg', 'a-b_1.jpeg', 'x.webp']) {
      expect(() => cheminSource(bon), bon).not.toThrow();
    }
  });

  it('refuse tout le reste', () => {
    for (const mauvais of [
      'x.glb', 'x.svg', 'x.json', 'x.php', 'x.png.sh', 'sans_extension',
      '../evade.png', 'a/b.png', 'a\\b.png', '..png', '.png', 'é.png', 'a b.png',
    ]) {
      expect(() => cheminSource(mauvais), mauvais).toThrow();
    }
  });

  it('le nom du fichier porte le nom de la plante', () => {
    expect(planteDe('nephrolepis.png')).toBe('nephrolepis');
    expect(planteDe('Acer_Palmatum.jpg')).toBe('Acer_Palmatum');
  });

  it('liste ce qui est là, trié, en ignorant les intrus', () => {
    poserSource('monstera.png');
    poserSource('acer.jpg');
    writeFileSync(join(BAC, 'sources', 'notes.txt'), 'x');
    const l = sources();
    expect(l.map((s) => s.plante)).toEqual(['acer', 'monstera']);
    expect(l[0].octets).toBe(IMG.length);
  });

  it('rend une liste vide quand le dossier n existe pas', () => {
    expect(sources()).toEqual([]);
  });

  /**
   * Le croisement qui évite de déposer deux fois la même plante. Il se fait
   * ici et pas dans la page : c'est au dépôt de savoir ce qu'il a déjà en vol.
   */
  it('dit ce que l état sait de chaque plante', async () => {
    poserSource('enattente.png');
    poserSource('encours.png');
    poserSource('tranchee.png');
    poserSource('neuve.png');

    // `prendre` sert la plus ANCIENNE : l'ordre de dépôt décide de ce qui part.
    // On traite donc une plante à la fois pour obtenir les quatre états voulus.
    await deposer('tranchee', 'tranchee.png');
    const t = await prendre();
    expect(t!.plante).toBe('tranchee');
    await livrer(t!.id, t!.reservation!, { graine: 1, accepte: true });
    await trancher('tranchee', 'validee');

    await deposer('encours', 'encours.png');
    const u = await prendre();
    expect(u!.plante).toBe('encours');

    await deposer('enattente', 'enattente.png');

    const par = Object.fromEntries(sources().map((s) => [s.plante, s]));
    expect(par.enattente.enFile).toBe(true);
    expect(par.encours.enFile).toBe(true);
    expect(par.neuve.enFile).toBe(false);
    // Tranchée : plus en file, et le verdict est rendu.
    expect(par.tranchee.enFile).toBe(false);
    expect(par.tranchee.verdict).toBe('validee');
  });

  it('supprime une source sans toucher aux artefacts', async () => {
    poserSource('partante.png');
    mkdirSync(join(BAC, 'plantes', 'partante'), { recursive: true });
    writeFileSync(cheminArtefact('partante', 'apercu_000.png'), IMG);

    expect(await supprimerSource('partante.png')).toEqual({ ok: true, tachesRetirees: 0 });
    expect(sources()).toEqual([]);
    // Les artefacts restent : ils sont la trace de ce qui a été jugé.
    expect(readdirSync(join(BAC, 'plantes', 'partante'))).toEqual(['apercu_000.png']);
  });

  /**
   * Les laisser derrière soi n'était pas neutre : l'ouvrier les prenait et
   * échouait sur `image introuvable`, tardivement et par un échec plutôt que
   * par une décision. Constaté sur deux plantes du premier lot.
   */
  it('emporte les tâches en attente de la plante', async () => {
    poserSource('avecfile.png');
    poserSource('autre.png');
    await deposer('avecfile', 'avecfile.png');
    await deposer('avecfile', 'avecfile.png', 'relance');
    await deposer('autre', 'autre.png');

    expect(await supprimerSource('avecfile.png')).toEqual({ ok: true, tachesRetirees: 2 });
    expect(lire().taches.map((t) => t.plante)).toEqual(['autre']);
  });

  /** On ne tire pas le tapis sous les pieds d'un ouvrier qui a engagé le GPU. */
  it('refuse tant qu une tâche est en cours', async () => {
    poserSource('occupee.png');
    await deposer('occupee', 'occupee.png');
    await prendre();

    expect(await supprimerSource('occupee.png'))
      .toEqual({ ok: false, raison: 'tache_en_cours' });
    expect(sources().map((s) => s.plante)).toEqual(['occupee']);
  });

  it('supprimer une source absente ne lève pas', async () => {
    expect(await supprimerSource('fantome.png')).toMatchObject({ ok: false, raison: 'introuvable' });
    expect(await supprimerSource('../evade.png')).toMatchObject({ ok: false });
  });

  it('marque et démarque une source sans pot', async () => {
    poserSource('palmier.png');
    expect(sources()[0].sansPot).toBe(false);
    await marquerSansPot('palmier.png', true);
    expect(sources()[0].sansPot).toBe(true);
    await marquerSansPot('palmier.png', false);
    expect(sources()[0].sansPot).toBe(false);
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

describe('dépôt — empreintes mises en cache', () => {
  beforeEach(() => reinitialiser());

  const residu = { rayons: new Array<number>(24).fill(0.09), profondeur: 0.2 };

  it('rend l empreinte rangée quand la taille du fichier concorde', async () => {
    await noterEmpreinte('ficus', 'sanspot_geometrie.glb',
                         { residu, hauteur: 1, octets: 1234, mesure: 1 });
    const e = empreinteRangee('ficus', 'sanspot_geometrie.glb', 1234);
    expect(e).not.toBeNull();
    expect(e!.hauteur).toBe(1);
  });

  /**
   * La fraîcheur par la TAILLE, et c'est ce qui compte : une régénération sous
   * une autre graine réécrit le GLB sous le même nom. Sans ce contrôle,
   * l'atelier jugerait la plante neuve sur l'empreinte de l'ancienne, et
   * personne ne verrait l'erreur puisque les deux mesures sont plausibles.
   */
  it('ignore l empreinte quand le maillage a changé de taille', async () => {
    await noterEmpreinte('ficus', 'sanspot_geometrie.glb',
                         { residu, hauteur: 1, octets: 1234, mesure: 1 });
    expect(empreinteRangee('ficus', 'sanspot_geometrie.glb', 9999)).toBeNull();
  });

  it('ne confond pas deux coupes d une même plante', async () => {
    await noterEmpreinte('ficus', 'sanspot_geometrie.glb',
                         { residu, hauteur: 1, octets: 10, mesure: 1 });
    await noterEmpreinte('ficus', 'sanspot_couleur.glb',
                         { residu, hauteur: 2, octets: 10, mesure: 1 });
    expect(empreinteRangee('ficus', 'sanspot_geometrie.glb', 10)!.hauteur).toBe(1);
    expect(empreinteRangee('ficus', 'sanspot_couleur.glb', 10)!.hauteur).toBe(2);
    expect(cleEmpreinte('ficus', 'a.glb')).toBe('ficus/a.glb');
  });

  it('rend null quand rien n a été mesuré', () => {
    expect(empreinteRangee('inconnue', 'x.glb', 1)).toBeNull();
  });
});

describe('dépôt — le résidu mesuré par l ouvrier', () => {
  beforeEach(() => reinitialiser());

  const bandes = (v: number) => new Array<number>(24).fill(v);

  async function livrerAvecResidu(plante: string, residu: unknown) {
    await deposer(plante, `/${plante}.png`);
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, {
      graine: 1, accepte: true,
      candidats_pot: [{
        voie: 'geometrie', fichier: '/x/sanspot_geometrie.glb',
        socle: { x: 0, z: 0, y: -0.2, rayon: 0.1, hauteur_modele: 1 },
        residu,
      }],
    });
    return aRevoir()[0].candidats[0];
  }

  it('traverse l API quand il est complet', async () => {
    const c = await livrerAvecResidu('bonne', {
      profondeur: 0.22, hauteur: 0.78, pot: bandes(0), vert: bandes(0.11),
    });
    expect(c.residu).not.toBeNull();
    expect(c.residu!.profondeur).toBe(0.22);
    expect(c.residu!.hauteur).toBe(0.78);
    expect(c.residu!.vert[0]).toBe(0.11);
    expect(posables()[0].residu).not.toBeNull();
  });

  /**
   * Tout ou rien, comme le socle : un profil amputé d'une bande ferait juger la
   * plante sur une mesure trompeuse, ce qui est pire que de ne pas la juger.
   * L'atelier retombe alors sur sa propre mesure.
   */
  it('refuse un résidu incomplet ou absurde', async () => {
    const mauvais: unknown[] = [
      undefined,
      { profondeur: 0.2, hauteur: 0.8, pot: bandes(0) },               // pas de vert
      { profondeur: 0.2, hauteur: 0.8, pot: [0, 0], vert: bandes(0) }, // trop court
      { profondeur: 0.2, hauteur: 0, pot: bandes(0), vert: bandes(0) },// hauteur nulle
      { profondeur: -1, hauteur: 0.8, pot: bandes(0), vert: bandes(0) },
      { profondeur: 0.2, hauteur: 0.8, pot: bandes(-0.1), vert: bandes(0) },
      { profondeur: 0.2, hauteur: 0.8, pot: bandes(Infinity), vert: bandes(0) },
    ];
    for (let i = 0; i < mauvais.length; i += 1) {
      const c = await livrerAvecResidu(`mauvaise_${i}`, mauvais[i]);
      expect(c.residu, `cas ${i}`).toBeNull();
    }
  });
});

describe('dépôt — recoupe d une plante déjà livrée', () => {
  beforeEach(() => reinitialiser());

  const socle = { x: 0, z: 0, y: -0.2, rayon: 0.1, hauteur_modele: 1 };
  const candidat = (voie: string) => ({
    voie, fichier: `/content/x/sanspot_${voie}.glb`, socle,
  });

  async function livrerUne(plante: string) {
    await deposer(plante, `/${plante}.png`);
    const t = await prendre();
    await livrer(t!.id, t!.reservation!, {
      graine: 1, accepte: true, candidats_pot: [candidat('geometrie')],
    });
    return t!.id;
  }

  it('remplace les candidats sans toucher au verdict ni aux graines', async () => {
    const id = await livrerUne('ficus');
    await trancher('ficus', 'validee', 'sanspot_geometrie.glb');

    const r = await recouper(id, [candidat('geometrie'), candidat('couleur')]);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.candidats).toBe(2);
      expect(r.coupePerdue).toBe(false);
    }
    const etat = lire();
    expect(etat.plantes.ficus.verdict).toBe('validee');
    expect(etat.plantes.ficus.coupe).toBe('sanspot_geometrie.glb');
    expect(etat.plantes.ficus.graines).toEqual([1]);
    expect(etat.taches[0].resultat!.candidats_pot).toHaveLength(2);
  });

  /**
   * Les empreintes décrivaient les ANCIENNES coupes. La recoupe réécrit le GLB
   * sous le même nom et peut tomber sur la même taille : on ne parie pas sur un
   * octet de différence, on les retire.
   */
  it('vide les empreintes de la plante, et d elle seule', async () => {
    const id = await livrerUne('ficus');
    await deposer('voisine', '/v.png');
    const residu = { rayons: new Array<number>(24).fill(0.09), profondeur: 0.2 };
    await noterEmpreinte('ficus', 'sanspot_geometrie.glb',
                         { residu, hauteur: 1, octets: 10, mesure: 1 });
    await noterEmpreinte('voisine', 'sanspot_geometrie.glb',
                         { residu, hauteur: 1, octets: 10, mesure: 1 });

    const r = await recouper(id, [candidat('geometrie')]);
    expect(r.ok && r.empreintes).toBe(1);
    expect(empreinteRangee('ficus', 'sanspot_geometrie.glb', 10)).toBeNull();
    expect(empreinteRangee('voisine', 'sanspot_geometrie.glb', 10)).not.toBeNull();
  });

  /**
   * La nouvelle détection retire davantage, et la fenêtre de vraisemblance peut
   * écarter une voie qu'elle acceptait. L'atelier retomberait alors sans bruit
   * sur le premier candidat : mieux vaut que l'ouvrier l'apprenne.
   */
  it('signale quand la coupe retenue ne figure plus parmi les candidats', async () => {
    const id = await livrerUne('ficus');
    await trancher('ficus', 'validee', 'sanspot_geometrie.glb');
    const r = await recouper(id, [candidat('couleur')]);
    expect(r.ok && r.coupePerdue).toBe(true);
  });

  it('refuse une tâche inconnue ou non livrée', async () => {
    expect(await recouper('inexistante', [candidat('geometrie')]))
      .toEqual({ ok: false, raison: 'introuvable' });

    await deposer('en_attente', '/a.png');
    const attente = lire().taches[0];
    expect(await recouper(attente.id, [candidat('geometrie')]))
      .toEqual({ ok: false, raison: 'pas_livree' });

    const t = await prendre();
    expect(await recouper(t!.id, [candidat('geometrie')]))
      .toEqual({ ok: false, raison: 'pas_livree' });
  });

  it('rend la plante posable sur les nouveaux candidats', async () => {
    const id = await livrerUne('ficus');
    await recouper(id, [{
      voie: 'geometrie', fichier: '/content/x/sanspot_geometrie.glb',
      socle: { ...socle, rayon: 0.2 },
    }]);
    expect(posables()[0].socle.rayon).toBe(0.2);
  });
});

/**
 * La liste que lit la passe de recoupe. Elle existe parce que `/taches` retire
 * `resultat` à dessein — et c'est cet oubli qui a fait sauter les 79 plantes
 * au premier essai de la passe, sans qu'aucune erreur ne soit levée.
 */
describe('dépôt — ce qui peut être recoupé', () => {
  beforeEach(() => reinitialiser());

  const socle = { x: 0, z: 0, y: -0.2, rayon: 0.1, hauteur_modele: 1 };

  async function livrer_(plante: string, candidats: unknown[]) {
    await deposer(plante, `/${plante}.png`);
    const t = await prendre();
    await livrer(t!.id, t!.reservation!,
                 { graine: 1, accepte: true, candidats_pot: candidats });
    return t!.id;
  }

  it('rend les noms de fichiers, jamais les chemins du volume', async () => {
    await livrer_('ficus', [{
      voie: 'geometrie', aire_retiree: 0.332, socle,
      fichier: '/content/pipeline/resultats/ficus/sanspot_geometrie.glb',
    }]);
    const r = recoupables();
    expect(r).toHaveLength(1);
    expect(r[0].candidats[0].fichier).toBe('sanspot_geometrie.glb');
    expect(r[0].candidats[0].aireRetiree).toBe(0.332);
    expect(JSON.stringify(r)).not.toContain('/content');
  });

  it('distingue ce qui porte déjà une mesure de résidu', async () => {
    const residu = { profondeur: 0.2, hauteur: 0.8, pot: [], vert: [] };
    await livrer_('neuve', [{ voie: 'geometrie', fichier: '/x/sanspot_geometrie.glb', socle, residu }]);
    await livrer_('ancienne', [{ voie: 'geometrie', fichier: '/x/sanspot_geometrie.glb', socle }]);
    const par = Object.fromEntries(recoupables().map((p) => [p.plante, p.mesure]));
    expect(par).toEqual({ neuve: true, ancienne: false });
  });

  /** Une plante sans fichier n'a rien d'où repartir : il lui faut une régénération. */
  it('écarte ce qui n a aucun maillage coupé', async () => {
    await livrer_('sans_candidat', []);
    await livrer_('sans_fichier', [{ voie: 'geometrie', socle }]);
    expect(recoupables()).toHaveLength(0);
  });

  /** Une coupe validée se reprend : c'est la coupe qui s'améliore, pas le jugement. */
  it('inclut les plantes déjà tranchées', async () => {
    await livrer_('validee', [{ voie: 'geometrie', fichier: '/x/sanspot_geometrie.glb', socle }]);
    await trancher('validee', 'validee', 'sanspot_geometrie.glb');
    await livrer_('ecartee', [{ voie: 'geometrie', fichier: '/x/sanspot_geometrie.glb', socle }]);
    await trancher('ecartee', 'ecartee');
    expect(recoupables().map((p) => p.plante).sort()).toEqual(['ecartee', 'validee']);
  });

  it('ignore ce qui n est pas livré', async () => {
    await deposer('en_attente', '/a.png');
    expect(recoupables()).toHaveLength(0);
    const t = await prendre();
    expect(recoupables()).toHaveLength(0);
    await echouer(t!.id, t!.reservation!, 'cassé');
    expect(recoupables()).toHaveLength(0);
  });
});
