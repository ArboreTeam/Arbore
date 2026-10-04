'use client';

import { useState } from 'react';

import Verdict from './Verdict';
import Visionneuse from './Visionneuse';

// Le choix de la coupe du pot, et le verdict.
//
// Deux tiers des plantes arrivent avec un seul candidat : la signature de
// paroi est nette et la géométrie a tranché seule. Il est présélectionné, et
// la revue se réduit alors à un oui ou un non.
//
// Le tiers restant arrive avec deux candidats que rien ne départage — 62 %
// contre 58 % de confiance, trop proches pour qu'un seuil décide. C'est là que
// cet écran gagne sa place : l'œil tranche en un clic.

export type CandidatVu = {
  voie: string;
  aireRetiree: number | null;
  confianceParoi: number | null;
  sommet: number | null;
  fichier: string | null;
  apercus: string[];
  octets: number | null;
};

type Props = { plante: string; candidats: CandidatVu[] };

const LIBELLE: Record<string, string> = {
  geometrie: 'Géométrie',
  couleur: 'Couleur',
};

const EXPLICATION: Record<string, string> = {
  geometrie:
    'Paroi de révolution : normales horizontales et radiales, rayon régulier. Aveugle à un pot froissé, qui n’est plus une révolution.',
  couleur:
    'Un pot n’est pas vert. Voit le pot froissé, mais avale les parties non vertes de la plante : caudex beige, pétioles magenta.',
};

function pourcent(v: number | null): string {
  return v === null ? '—' : `${(v * 100).toFixed(1)} %`;
}

export default function Arbitrage({ plante, candidats }: Props) {
  // Présélection quand il n'y a rien à arbitrer : un seul candidat n'est pas
  // une question. Avec deux, aucun n'est choisi d'avance — proposer un défaut
  // reviendrait à répondre à la place de l'opérateur, sur l'écart même que la
  // machine n'a pas su trancher.
  const [choisi, setChoisi] = useState<number | null>(candidats.length === 1 ? 0 : null);

  const retenu = choisi === null ? null : candidats[choisi];

  return (
    <>
      <section className="mt-10">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-[#1B1F1A]">Retrait du pot</h2>
          {candidats.length > 1 && (
            <span className="text-xs text-[#8A5A1B]">
              deux candidats, à toi de trancher
            </span>
          )}
        </div>

        {candidats.length === 0 ? (
          <p className="mt-3 rounded-2xl border border-dashed border-[#DDD8CF] bg-white/60 px-6 py-8 text-center text-sm text-[#6E746B]">
            Aucun retrait plausible proposé. Soit la plante n&apos;a pas de pot
            détectable, soit les deux voies sortaient des bornes de
            vraisemblance : on ne propose pas une coupe invraisemblable.
          </p>
        ) : (
          <div className={`mt-3 grid items-start gap-4 ${candidats.length > 1 ? 'lg:grid-cols-2' : ''}`}>
            {candidats.map((c, i) => {
              const actif = choisi === i;
              return (
                <div
                  key={c.voie}
                  className={`rounded-2xl border bg-white p-4 transition ${
                    actif ? 'border-[#234632] ring-1 ring-[#234632]' : 'border-[#DDD8CF]'
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <h3 className="font-medium text-[#1B1F1A]">
                      {LIBELLE[c.voie] ?? c.voie}
                    </h3>
                    <span className="text-xs text-[#6E746B]">
                      retire {pourcent(c.aireRetiree)} de l&apos;aire
                    </span>
                  </div>

                  <p className="mt-1 text-xs leading-relaxed text-[#6E746B]">
                    {EXPLICATION[c.voie] ?? ''}
                  </p>

                  {c.apercus.length > 0 ? (
                    <div className="mt-3 grid grid-cols-2 gap-2">
                      {c.apercus.map((a) => (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          key={a}
                          src={`/api/generator/artefacts/${plante}/${a}`}
                          alt={`${plante} sans pot, voie ${c.voie}`}
                          className="aspect-square w-full rounded-lg bg-[#F7F6F3] object-contain"
                        />
                      ))}
                    </div>
                  ) : (
                    <p className="mt-3 rounded-lg bg-[#F7F6F3] px-3 py-4 text-center text-xs text-[#6E746B]">
                      Aucun aperçu rendu pour ce candidat. Les générations
                      antérieures au rendu des coupes n&apos;en ont pas, et la 3D
                      ci-dessous reste alors le seul regard possible.
                    </p>
                  )}

                  <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
                    <dt className="text-[#6E746B]">confiance paroi</dt>
                    <dd className="text-right text-[#1B1F1A]">{pourcent(c.confianceParoi)}</dd>
                    <dt className="text-[#6E746B]">hauteur de coupe</dt>
                    <dd className="text-right text-[#1B1F1A]">
                      {c.sommet === null ? '—' : c.sommet.toFixed(3)}
                    </dd>
                  </dl>

                  {c.fichier && (
                    <Visionneuse
                      url={`/api/generator/artefacts/${plante}/${c.fichier}`}
                      octets={c.octets}
                    />
                  )}

                  <button
                    type="button"
                    onClick={() => setChoisi(i)}
                    disabled={actif}
                    className={`mt-3 w-full rounded-lg px-3 py-2 text-sm font-medium ${
                      actif
                        ? 'bg-[#E7EDE6] text-[#234632]'
                        : 'border border-[#DDD8CF] text-[#1B1F1A] hover:border-[#234632]'
                    }`}
                  >
                    {actif ? 'Coupe retenue' : 'Retenir cette coupe'}
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </section>

      <Verdict
        plante={plante}
        coupe={retenu?.fichier ?? null}
        choixManquant={candidats.length > 0 && retenu === null}
      />
    </>
  );
}
