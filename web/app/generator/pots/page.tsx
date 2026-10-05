// Bibliothèque de pots et essayage.
//
// Les pots ne viennent pas des plantes générées : ceux-là sont des
// sous-produits de la coupe. Ceux-ci sont sourcés ou générés à part, et tout
// l'objet de l'écran est de pouvoir choisir lequel va sous quelle plante.
import Link from 'next/link';

import Bibliotheque from './Bibliotheque';

export const dynamic = 'force-dynamic';

export default function PagePots() {
  return (
    <main className="min-h-screen bg-[#F0EEEA] px-6 py-10">
      <div className="mx-auto max-w-6xl">
        <Link href="/generator" className="text-sm text-[#6E746B] hover:text-[#234632]">
          ← Atelier
        </Link>
        <h1 className="mt-3 text-3xl font-bold text-[#1B1F1A]">Pots</h1>
        <p className="mt-1 text-sm text-[#6E746B]">
          Déposer des pots, et les essayer sous une plante dont le pot a été retiré.
        </p>
        <Bibliotheque />
      </div>
    </main>
  );
}
