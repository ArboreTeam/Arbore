'use client';

import { useState } from 'react';

import Visionneuse from '../revue/[plante]/Visionneuse';

// Carte d'une plante de la galerie.
//
// Le client ne sert qu'à deux choses : ouvrir la 3D à la demande, et rendre un
// verdict. Tout le reste est calculé côté serveur — la galerie doit s'afficher
// sans JavaScript utile si le moteur 3D ne se charge jamais.

export type EntreeVue = {
  plante: string;
  verdict: string | null;
  raison: string | null;
  coupe: string | null;
  maillages: Array<{ fichier: string; octets: number; modifie: number | null }>;
  apercus: string[];
  tranchee: number | null;
  coupeEcrite: number | null;
  coupeApresVerdict: boolean;
  graines: number[];
  hauteurCm: number | null;
};

function date(ms: number | null): string {
  if (!ms) return '—';
  return new Date(ms).toLocaleDateString('fr-FR', {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  });
}

const COULEUR: Record<string, string> = {
  validee: 'bg-[#DFEBDE] text-[#234632]',
  invalidee: 'bg-[#F6E2DC] text-[#8A3B22]',
  ecartee: 'bg-[#EFEBE3] text-[#6E746B]',
};

export default function Carte({ e }: { e: EntreeVue }) {
  const [verdict, setVerdict] = useState(e.verdict);
  const [occupe, setOccupe] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  // Le maillage le plus lourd est le maillage complet ; la coupe retenue, si
  // elle existe, est ce qui sera réellement servi. C'est elle qu'on montre.
  const aVoir = e.coupe ?? e.maillages[0]?.fichier ?? null;
  const octets = e.maillages.find((m) => m.fichier === aVoir)?.octets ?? null;

  async function trancher(demande: 'invalidee' | 'ecartee') {
    const mots = demande === 'invalidee'
      ? "Invalider relance une génération sur le GPU et EFFACE le maillage actuel. Continuer ?"
      : "Écarter efface le maillage sans relancer : le défaut vient de la source. Continuer ?";
    if (!window.confirm(`${e.plante}\n\n${mots}`)) return;
    setOccupe(true);
    setErreur(null);
    const r = await fetch(`/api/generator/revue/${encodeURIComponent(e.plante)}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ verdict: demande, raison: 'revue a posteriori depuis la galerie' }),
    }).then((x) => x.json()).catch(() => ({ ok: false }));
    setOccupe(false);
    if (!r?.ok) { setErreur('refus du serveur'); return; }
    setVerdict(demande);
  }

  return (
    <div className="rounded-2xl border border-[#DDD8CF] bg-white p-3">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="truncate text-sm font-semibold text-[#1B1F1A]">{e.plante}</div>
          <div className="text-[11px] text-[#6E746B]">
            {e.hauteurCm ? `${e.hauteurCm} cm · ` : ''}
            {e.graines.length} graine{e.graines.length > 1 ? 's' : ''}
          </div>
        </div>
        <span className={`shrink-0 rounded-full px-2 py-0.5 text-[11px] ${
          COULEUR[verdict ?? ''] ?? 'bg-[#EFEBE3] text-[#6E746B]'}`}
        >
          {verdict ?? 'non tranchée'}
        </span>
      </div>

      {/* Comparaison de DATES, pas de contenus : une recoupe réécrit le
          fichier même quand elle retombe sur la même coupe. Le signal invite à
          regarder, il n'affirme pas que le maillage a changé. */}
      {e.coupeApresVerdict && (
        <div className="mt-2 rounded-xl border border-[#E3C9A8] bg-[#FBF3E8] px-3 py-2 text-[11px] text-[#8A5A1B]">
          <strong>Fichier réécrit après le dernier verdict enregistré.</strong><br />
          verdict le {date(e.tranchee)} · fichier écrit le {date(e.coupeEcrite)}<br />
          Une recoupe réécrit le fichier même si la coupe est identique — à
          regarder, pas forcément à rejuger.
        </div>
      )}

      {e.apercus.length > 0 && (
        <div className="mt-2 grid grid-cols-4 gap-1">
          {e.apercus.slice(0, 4).map((a) => (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              key={a}
              src={`/api/generator/artefacts/${encodeURIComponent(e.plante)}/${encodeURIComponent(a)}`}
              alt={`${e.plante} — ${a}`}
              className="aspect-square w-full rounded-lg bg-[#F6F4EF] object-contain"
              loading="lazy"
            />
          ))}
        </div>
      )}

      {aVoir && (
        <div className="mt-2">
          <Visionneuse
            url={`/api/generator/artefacts/${encodeURIComponent(e.plante)}/${encodeURIComponent(aVoir)}`}
            octets={octets}
          />
        </div>
      )}

      <div className="mt-2 text-[11px] text-[#6E746B]">
        {aVoir ? <>coupe : <code>{aVoir}</code></> : 'aucun maillage sur le volume'}
        {e.maillages.length > 1 && ` · ${e.maillages.length} maillages`}
      </div>

      {e.raison && (
        <div className="mt-1 text-[11px] italic text-[#6E746B]">« {e.raison} »</div>
      )}

      <div className="mt-2 flex gap-2">
        <button
          type="button"
          disabled={occupe || !aVoir}
          onClick={() => void trancher('invalidee')}
          className="flex-1 rounded-xl border border-[#D8BFB4] bg-white px-2 py-1.5 text-[12px] font-medium text-[#8A3B22] disabled:opacity-40"
        >
          Invalider et relancer
        </button>
        <button
          type="button"
          disabled={occupe || !aVoir}
          onClick={() => void trancher('ecartee')}
          className="flex-1 rounded-xl border border-[#DDD8CF] bg-white px-2 py-1.5 text-[12px] font-medium text-[#6E746B] disabled:opacity-40"
        >
          Écarter
        </button>
      </div>
      {erreur && <div className="mt-1 text-[11px] text-[#8A3B22]">{erreur}</div>}
    </div>
  );
}
