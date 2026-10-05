'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

// Les deux seules décisions de la revue.
//
// Elles passent par `/api/generator/revue/{plante}`, la même route que
// consomme déjà l'ouvrier : une seule porte vers le dépôt, déjà couverte par
// ses tests. Un composant serveur aurait pu écrire en direct, au prix d'un
// second chemin d'écriture à garder cohérent.

type Verdict = 'validee' | 'invalidee' | 'ecartee';

type Props = {
  plante: string;
  /** Nom du GLB coupé retenu. `null` = valider sans retrait de pot. */
  coupe: string | null;
  /** Vrai quand deux candidats s'opposent et qu'aucun n'a encore été choisi. */
  choixManquant: boolean;
};

export default function Verdict({ plante, coupe, choixManquant }: Props) {
  const router = useRouter();
  const [enCours, setEnCours] = useState<Verdict | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);
  const [confirmer, setConfirmer] = useState<'invalidee' | 'ecartee' | null>(null);

  async function trancher(verdict: Verdict) {
    setEnCours(verdict);
    setErreur(null);
    try {
      const r = await fetch(`/api/generator/revue/${encodeURIComponent(plante)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(
          verdict === 'validee' ? { verdict, coupe: coupe ?? undefined } : { verdict },
        ),
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
          onClick={() => trancher('validee')}
          className="flex-1 rounded-xl bg-[#234632] px-4 py-3 font-medium text-white disabled:cursor-not-allowed disabled:bg-[#B5BDB4]"
        >
          {enCours === 'validee'
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
              onClick={() => trancher(confirmer)}
              className="flex-1 rounded-xl bg-[#8A1B1B] px-4 py-3 font-medium text-white disabled:bg-[#B5BDB4]"
            >
              {enCours
                ? 'enregistrement…'
                : confirmer === 'invalidee' ? 'Confirmer : relancer' : 'Confirmer : écarter'}
            </button>
            <button
              type="button"
              onClick={() => setConfirmer(null)}
              className="rounded-xl border border-[#DDD8CF] bg-white px-4 py-3 text-sm text-[#6E746B]"
            >
              Annuler
            </button>
          </div>
        ) : (
          <>
            <button
              type="button"
              disabled={enCours !== null}
              onClick={() => setConfirmer('invalidee')}
              className="flex-1 rounded-xl border border-[#DDD8CF] bg-white px-4 py-3 font-medium text-[#8A1B1B] disabled:text-[#B5BDB4]"
            >
              Invalider et relancer sur une graine neuve
            </button>
            {/*
              Le troisième verdict. Quand le défaut vient de la SOURCE — une
              image dans l'image, une étagère sous le pot qui s'est modélisée —
              relancer ne peut que le reproduire, et sans cette issue la plante
              restait indéfiniment en revue.
            */}
            <button
              type="button"
              disabled={enCours !== null}
              onClick={() => setConfirmer('ecartee')}
              className="rounded-xl border border-[#DDD8CF] bg-white px-4 py-3 text-sm text-[#6E746B] disabled:text-[#B5BDB4]"
            >
              Écarter
            </button>
          </>
        )}
      </div>

      {/*
        L'invalidation demande une confirmation, pas la validation. Elle coûte
        une génération entière — 165 s de GPU — et consomme définitivement la
        graine, qui entre dans l'historique et ne sera jamais rejouée. Une
        validation posée par erreur se corrige en redéposant une tâche.
      */}
      <p className="mt-3 text-xs text-[#6E746B]">
        <strong className="font-medium">Invalider</strong> redépose une tâche sans
        graine imposée : à réserver au défaut de génération, puisque la graine
        refusée reste brûlée.{' '}
        <strong className="font-medium">Écarter</strong> ne redépose pas, et sert
        quand le défaut vient de l&apos;image source — une image dans
        l&apos;image, une étagère modélisée : une graine neuve ne ferait que le
        reproduire. Dans les deux cas les maillages sont effacés et les aperçus
        conservés.
      </p>
    </div>
  );
}
