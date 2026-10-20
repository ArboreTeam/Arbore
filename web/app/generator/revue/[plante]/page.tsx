// Revue d'une plante.
//
// Deux questions, et elles n'ont pas la même nature. La première — le maillage
// est-il bon ? — ne se mesure pas : le portillon attrape les composantes
// détachées et les dalles, mais une géométrie inventée et plausible passe tous
// les seuils. Seul un œil la voit. La seconde — quelle coupe du pot ? — a été
// tranchée par la machine deux fois sur trois ; le tiers restant arrive ici.
import Link from 'next/link';
import { notFound } from 'next/navigation';

import { aRevoir, coupeNonRetenue, tailleArtefact } from '@/lib/generator/depot';

import Arbitrage, { type CandidatVu } from './Arbitrage';

export const dynamic = 'force-dynamic';

function Mesure({
  libelle, valeur, detail, alerte,
}: { libelle: string; valeur: string; detail?: string; alerte?: boolean }) {
  return (
    <div className="rounded-xl border border-[#DDD8CF] bg-white px-3 py-2">
      <div className="text-[11px] text-[#6E746B]">{libelle}</div>
      <div className={`text-sm font-medium ${alerte ? 'text-[#8A5A1B]' : 'text-[#1B1F1A]'}`}>
        {valeur}
      </div>
      {detail && <div className="text-[11px] text-[#6E746B]">{detail}</div>}
    </div>
  );
}

export default async function RevuePlante({ params }: { params: Promise<{ plante: string }> }) {
  const { plante } = await params;
  const vue = aRevoir().find((p) => p.plante === plante);

  // Validée sans qu'aucune coupe ait été retenue, alors qu'un candidat existe
  // encore. `aRevoir` l'écarte — elle est jugée — et l'écran répondait donc 404
  // sans qu'aucun chemin ne permette de nommer la coupe après coup.
  const sansCoupe = vue ? undefined : coupeNonRetenue().find((p) => p.plante === plante);
  const sujet = vue ?? sansCoupe;

  // Déjà tranchée de part en part, ou jamais livrée : dans les deux cas il n'y
  // a rien à revoir. Un 404 plutôt qu'un écran vide — revenir en arrière après
  // un verdict ne doit pas donner l'impression qu'on peut le reprendre.
  if (!sujet) notFound();

  const candidats: CandidatVu[] = sujet.candidats.map((c) => ({
    voie: c.voie,
    aireRetiree: c.aireRetiree,
    confianceParoi: c.confianceParoi,
    sommet: c.sommet,
    fichier: c.fichier,
    apercus: c.apercus,
    octets: c.fichier ? tailleArtefact(plante, c.fichier) : null,
  }));

  return (
    <main className="min-h-screen bg-[#F0EEEA] px-6 py-10">
      <div className="mx-auto max-w-5xl">
        <Link href="/generator" className="text-sm text-[#6E746B] hover:text-[#234632]">
          ← Atelier
        </Link>

        <header className="mt-3 flex flex-wrap items-baseline justify-between gap-2">
          <h1 className="text-3xl font-bold text-[#1B1F1A]">{sujet.plante}</h1>
          <div className="text-sm text-[#6E746B]">
            graine {sujet.graine ?? '—'}
            {sujet.essai && sujet.essai > 1 ? ` · essai ${sujet.essai}` : ''}
            {sujet.secondes ? ` · ${sujet.secondes.toFixed(0)} s` : ''}
          </div>
        </header>

        {sansCoupe && (
          <p className="mt-4 rounded-xl bg-[#E4EAF4] px-4 py-3 text-sm text-[#2F4B7C]">
            Cette plante est <strong className="font-medium">déjà validée</strong> :
            le maillage a été jugé bon, et le verdict n&apos;est pas remis en
            question ici. Il lui manque seulement une coupe du pot, alors
            qu&apos;un candidat est toujours sur le volume.
          </p>
        )}

        {!sujet.accepte && (
          <p className="mt-4 rounded-xl bg-[#FBE9D0] px-4 py-3 text-sm text-[#8A5A1B]">
            Le portillon a rejeté toutes les tentatives. Ce maillage est le
            dernier essai, livré faute de mieux : il porte probablement le
            défaut que les mesures ci-dessous signalent.
          </p>
        )}

        <section className="mt-6 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
          <Mesure
            libelle="composante dominante"
            valeur={sujet.dominante === null ? '—' : `${(sujet.dominante * 100).toFixed(1)} %`}
            detail="100 % = d'un seul tenant"
          />
          <Mesure
            libelle="grosses composantes"
            valeur={sujet.grosses === null ? '—' : String(sujet.grosses)}
            detail="au-delà de 1 : morceau détaché"
            alerte={(sujet.grosses ?? 0) > 1}
          />
          <Mesure
            libelle="aire dans 3 plans"
            valeur={sujet.plans === null ? '—' : `${(sujet.plans * 100).toFixed(1)} %`}
            detail="élevé = cube ou dalle"
            alerte={(sujet.plans ?? 0) > 0.2}
          />
          <Mesure
            libelle="triangles"
            valeur={sujet.triangles === null ? '—' : sujet.triangles.toLocaleString('fr-FR')}
          />
          <Mesure
            libelle="poids"
            valeur={sujet.octets === null ? '—' : `${(sujet.octets / 1e6).toFixed(0)} Mo`}
          />
        </section>

        <section className="mt-8">
          <h2 className="font-semibold text-[#1B1F1A]">Maillage complet</h2>
          <p className="mt-1 text-xs text-[#6E746B]">
            Quatre azimuts. Ce qu&apos;aucune mesure ne voit : une feuille
            inventée, une tige qui part de nulle part, une symétrie trop propre.
          </p>
          {sujet.apercus.length === 0 ? (
            <p className="mt-3 rounded-2xl border border-dashed border-[#DDD8CF] bg-white/60 px-6 py-10 text-center text-sm text-[#6E746B]">
              Aucun aperçu livré pour cette plante.
            </p>
          ) : (
            <div className="mt-3 grid grid-cols-2 gap-3 lg:grid-cols-4">
              {sujet.apercus.map((a) => (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  key={a}
                  src={`/api/generator/artefacts/${plante}/${a}`}
                  alt={`${plante}, ${a.replace(/\D+/g, '')}°`}
                  className="aspect-square w-full rounded-xl border border-[#DDD8CF] bg-white object-contain"
                />
              ))}
            </div>
          )}
        </section>

        <Arbitrage plante={plante} candidats={candidats} dejaValidee={sansCoupe !== undefined} />
      </div>
    </main>
  );
}
