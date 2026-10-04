'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

// Les deux seules décisions de la revue.
//
// Elles passent par `/api/generator/revue/{plante}`, la même route que
// consomme déjà l'ouvrier : une seule porte vers le dépôt, déjà couverte par
// ses tests. Un composant serveur aurait pu écrire en direct, au prix d'un
// second chemin d'écriture à garder cohérent.

type Props = {
  plante: string;
  /** Nom du GLB coupé retenu. `null` = valider sans retrait de pot. */
  coupe: string | null;
  /** Vrai quand deux candidats s'opposent et qu'aucun n'a encore été choisi. */
  choixManquant: boolean;
};

export default function Verdict({ plante, coupe, choixManquant }: Props) {
  const router = useRouter();
  const [enCours, setEnCours] = useState<'valider' | 'invalider' | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);
  const [confirmer, setConfirmer] = useState(false);

  async function trancher(valide: boolean) {
    setEnCours(valide ? 'valider' : 'invalider');
    setErreur(null);
    try {
      const r = await fetch(`/api/generator/revue/${encodeURIComponent(plante)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(valide ? { valide: true, coupe: coupe ?? undefined } : { valide: false }),
      });
      if (!r.ok) {
        setErreur(`le verdict n'a pas été enregistré (${r.status})`);
        setEnCours(null);
        return;
      }
      router.push('/generator');
      router.refresh();
    } catch {
      setErreur('réseau indisponible');
      setEnCours(null);
    }
  }

  return (
    <div className="sticky bottom-0 mt-10 border-t border-[#DDD8CF] bg-[#F0EEEA]/95 py-4 backdrop-blur">
      {erreur && (
        <p className="mb-3 rounded-lg bg-[#F8D7D7] px-3 py-2 text-sm text-[#8A1B1B]">{erreur}</p>
      )}

      <div className="flex flex-col gap-3 sm:flex-row">
        <button
          type="button"
          disabled={enCours !== null || choixManquant}
          onClick={() => trancher(true)}
          className="flex-1 rounded-xl bg-[#234632] px-4 py-3 font-medium text-white disabled:cursor-not-allowed disabled:bg-[#B5BDB4]"
        >
          {enCours === 'valider'
            ? 'enregistrement…'
            : choixManquant
              ? 'Choisir une coupe pour valider'
              : coupe
                ? 'Valider avec cette coupe'
                : 'Valider sans retrait de pot'}
        </button>

        {confirmer ? (
          <div className="flex flex-1 gap-2">
            <button
              type="button"
              disabled={enCours !== null}
              onClick={() => trancher(false)}
              className="flex-1 rounded-xl bg-[#8A1B1B] px-4 py-3 font-medium text-white disabled:bg-[#B5BDB4]"
            >
              {enCours === 'invalider' ? 'enregistrement…' : 'Confirmer : relancer'}
            </button>
            <button
              type="button"
              onClick={() => setConfirmer(false)}
              className="rounded-xl border border-[#DDD8CF] bg-white px-4 py-3 text-sm text-[#6E746B]"
            >
              Annuler
            </button>
          </div>
        ) : (
          <button
            type="button"
            disabled={enCours !== null}
            onClick={() => setConfirmer(true)}
            className="flex-1 rounded-xl border border-[#DDD8CF] bg-white px-4 py-3 font-medium text-[#8A1B1B] disabled:text-[#B5BDB4]"
          >
            Invalider — relancer sur une graine neuve
          </button>
        )}
      </div>

      {/*
        L'invalidation demande une confirmation, pas la validation. Elle coûte
        une génération entière — 165 s de GPU — et consomme définitivement la
        graine, qui entre dans l'historique et ne sera jamais rejouée. Une
        validation posée par erreur se corrige en redéposant une tâche.
      */}
      <p className="mt-3 text-xs text-[#6E746B]">
        Invalider redépose une tâche sans graine imposée. La graine refusée reste
        brûlée : elle ne sera pas rejouée.
      </p>
    </div>
  );
}
