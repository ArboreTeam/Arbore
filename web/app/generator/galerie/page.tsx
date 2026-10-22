// Galerie : tout ce que l'atelier a produit, tranché ou non.
//
// La revue ne montre que ce qui attend un jugement, et rien ne permettait de
// revenir sur une plante déjà tranchée. C'est ainsi qu'un palmier validé le
// 5 octobre a pu être servi avec une coupe réécrite le 15, sans qu'aucun écran
// ne puisse le montrer — 58 coupes réécrites ce jour-là, zéro plante marquée.
//
// Cet écran répond à deux besoins qui vont ensemble : VOIR ce qui existe
// réellement sur le volume, et pouvoir le REJETER après coup.
import Link from 'next/link';

import { galerie } from '@/lib/generator/depot';

import Carte from './Carte';

export const dynamic = 'force-dynamic';

export default async function Galerie() {
  const plantes = galerie();
  const avecMaillage = plantes.filter((p) => p.maillages.length > 0);
  const decalees = plantes.filter((p) => p.coupeApresVerdict);
  const parVerdict = (v: string | null) => plantes.filter((p) => p.verdict === v).length;

  return (
    <main className="mx-auto max-w-[1400px] px-4 py-6">
      <div className="mb-4 flex items-baseline justify-between gap-3">
        <div>
          <h1 className="text-3xl font-bold text-[#1B1F1A]">Galerie</h1>
          <p className="text-sm text-[#6E746B]">
            Tout ce que l&apos;atelier a produit. Un verdict rendu ici remplace
            le précédent.
          </p>
        </div>
        <Link href="/generator" className="text-sm text-[#234632] underline">
          retour à l&apos;atelier
        </Link>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-2 sm:grid-cols-5">
        {[
          ['plantes', String(plantes.length)],
          ['avec maillage', String(avecMaillage.length)],
          ['validées', String(parVerdict('validee'))],
          ['invalidées', String(parVerdict('invalidee'))],
          ['écartées', String(parVerdict('ecartee'))],
        ].map(([libelle, valeur]) => (
          <div key={libelle} className="rounded-xl border border-[#DDD8CF] bg-white px-3 py-2">
            <div className="text-[11px] text-[#6E746B]">{libelle}</div>
            <div className="text-lg font-semibold text-[#1B1F1A]">{valeur}</div>
          </div>
        ))}
      </div>

      {decalees.length > 0 && (
        <div className="mb-4 rounded-2xl border border-[#E3C9A8] bg-[#FBF3E8] px-4 py-3">
          <div className="text-sm font-semibold text-[#8A5A1B]">
            {decalees.length} plante{decalees.length > 1 ? 's' : ''} dont la coupe a été
            réécrite après le verdict
          </div>
          <p className="mt-1 text-[12px] text-[#8A5A1B]">
            Leur verdict porte sur un maillage qui n&apos;est plus sur le volume.
            Elles sont à revoir en priorité, et à ne pas livrer en l&apos;état.
          </p>
          <div className="mt-1 text-[11px] text-[#6E746B]">
            {decalees.map((p) => p.plante).join(' · ')}
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {plantes.map((p) => (
          <Carte key={p.plante} e={p} />
        ))}
      </div>

      {plantes.length === 0 && (
        <div className="rounded-2xl border border-[#DDD8CF] bg-white px-4 py-8 text-center text-sm text-[#6E746B]">
          Aucune plante dans l&apos;atelier.
        </div>
      )}
    </main>
  );
}
