// Contrôle de pose de toutes les paires plante/pot.
//
// Essayer à l'œil, c'est charger un maillage de soixante mégaoctets par plante
// et un par pot, puis orbiter. Quarante-huit plantes et dix pots font quatre
// cent quatre-vingts regards. Le contrôle les rend tous d'un coup, et l'écran
// n'a plus qu'à montrer les paires fautives.
//
// Le coût est dans la MESURE des plantes, pas dans le contrôle : une empreinte
// demande de relire le GLB coupé, le contrôle qui s'ensuit est de
// l'arithmétique sur vingt-quatre nombres. Les empreintes sont donc mises en
// cache, et cette route en mesure autant qu'elle peut dans un budget de temps
// avant de rendre ce qu'elle a, en annonçant ce qui reste. L'écran rappelle.
import { statSync } from 'node:fs';
import { NextRequest, NextResponse } from 'next/server';

import {
  cheminArtefact, cheminPot, empreinteRangee, noterEmpreinte, noterPot, posables, pots,
} from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';
import { mesurerRebord } from '@/lib/generator/pot';
import {
  controlerPose, jugerEmpreinte, profilerPlante, profilerPot, SEUILS,
  type Empreinte,
} from '@/lib/generator/profil';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/**
 * Temps accordé aux mesures manquantes par requête.
 *
 * Une empreinte coûte quelques secondes. Tout mesurer d'un trait tiendrait la
 * requête plusieurs minutes, au-delà de ce que les mandataires devant
 * l'application laissent passer, et l'écran n'afficherait rien en attendant.
 */
const BUDGET_MS = 15_000;

export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();

  const debut = Date.now();

  // Les pots d'abord : leur profil est petit et manque seulement à ceux rangés
  // avant le contrôle. Sans lui, aucune paire ne peut être jugée.
  const bibliotheque = [];
  for (const pot of pots()) {
    if (pot.profil) {
      bibliotheque.push(pot);
      continue;
    }
    const chemin = cheminPot(pot.fichier);
    const rebord = mesurerRebord(chemin);
    const profil = rebord ? profilerPot(chemin, rebord) : null;
    if (!profil) continue;
    bibliotheque.push(await noterPot({ ...pot, profil }));
  }

  const plantes = [];
  let restant = 0;

  for (const p of posables()) {
    const chemin = cheminArtefact(p.plante, p.fichier);
    let octets: number;
    try {
      octets = statSync(chemin).size;
    } catch {
      // Le maillage a été purgé : la plante reste posable sur le papier, mais
      // il n'y a plus rien à mesurer.
      continue;
    }

    // Le résidu de l'ouvrier d'abord : il connaît la couleur, donc il sépare
    // un reste de pot d'un feuillage qui retombe — ce que la mesure d'ici ne
    // sait pas faire. Et il évite de relire soixante mégaoctets.
    let empreinte: Empreinte | null = p.residu
      ? { residu: { rayons: p.residu.pot, profondeur: p.residu.profondeur },
          hauteur: p.residu.hauteur }
      : null;
    const livre = empreinte !== null;

    if (!empreinte) empreinte = empreinteRangee(p.plante, p.fichier, octets);
    if (!empreinte) {
      if (Date.now() - debut > BUDGET_MS) {
        restant += 1;
        continue;
      }
      const mesuree = profilerPlante(chemin, p.socle);
      if (!mesuree) continue;
      empreinte = await noterEmpreinte(p.plante, p.fichier, {
        ...mesuree, octets, mesure: Date.now(),
      });
    }

    const jugement = jugerEmpreinte(p.socle, empreinte);
    plantes.push({
      plante: p.plante,
      fichier: p.fichier,
      verdict: p.verdict,
      socle: p.socle,
      hauteur: empreinte.hauteur,
      // L'écran doit pouvoir dire sur quoi il se prononce : un jugement rendu
      // sur la mesure aveugle à la couleur n'a pas la même portée que celui
      // rendu sur le résidu livré, qui exclut le feuillage.
      couleur: livre,
      jugement,
      // Les paires sont contrôlées même quand la plante porte un signal : ce
      // signal ne sait pas distinguer un reste de pot d'un feuillage
      // retombant, et sauter le contrôle priverait d'une réponse les plantes
      // qu'il désigne à tort. Mesuré sur le premier lot, il en désigne 40
      // sur 48 — en sauter 40 ne laisserait rien à l'écran.
      poses: bibliotheque.map((pot) => ({
        pot: pot.fichier,
        ...controlerPose(p.socle, pot, empreinte!, pot.profil!),
      })),
    });
  }

  return NextResponse.json({
    plantes, pots: bibliotheque.map((p) => p.fichier), restant, seuils: SEUILS,
  });
}
