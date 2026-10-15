'use client';

// Saisie des tailles, plante par plante.
//
// Le pot est une règle graduée : son rayon est mesuré au millième par la
// coupe, et les pots d'horticulture n'ont qu'une poignée de diamètres. Donner
// le diamètre suffit donc à tout déduire. Pour les plantes dont le rebord
// détecté ne ressemble pas à un pot, la hauteur se saisit directement.
import { useCallback, useEffect, useMemo, useState } from 'react';

type Taille = {
  hauteurCm: number; stade: 'jeune' | 'adulte';
  diametrePotCm?: number; pose: number;
};

type Mesurable = {
  plante: string;
  rayon: number | null;
  hauteurModele: number | null;
  sommet: number | null;
  hauteurVegetal: number | null;
  rapportHD: number | null;
  potPlausible: boolean;
  taille: Taille | null;
};

const DIAMETRES = [10, 12, 14, 15, 17, 19, 21, 24, 27, 30];

/**
 * La hauteur du végétal au-dessus de la terre, en centimètres.
 *
 * `hauteurVegetal` est la mesure juste : elle part de la surface du terreau.
 * Tant qu'une passe de coupe ne l'a pas écrite, on retombe sur ce qui dépasse
 * du REBORD, qui est un peu plus haut que la terre — donc une sous-estimation,
 * qu'on signale plutôt que de la maquiller.
 */
function hauteurProposee(m: Mesurable, diametre: number): { cm: number; exacte: boolean } | null {
  if (!m.rayon || !m.hauteurModele) return null;
  const echelle = diametre / (2 * m.rayon);
  if (m.hauteurVegetal) return { cm: m.hauteurVegetal * echelle, exacte: true };
  if (m.sommet === null) return null;
  return { cm: m.hauteurModele * (1 - m.sommet) * echelle, exacte: false };
}

function Ligne({ m, onEnregistre }: { m: Mesurable; onEnregistre: () => void }) {
  const [diametre, setDiametre] = useState<number | ''>(m.taille?.diametrePotCm ?? '');
  const [hauteur, setHauteur] = useState<string>(
    m.taille ? String(m.taille.hauteurCm) : '');
  const [stade, setStade] = useState<'jeune' | 'adulte'>(m.taille?.stade ?? 'adulte');
  const [occupe, setOccupe] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  const propose = typeof diametre === 'number'
    ? hauteurProposee(m, diametre) : null;

  // Choisir un diamètre remplit la hauteur. L'opérateur reste libre de la
  // corriger ensuite : la règle propose, elle ne décide pas.
  const choisirDiametre = (d: number) => {
    setDiametre(d);
    const p = hauteurProposee(m, d);
    if (p) setHauteur(p.cm.toFixed(0));
  };

  const enregistrer = async () => {
    setOccupe(true); setErreur(null);
    const r = await fetch('/api/generator/tailles', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        plante: m.plante,
        taille: { hauteurCm: Number(hauteur), stade,
                  ...(typeof diametre === 'number' ? { diametrePotCm: diametre } : {}) },
      }),
    }).then((x) => x.json()).catch(() => ({ ok: false, raison: 'réseau' }));
    setOccupe(false);
    if (!r.ok) { setErreur(r.raison ?? 'refus'); return; }
    onEnregistre();
  };

  const retirer = async () => {
    setOccupe(true);
    await fetch('/api/generator/tailles', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ plante: m.plante, taille: null }),
    }).catch(() => undefined);
    setOccupe(false); setDiametre(''); setHauteur(''); onEnregistre();
  };

  return (
    <tr className="border-t border-[#DDD8CF] align-top">
      <td className="px-3 py-3">
        <div className="text-sm font-medium text-[#1B1F1A]">{m.plante}</div>
        <div className="mt-0.5 flex items-center gap-2 text-[11px]">
          {m.rapportHD === null ? (
            <span className="text-[#6E746B]">aucun rebord mesuré</span>
          ) : m.potPlausible ? (
            <span className="text-[#6E746B]">
              pot plausible · H/D {m.rapportHD.toFixed(2)}
            </span>
          ) : (
            <span className="rounded-full bg-[#FBE9D0] px-2 py-0.5 text-[#8A5A1B]">
              rebord douteux · H/D {m.rapportHD.toFixed(2)}
            </span>
          )}
        </div>
      </td>
      <td className="px-3 py-3">
        <div className="flex flex-wrap gap-1">
          {DIAMETRES.map((d) => (
            <button
              key={d}
              onClick={() => choisirDiametre(d)}
              disabled={!m.rayon}
              className={`rounded px-1.5 py-0.5 text-[11px] ${
                diametre === d
                  ? 'bg-[#234632] text-white'
                  : 'border border-[#DDD8CF] bg-white text-[#6E746B] hover:border-[#234632] disabled:opacity-40'
              }`}
            >
              {d}
            </button>
          ))}
        </div>
        {propose && (
          <div className="mt-1 text-[11px] text-[#6E746B]">
            propose {propose.cm.toFixed(0)} cm
            {!propose.exacte && ' · depuis le rebord, donc un peu sous-estimée'}
          </div>
        )}
      </td>
      <td className="px-3 py-3">
        <input
          value={hauteur}
          onChange={(e) => setHauteur(e.target.value)}
          inputMode="decimal"
          placeholder="cm"
          className="w-20 rounded border border-[#DDD8CF] px-2 py-1 text-sm"
        />
      </td>
      <td className="px-3 py-3">
        <select
          value={stade}
          onChange={(e) => setStade(e.target.value as 'jeune' | 'adulte')}
          className="rounded border border-[#DDD8CF] bg-white px-2 py-1 text-sm"
        >
          <option value="jeune">jeune</option>
          <option value="adulte">adulte</option>
        </select>
      </td>
      <td className="px-3 py-3">
        <div className="flex items-center gap-2">
          <button
            onClick={enregistrer}
            disabled={occupe || !hauteur}
            className="rounded bg-[#234632] px-2.5 py-1 text-xs text-white disabled:opacity-40"
          >
            {m.taille ? 'Corriger' : 'Poser'}
          </button>
          {m.taille && (
            <button
              onClick={retirer}
              disabled={occupe}
              className="text-xs text-[#6E746B] hover:text-[#8A5A1B]"
            >
              retirer
            </button>
          )}
        </div>
        {erreur && <div className="mt-1 text-[11px] text-[#8A5A1B]">{erreur}</div>}
        {m.taille && !erreur && (
          <div className="mt-1 text-[11px] text-[#234632]">
            {m.taille.hauteurCm} cm · {m.taille.stade}
          </div>
        )}
      </td>
    </tr>
  );
}

export default function Tailles() {
  const [plantes, setPlantes] = useState<Mesurable[] | null>(null);
  const [filtre, setFiltre] = useState<'toutes' | 'sans' | 'douteuses'>('sans');

  const charger = useCallback(() => {
    fetch('/api/generator/tailles')
      .then((r) => r.json())
      .then((d) => setPlantes(d.plantes ?? []))
      .catch(() => setPlantes([]));
  }, []);
  useEffect(charger, [charger]);

  const vues = useMemo(() => {
    if (!plantes) return [];
    if (filtre === 'sans') return plantes.filter((p) => !p.taille);
    if (filtre === 'douteuses') return plantes.filter((p) => !p.potPlausible);
    return plantes;
  }, [plantes, filtre]);

  if (!plantes) return <p className="mt-8 text-sm text-[#6E746B]">chargement…</p>;

  const posees = plantes.filter((p) => p.taille).length;

  return (
    <section className="mt-6">
      <div className="flex flex-wrap items-center gap-3">
        <span className="text-sm text-[#1B1F1A]">
          {posees} sur {plantes.length} attribuées
        </span>
        {(['sans', 'douteuses', 'toutes'] as const).map((f) => (
          <button
            key={f}
            onClick={() => setFiltre(f)}
            className={`rounded-lg px-2.5 py-1 text-xs ${
              filtre === f
                ? 'bg-[#234632] text-white'
                : 'border border-[#DDD8CF] bg-white text-[#6E746B] hover:border-[#234632]'
            }`}
          >
            {f === 'sans' ? 'à faire' : f === 'douteuses' ? 'rebord douteux' : 'toutes'}
          </button>
        ))}
      </div>

      <div className="mt-4 overflow-x-auto rounded-xl border border-[#DDD8CF] bg-white">
        <table className="w-full">
          <thead>
            <tr className="text-left text-[11px] uppercase tracking-wide text-[#6E746B]">
              <th className="px-3 py-2 font-medium">Plante</th>
              <th className="px-3 py-2 font-medium">Diamètre du pot (cm)</th>
              <th className="px-3 py-2 font-medium">Hauteur</th>
              <th className="px-3 py-2 font-medium">Stade</th>
              <th className="px-3 py-2 font-medium" />
            </tr>
          </thead>
          <tbody>
            {vues.map((m) => (
              <Ligne key={m.plante} m={m} onEnregistre={charger} />
            ))}
          </tbody>
        </table>
        {vues.length === 0 && (
          <p className="px-3 py-6 text-sm text-[#6E746B]">rien à montrer ici</p>
        )}
      </div>
    </section>
  );
}
