// Attribution de la taille réelle des plantes.
//
// Une plante n'est pas redimensionnable dans l'application : elle a la taille
// qu'elle a. Cet écran est l'endroit où on la lui donne, une fois pour toutes.
import Link from 'next/link';

import Tailles from './Tailles';

export const dynamic = 'force-dynamic';

export default function PageTailles() {
  return (
    <main className="min-h-screen bg-[#F0EEEA] px-6 py-10">
      <div className="mx-auto max-w-6xl">
        <Link href="/generator" className="text-sm text-[#6E746B] hover:text-[#234632]">
          ← Atelier
        </Link>
        <h1 className="mt-3 text-3xl font-bold text-[#1B1F1A]">Tailles</h1>
        <p className="mt-1 text-sm text-[#6E746B]">
          Le pot sert de règle : donne son diamètre, la hauteur se calcule.
          Elle est mesurée depuis la terre, pas depuis le bas du pot.
        </p>
        <Tailles />
      </div>
    </main>
  );
}
