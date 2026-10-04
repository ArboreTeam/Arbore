'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';

// Rafraîchissement du tableau de bord pendant qu'un lot tourne.
//
// Sur l'écran de REVUE il n'y en a pas, et c'est délibéré : rien ne doit bouger
// sous les yeux de quelqu'un en train de trancher.
//
// `router.refresh()` et non `location.reload()` : Next ne refait que le rendu
// serveur et réconcilie, donc la position de défilement est gardée et les
// images déjà chargées ne sont pas redemandées.

const PERIODE_MS = 30_000;

export default function Rafraichir() {
  const router = useRouter();
  const [actif, setActif] = useState(true);
  const [dernier, setDernier] = useState<number | null>(null);

  useEffect(() => {
    if (!actif) return;
    const t = setInterval(() => {
      // Onglet en arrière-plan : on ne rafraîchit pas. Quatre heures de lot
      // feraient autrement 480 rendus serveur pour personne.
      if (document.visibilityState !== 'visible') return;
      router.refresh();
      setDernier(Date.now());
    }, PERIODE_MS);
    return () => clearInterval(t);
  }, [actif, router]);

  return (
    <button
      type="button"
      onClick={() => setActif((v) => !v)}
      title={actif ? 'Suspendre le rafraîchissement' : 'Reprendre le rafraîchissement'}
      className="text-xs text-[#6E746B] hover:text-[#234632]"
    >
      {actif ? '⟳ auto' : '⏸ figé'}
      {actif && dernier && (
        <span className="ml-1 text-[#B5BDB4]">
          {new Date(dernier).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
        </span>
      )}
    </button>
  );
}
