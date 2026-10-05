// @vitest-environment node
//
// Le contrôle de pose remplace un coup d'œil : s'il se trompe, il cache une
// paire fautive ou condamne une paire saine, et dans les deux cas personne ne
// s'en aperçoit puisque l'écran ne montre plus rien à vérifier. On l'éprouve
// donc sur des maillages construits, dont le profil est connu d'avance.
import { describe, it, expect, afterAll } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { lireMaillage } from './glb';
import { cylindre, ecrireGlb, joindre } from './maillages.essai';
import {
  BANDES, controlerPose, jugerEmpreinte, profilRadial, profilerPlante,
  profilerPot, rayonA, type Empreinte, type Profil,
} from './profil';

const BAC = mkdtempSync(join(tmpdir(), 'profils-'));
afterAll(() => rmSync(BAC, { recursive: true, force: true }));

const glb = (nom: string, m: { s: number[]; f: number[] }) => ecrireGlb(BAC, nom, m.s, m.f);

/** Un profil posé à la main, pour les cas où le maillage n'apporte rien. */
function profil(rayons: number[], profondeur: number): Profil {
  const r = [...rayons];
  while (r.length < BANDES) r.push(r[r.length - 1] ?? 0);
  return { rayons: r.slice(0, BANDES), profondeur };
}

function empreinte(rayons: number[], profondeur: number, hauteur: number): Empreinte {
  return { residu: profil(rayons, profondeur), hauteur };
}

describe('profil radial', () => {
  it('rend le même rayon à toutes les bandes d un cylindre', () => {
    const m = lireMaillage(glb('cyl.glb', cylindre({ r: 0.2, y0: 0, y1: 0.4, etages: 48 })));
    const p = profilRadial(m.positions, 0, 0, 0.4, 0, true);
    expect(p.profondeur).toBeCloseTo(0.4, 5);
    expect(p.rayons).toHaveLength(BANDES);
    for (const r of p.rayons) expect(r).toBeCloseTo(0.2, 3);
  });

  it('suit le galbe d un tronc évasé, du haut vers le bas', () => {
    // 0,10 en bas, 0,20 en haut : la bande 0 est la LÈVRE.
    const m = lireMaillage(glb('evase.glb',
      cylindre({ r: 0.10, rHaut: 0.20, y0: 0, y1: 0.4, etages: 48 })));
    const p = profilRadial(m.positions, 0, 0, 0.4, 0, true);
    expect(p.rayons[0]).toBeGreaterThan(0.19);
    expect(p.rayons[BANDES - 1]).toBeLessThan(0.11);
    for (let i = 1; i < BANDES; i += 1) {
      expect(p.rayons[i]).toBeLessThanOrEqual(p.rayons[i - 1] + 1e-6);
    }
  });

  it('tient compte de l axe', () => {
    const m = lireMaillage(glb('decale.glb',
      cylindre({ r: 0.15, y0: 0, y1: 0.3, cx: 0.4, cz: -0.25, etages: 48 })));
    const bon = profilRadial(m.positions, 0.4, -0.25, 0.3, 0, true);
    const faux = profilRadial(m.positions, 0, 0, 0.3, 0, true);
    for (const r of bon.rayons) expect(r).toBeCloseTo(0.15, 2);
    // Mesuré depuis l'origine, le même cylindre paraît cinq fois plus large.
    expect(faux.rayons[0]).toBeGreaterThan(0.6);
  });

  /**
   * La distinction qui porte tout le contrôle. Une bande vide est un trou de
   * maillage sur un POT, où la paroi continue ; c'est une absence de matière
   * sur un RÉSIDU, où il n'y a rien à cacher.
   */
  it('comble les bandes vides d un pot et laisse celles d un résidu à zéro', () => {
    // Deux anneaux séparés par du vide : le haut et le bas d'un pot éventré.
    const m = lireMaillage(glb('troue.glb', joindre(
      cylindre({ r: 0.2, y0: 0.8, y1: 1.0, etages: 12 }),
      cylindre({ r: 0.2, y0: 0.0, y1: 0.2, etages: 12 }),
    )));
    const comble = profilRadial(m.positions, 0, 0, 1.0, 0, true);
    const brut = profilRadial(m.positions, 0, 0, 1.0, 0, false);
    const milieu = BANDES >> 1;
    expect(comble.rayons[milieu]).toBeCloseTo(0.2, 2);
    expect(brut.rayons[milieu]).toBe(0);
    // Aux extrémités, les deux conviennent du même rayon.
    expect(brut.rayons[0]).toBeCloseTo(0.2, 2);
    expect(brut.rayons[BANDES - 1]).toBeCloseTo(0.2, 2);
  });

  it('rend un profil nul plutôt que de lever sur une épaisseur nulle', () => {
    const p = profilRadial(Float32Array.from([0, 0, 0]), 0, 0, 1, 1, true);
    expect(p.profondeur).toBe(0);
    expect(p.rayons.every((r) => r === 0)).toBe(true);
  });
});

describe('lecture d un profil à une profondeur', () => {
  it('rend la bande au centre de la bande, et borne aux extrémités', () => {
    const p = profil([1, 2, 3], 1);                      // puis 3 jusqu'en bas
    expect(rayonA(p, (0.5 / BANDES) * 1)).toBeCloseTo(1, 6);
    expect(rayonA(p, (1.5 / BANDES) * 1)).toBeCloseTo(2, 6);
    expect(rayonA(p, 0)).toBeCloseTo(1, 6);              // au-dessus de la 1re
    expect(rayonA(p, 10)).toBeCloseTo(3, 6);             // sous la dernière
  });

  it('interpole entre deux centres', () => {
    const p = profil([1, 2], 1);
    expect(rayonA(p, (1.0 / BANDES) * 1)).toBeCloseTo(1.5, 6);
  });

  it('rend zéro sur un profil sans épaisseur', () => {
    expect(rayonA({ rayons: [], profondeur: 0 }, 0.1)).toBe(0);
    expect(rayonA({ rayons: [1, 1], profondeur: 0 }, 0.1)).toBe(0);
  });
});

describe('mesure d un pot et d une plante', () => {
  it('profile un pot de sa lèvre à son fond', () => {
    const chemin = glb('pot.glb', cylindre({ r: 0.06, y0: 0, y1: 0.1, etages: 32 }));
    const p = profilerPot(chemin, { x: 0, z: 0, y: 0.1, hauteur: 0.1 })!;
    expect(p).not.toBeNull();
    expect(p.profondeur).toBeCloseTo(0.1, 5);
    for (const r of p.rayons) expect(r).toBeCloseTo(0.06, 3);
  });

  it('ne mesure que ce qui est SOUS la coupe', () => {
    // Un feuillage large en haut, un résidu étroit en bas, la coupe entre les
    // deux. Mesurer les deux donnerait un résidu aussi large que la plante.
    const chemin = glb('plante.glb', joindre(
      cylindre({ r: 0.40, y0: 0.05, y1: 0.5, etages: 24 }),
      cylindre({ r: 0.09, y0: -0.2, y1: 0.0, etages: 48 }),
    ));
    const e = profilerPlante(chemin, { x: 0, z: 0, y: 0 })!;
    expect(e.hauteur).toBeCloseTo(0.7, 4);
    expect(e.residu.profondeur).toBeCloseTo(0.2, 4);
    for (const r of e.residu.rayons) expect(r).toBeCloseTo(0.09, 2);
  });

  /**
   * La frontière, parce qu'elle décide d'un défaut : ce qui est PILE sur la
   * ligne de coupe compte dans la première bande. C'est le bon côté — la tige
   * traverse la coupe, et l'anneau du rebord s'y trouve exactement — mais il
   * faut l'avoir écrit, sans quoi un ajustement de bande le retournerait sans
   * qu'aucun test ne bronche.
   */
  it('compte la géométrie posée sur la coupe dans la première bande', () => {
    const chemin = glb('frontiere.glb', joindre(
      cylindre({ r: 0.30, y0: 0.0, y1: 0.4, etages: 12 }),
      cylindre({ r: 0.09, y0: -0.2, y1: 0.0, etages: 48 }),
    ));
    const e = profilerPlante(chemin, { x: 0, z: 0, y: 0 })!;
    expect(e.residu.rayons[0]).toBeCloseTo(0.30, 2);
    expect(e.residu.rayons[1]).toBeCloseTo(0.09, 2);
  });

  /**
   * Le piège du format : un GLB coupé garde le tampon de sommets de la plante
   * ENTIÈRE et n'y ajoute qu'une liste de triangles. Mesurer tous les sommets
   * rendrait le pot qu'on vient de retirer.
   */
  it('ignore les sommets qu aucun triangle ne référence', () => {
    const garde = cylindre({ r: 0.09, y0: -0.2, y1: 0, etages: 12 });
    const retire = cylindre({ r: 0.30, y0: -0.5, y1: -0.2, etages: 12 });
    const chemin = ecrireGlb(BAC, 'coupe.glb',
                             [...garde.s, ...retire.s], garde.f);
    const e = profilerPlante(chemin, { x: 0, z: 0, y: 0 })!;
    expect(e.residu.profondeur).toBeCloseTo(0.2, 4);
    for (const r of e.residu.rayons) expect(r).toBeLessThan(0.1);
  });

  it('rend null sur un fichier illisible plutôt que de lever', () => {
    expect(profilerPot(join(BAC, 'absent.glb'), { x: 0, z: 0, y: 1, hauteur: 1 })).toBeNull();
    expect(profilerPlante(join(BAC, 'absent.glb'), { x: 0, z: 0, y: 0 })).toBeNull();
  });
});

describe('jugement d une plante, pot indépendant', () => {
  const socle = { rayon: 0.10 };

  it('ne reproche rien à un résidu qui tient dans l ancien rebord', () => {
    const j = jugerEmpreinte(socle, empreinte([0.08, 0.09, 0.095], 0.2, 1.0));
    expect(j.defauts).toEqual([]);
    expect(j.largeur).toBeCloseTo(0.95, 2);
    expect(j.profondeur).toBeCloseTo(0.2, 2);
  });

  /**
   * Le cas qui décide : le rebord du pot est mis à l'échelle du rayon du socle,
   * donc un résidu plus large que ce rayon dépasse de TOUT pot. Le dire une
   * fois évite de l'essayer cent fois.
   */
  it('condamne un résidu plus large que le rayon du socle', () => {
    const j = jugerEmpreinte(socle, empreinte([0.27, 0.12, 0.10], 0.24, 1.0));
    expect(j.defauts).toContain('residu_large');
    expect(j.largeur).toBeCloseTo(2.7, 2);
  });

  /** La signature mesurée sur 39 paires du premier lot. */
  it('repère le fond isolé : de la matière, du vide, puis de la matière', () => {
    const r = new Array<number>(BANDES).fill(0);
    r[0] = 0.08; r[1] = 0.09;                      // sol sous la coupe
    r[BANDES - 2] = 0.10; r[BANDES - 1] = 0.10;    // fond de l'ancien pot
    const j = jugerEmpreinte(socle, { residu: { rayons: r, profondeur: 0.22 }, hauteur: 1 });
    expect(j.creux).toBe(true);
  });

  /**
   * Un maillage plus grossier que vingt-quatre bandes laisse des bandes vides
   * sans qu'il manque de matière. Les compter comme un creux ferait désigner
   * un défaut inexistant.
   */
  it('ne prend pas une bande vide isolée pour un creux', () => {
    const r = new Array<number>(BANDES).fill(0.09);
    r[5] = 0;
    r[11] = 0; r[12] = 0;
    const j = jugerEmpreinte(socle, { residu: { rayons: r, profondeur: 0.2 }, hauteur: 1 });
    expect(j.vide).toBe(2);
    expect(j.creux).toBe(false);
  });

  it('ne voit pas de creux dans un résidu plein, ni dans un résidu absent', () => {
    expect(jugerEmpreinte(socle, empreinte([0.09], 0.2, 1)).creux).toBe(false);
    const vide = { residu: { rayons: new Array<number>(BANDES).fill(0), profondeur: 0 }, hauteur: 1 };
    const j = jugerEmpreinte(socle, vide);
    expect(j.creux).toBe(false);
    expect(j.defauts).toEqual([]);
    expect(j.largeur).toBe(0);
  });
});

describe('contrôle d une paire', () => {
  const socle = { rayon: 0.10 };
  // Un pot droit assez profond, dans ses propres unités : rayon 0,05 donne une
  // échelle de 2, et 0,15 de hauteur en donnent 0,30 une fois posé.
  const droit = { rayon: 0.05, hauteur: 0.15 };
  const profilDroit = profil(new Array<number>(BANDES).fill(0.05), 0.15);

  it('ne reproche rien à un résidu étroit dans un pot assez profond', () => {
    const p = controlerPose(socle, droit, empreinte([0.08, 0.085, 0.09], 0.25, 1.0), profilDroit);
    expect(p.defauts).toEqual([]);
    expect(p.echelle).toBeCloseTo(2, 4);
    expect(p.debordement).toBe(0);
    expect(p.proportion).toBeCloseTo(0.3, 3);
  });

  it('signale le résidu qui descend sous le fond du pot', () => {
    // Un pot peu profond : 0,05 de haut, soit 0,10 posé, sous un résidu de 0,25.
    const court = { rayon: 0.05, hauteur: 0.05 };
    const p = controlerPose(socle, court, empreinte([0.08], 0.25, 1.0),
                            profil(new Array<number>(BANDES).fill(0.05), 0.05));
    expect(p.defauts).toContain('sous_le_fond');
  });

  /**
   * Deux défauts qu'il ne faut pas confondre : traverser la paroi se corrige en
   * changeant de pot, dépasser par-dessous ne se corrige pas par l'échelle,
   * qu'impose le rayon du rebord.
   */
  it('signale la traversée de paroi dans la hauteur du pot', () => {
    // Un pot qui se resserre vers le bas, sous un résidu de rayon constant.
    const conique = profil(
      Array.from({ length: BANDES }, (_, i) => 0.05 - (0.02 * i) / (BANDES - 1)), 0.15);
    const p = controlerPose(socle, droit, empreinte([0.098], 0.28, 1.0), conique);
    expect(p.defauts).toContain('debordement');
    // Au fond, la paroi est à 0,03 × 2 = 0,06 pour un résidu à 0,098.
    expect(p.debordement).toBeGreaterThan(0.3);
    expect(p.ou).toBeGreaterThan(0.5);
  });

  it('juge la proportion du pot posé', () => {
    const haut = { rayon: 0.05, hauteur: 0.40 };      // 0,80 posé sur 1,0 de plante
    expect(controlerPose(socle, haut, empreinte([0.08], 0.1, 1.0),
                         profil(new Array<number>(BANDES).fill(0.05), 0.40)).defauts)
      .toContain('pot_trop_grand');

    const bas = { rayon: 0.05, hauteur: 0.02 };       // 0,04 posé sur 1,0
    expect(controlerPose(socle, bas, empreinte([], 0, 1.0),
                         profil(new Array<number>(BANDES).fill(0.05), 0.02)).defauts)
      .toContain('pot_trop_petit');
  });

  it('ne divise pas par une hauteur nulle', () => {
    const p = controlerPose(socle, droit, empreinte([], 0, 0), profilDroit);
    expect(p.proportion).toBe(0);
    expect(Number.isFinite(p.debordement)).toBe(true);
  });
});
