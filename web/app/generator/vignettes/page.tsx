// Vignettes : voir ce que chaque environnement sert, et le refaire.
//
// Les vignettes étaient rendues depuis l'app, plante par plante, par un écran
// d'administration. Rien ne permettait de voir CE QUI EST SERVI sans ouvrir
// l'app elle-même — et le 30 octobre 123 fichiers déposés sans leur marqueur
// de design ont été refusés en silence par l'app, qui a gardé les anciennes
// images. Personne n'avait de quoi s'en apercevoir.
//
// Cet écran répond à deux besoins qui vont ensemble : VOIR ce que sert un
// environnement, et pouvoir le refaire.
import Link from 'next/link';

import { environnements } from '@/lib/generator/config';
import { CLARTE_CIEL_MAX, REGLAGES_VIGNETTE, fileVignettes } from '@/lib/generator/depot';

import Pilote from './Pilote';

export const dynamic = 'force-dynamic';

export default async function Vignettes() {
  const noms = environnements().map((e) => e.nom);

  return (
    <main className="mx-auto max-w-[1400px] px-4 py-6">
      <div className="mb-4 flex items-baseline justify-between gap-3">
        <div>
          <h1 className="text-3xl font-bold text-[#1B1F1A]">Vignettes</h1>
          <p className="text-sm text-[#6E746B]">
            Ce que chaque environnement sert aujourd&apos;hui, et de quoi le refaire.
          </p>
        </div>
        <Link href="/generator" className="text-sm text-[#234632] underline">
          retour à l&apos;atelier
        </Link>
      </div>

      {noms.length === 0 ? (
        <div className="rounded-2xl border border-[#E3C9A8] bg-[#FBF3E8] px-4 py-6 text-sm text-[#8A5A1B]">
          <div className="font-semibold">Aucun environnement déclaré.</div>
          <p className="mt-1 text-[12px]">
            Renseignez <code>VIGNETTES_ENVIRONNEMENTS</code>, de préférence par un
            fichier monté via <code>VIGNETTES_ENVIRONNEMENTS_PATH</code> : une
            variable d&apos;environnement se lit avec <code>docker inspect</code>.
          </p>
        </div>
      ) : (
        <Pilote
          environnements={noms}
          defauts={REGLAGES_VIGNETTE}
          clarteCielMax={CLARTE_CIEL_MAX}
          file={fileVignettes()}
        />
      )}
    </main>
  );
}
