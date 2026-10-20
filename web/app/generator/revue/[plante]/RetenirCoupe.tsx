'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

// La barre d'action d'une plante DÉJÀ validée à qui il manque une coupe.
//
// Elle remplace `Verdict`, et n'en reprend pas les trois boutons : le jugement
// sur le maillage a été rendu, et le rouvrir ici inviterait à invalider une
// plante correcte — 165 s de GPU et une graine brûlée pour corriger une donnée
// qui n'a rien à voir avec le verdict.
//
// Deux issues, donc, et les deux sont des décisions : retenir la coupe
// proposée, ou acter qu'on garde le maillage entier avec son pot d'origine.

type Props = {
  plante: string;
  /** Nom du GLB coupé sélectionné. `null` = garder le maillage entier. */
  coupe: string | null;
  /** Vrai quand plusieurs candidats s'opposent et qu'aucun n'est choisi. */
  choixManquant: boolean;
};

export default function RetenirCoupe({ plante, coupe, choixManquant }: Props) {
  const router = useRouter();
  const [enCours, setEnCours] = useState<'coupe' | 'aucune' | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);

  async function retenir(valeur: string | null) {
    setEnCours(valeur === null ? 'aucune' : 'coupe');
    setErreur(null);
    try {
      const r = await fetch(`/api/generator/revue/${encodeURIComponent(plante)}/coupe`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ coupe: valeur }),
      });
      if (!r.ok) {
        setErreur(`la coupe n'a pas été enregistrée (${r.status})`);
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
          disabled={enCours !== null || choixManquant || coupe === null}
          onClick={() => retenir(coupe)}
          className="flex-1 rounded-xl bg-[#234632] px-4 py-3 font-medium text-white disabled:cursor-not-allowed disabled:bg-[#B5BDB4]"
        >
          {enCours === 'coupe'
            ? 'enregistrement…'
            : choixManquant
              ? 'Choisir une coupe pour la retenir'
              : coupe === null
                ? 'Sélectionne une coupe ci-dessus'
                : 'Retenir cette coupe'}
        </button>

        <button
          type="button"
          disabled={enCours !== null}
          onClick={() => retenir(null)}
          className="flex-1 rounded-xl border border-[#DDD8CF] bg-white px-4 py-3 font-medium text-[#6E746B] disabled:text-[#B5BDB4]"
        >
          {enCours === 'aucune' ? 'enregistrement…' : 'Garder le maillage entier'}
        </button>
      </div>

      <p className="mt-3 text-xs text-[#6E746B]">
        Le verdict reste <strong className="font-medium">validé</strong> dans les
        deux cas : seule la coupe du pot est en question ici.{' '}
        <strong className="font-medium">Garder le maillage entier</strong> acte que
        tu as regardé les candidats et que tu n&apos;en veux aucun — la plante
        conserve son pot d&apos;origine et ne reviendra plus dans cette liste.
        Aucun fichier n&apos;est effacé par ce choix.
      </p>
    </div>
  );
}
