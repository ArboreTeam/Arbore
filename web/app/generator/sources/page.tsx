// Images d'entrée de l'atelier.
//
// C'est la page qui rend le dépôt possible depuis ici. Pendant le spike les
// sources vivaient sur Drive et `tache.image` portait un chemin Colab :
// l'atelier ne pouvait pas déposer, il aurait fabriqué un chemin qu'il ne
// pouvait ni voir ni vérifier.
import Link from 'next/link';

import Sources from './Sources';

export const dynamic = 'force-dynamic';

export default function PageSources() {
  return (
    <main className="min-h-screen bg-[#F0EEEA] px-6 py-10">
      <div className="mx-auto max-w-5xl">
        <Link href="/generator" className="text-sm text-[#6E746B] hover:text-[#234632]">
          ← Atelier
        </Link>
        <h1 className="mt-3 text-3xl font-bold text-[#1B1F1A]">Images d&apos;entrée</h1>
        <p className="mt-1 text-sm text-[#6E746B]">
          Les sources détourées que l&apos;ouvrier transforme en maillage. Une par
          plante, nommée par elle.
        </p>
        <Sources />
      </div>
    </main>
  );
}
