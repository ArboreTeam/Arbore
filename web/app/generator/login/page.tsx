'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

// Formulaire de clé de l'atelier.
//
// Aucune indication sur ce qui a échoué au-delà de « clé invalide » : dire
// qu'une clé est « trop courte » ou « mal formée » renseignerait sur ce qu'il
// faut corriger. Le nombre d'essais restants, lui, est affiché — il protège
// l'usage légitime d'un blocage surprise, et n'apprend rien à qui force.
export default function ConnexionAtelier() {
  const router = useRouter();
  const [cle, setCle] = useState('');
  const [enCours, setEnCours] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  async function soumettre(e: React.FormEvent) {
    e.preventDefault();
    setEnCours(true);
    setErreur(null);
    try {
      const r = await fetch('/api/generator/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cle }),
      });
      if (r.ok) {
        setCle('');
        router.replace('/generator');
        router.refresh();
        return;
      }
      const d = await r.json().catch(() => ({}));
      if (r.status === 429) {
        const min = Math.ceil((d.attente ?? 3600) / 60);
        setErreur(`Trop de tentatives. Réessayez dans ${min} minute${min > 1 ? 's' : ''}.`);
      } else if (r.status === 503) {
        setErreur("L'atelier n'est pas configuré. Prévenez l'administrateur.");
      } else {
        const reste = typeof d.restants === 'number' ? d.restants : null;
        setErreur(
          reste === null || reste > 0
            ? `Clé invalide.${reste !== null ? ` ${reste} essai${reste > 1 ? 's' : ''} restant${reste > 1 ? 's' : ''}.` : ''}`
            : 'Clé invalide. Plus aucun essai avant une heure.',
        );
      }
    } catch {
      setErreur('Service injoignable.');
    } finally {
      setEnCours(false);
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#F0EEEA] px-4">
      <form
        onSubmit={soumettre}
        className="w-full max-w-sm rounded-2xl border border-[#DDD8CF] bg-white p-8 shadow-sm"
      >
        <h1 className="text-2xl font-bold text-[#1B1F1A]">Atelier 3D</h1>
        <p className="mt-2 text-sm text-[#6E746B]">
          Génération des modèles de plantes. Accès par clé.
        </p>

        <label htmlFor="cle" className="mt-8 block text-sm font-medium text-[#1B1F1A]">
          Clé d&apos;accès
        </label>
        <input
          id="cle"
          type="password"
          value={cle}
          onChange={(e) => setCle(e.target.value)}
          autoComplete="off"
          autoFocus
          required
          className="mt-2 w-full rounded-xl border border-[#DDD8CF] bg-[#F0EEEA] px-4 py-3 text-[#1B1F1A] outline-none focus:border-[#234632]"
        />

        {erreur && (
          <p role="alert" className="mt-4 rounded-lg bg-[#FBEAEA] px-3 py-2 text-sm text-[#D9534F]">
            {erreur}
          </p>
        )}

        <button
          type="submit"
          disabled={enCours || cle.length === 0}
          className="mt-6 w-full rounded-xl bg-[#234632] py-3 font-semibold text-white disabled:opacity-40"
        >
          {enCours ? 'Vérification…' : 'Entrer'}
        </button>

        <p className="mt-6 text-xs text-[#8A8F87]">
          Trois tentatives par heure. La session dure douze heures.
        </p>
      </form>
    </main>
  );
}
