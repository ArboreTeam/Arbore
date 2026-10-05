'use client';

import { useCallback, useEffect, useState } from 'react';

// Le contrôle de pose, à la place du coup d'œil.
//
// La composition étant une similitude déterminée par le socle et le rebord,
// elle se vérifie par le calcul : on compare le profil radial du pot à ce que
// la plante laisse sous sa ligne de coupe. L'écran ne montre donc que les
// paires fautives, et surtout il sépare deux causes qu'un regard confond.
//
// Un RÉSIDU PLUS LARGE que l'ancien rebord ne tient dans aucun pot, puisque le
// rebord de tout pot est mis à l'échelle de ce rayon : c'est la coupe qu'il
// faut reprendre, pas le pot qu'il faut changer. Mesuré sur le premier lot,
// c'est le cas de 40 plantes sur 48 — autant de recherches de pot qui
// n'auraient rien donné.

type Jugement = {
  largeur: number;
  profondeur: number;
  creux: boolean;
  vide: number;
  defauts: string[];
};

type Pose = {
  pot: string;
  echelle: number;
  proportion: number;
  debordement: number;
  ou: number;
  defauts: string[];
};

export type PlanteControlee = {
  plante: string;
  fichier: string;
  verdict?: string;
  hauteur: number;
  jugement: Jugement;
  poses: Pose[];
};

const LIBELLES: Record<string, string> = {
  residu_large: 'résidu plus large que l’ancien rebord',
  debordement: 'le résidu traverse la paroi',
  sous_le_fond: 'le résidu dépasse sous le fond',
  pot_trop_grand: 'pot trop haut pour la plante',
  pot_trop_petit: 'pot trop bas pour la plante',
};

type Props = { onChoisir: (plante: string, pot: string | null) => void };

export default function Controle({ onChoisir }: Props) {
  const [plantes, setPlantes] = useState<PlanteControlee[] | null>(null);
  const [restant, setRestant] = useState(0);
  const [erreur, setErreur] = useState<string | null>(null);
  const [tout, setTout] = useState(false);

  const charger = useCallback(async () => {
    try {
      const r = await fetch('/api/generator/poses');
      if (!r.ok) throw new Error(String(r.status));
      const d = await r.json();
      setPlantes(d.plantes);
      setRestant(d.restant ?? 0);
      setErreur(null);
      return d.restant ?? 0;
    } catch {
      setErreur('contrôle indisponible');
      return 0;
    }
  }, []);

  useEffect(() => {
    void charger();
  }, [charger]);

  // La route mesure ce qu'elle peut dans un budget de temps puis rend la main :
  // on la rappelle tant qu'il reste des empreintes à prendre, plutôt que de
  // tenir une requête de plusieurs minutes devant un écran vide.
  useEffect(() => {
    if (restant <= 0) return;
    const t = setTimeout(() => void charger(), 300);
    return () => clearTimeout(t);
  }, [restant, charger]);

  if (erreur) {
    return <p className="mt-6 text-sm text-[#8A1B1B]">{erreur}</p>;
  }
  if (plantes === null) {
    return <p className="mt-6 text-sm text-[#6E746B]">contrôle en cours…</p>;
  }

  const condamnees = plantes.filter((p) => p.jugement.defauts.length > 0);
  const jugeables = plantes.filter((p) => p.jugement.defauts.length === 0);
  const fautives = jugeables
    .map((p) => ({ p, mauvaises: p.poses.filter((x) => x.defauts.length > 0) }))
    .filter((x) => x.mauvaises.length > 0);
  const saines = jugeables.reduce(
    (n, p) => n + p.poses.filter((x) => x.defauts.length === 0).length, 0);

  return (
    <section className="mt-8 rounded-2xl border border-[#DDD8CF] bg-white p-6">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-semibold text-[#1B1F1A]">Contrôle de pose</h2>
        <span className="text-xs text-[#6E746B]">
          {restant > 0
            ? `mesure en cours · ${restant} plante(s) à lire`
            : `${plantes.length} plante(s) contrôlée(s) · ${saines} paire(s) saine(s)`}
        </span>
      </div>
      <p className="mt-1 text-xs text-[#6E746B]">
        Vérifié par le calcul, pas à l&apos;œil : le profil radial du pot contre
        ce que la plante laisse sous sa coupe. Seules les paires fautives sont
        listées.
      </p>

      {condamnees.length > 0 && (
        <div className="mt-5">
          <h3 className="text-sm font-medium text-[#8A1B1B]">
            {condamnees.length} plante(s) qu&apos;aucun pot ne peut habiller
          </h3>
          <p className="mt-1 text-xs text-[#6E746B]">
            Leur résidu est plus large que leur ancien rebord. Comme tout pot est
            mis à l&apos;échelle de ce rayon, il dépasserait de n&apos;importe
            lequel : c&apos;est la coupe qu&apos;il faut reprendre.
          </p>
          <ul className="mt-2 divide-y divide-[#DDD8CF] rounded-xl border border-[#DDD8CF]">
            {condamnees.map((p) => (
              <li key={p.plante} className="flex items-center gap-3 px-3 py-2">
                <button
                  type="button"
                  onClick={() => onChoisir(p.plante, null)}
                  className="flex-1 text-left text-sm text-[#1B1F1A] hover:text-[#234632]"
                >
                  {p.plante}
                </button>
                <span className="text-xs text-[#6E746B]">
                  résidu ×{p.jugement.largeur.toFixed(2)} du rebord
                  {p.jugement.creux ? ` · fond isolé sur ${p.jugement.vide} bandes` : ''}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {fautives.length > 0 && (
        <div className="mt-5">
          <h3 className="text-sm font-medium text-[#8A5A1B]">
            {fautives.reduce((n, x) => n + x.mauvaises.length, 0)} paire(s) fautive(s)
          </h3>
          <ul className="mt-2 space-y-2">
            {fautives.map(({ p, mauvaises }) => (
              <li key={p.plante} className="rounded-xl border border-[#DDD8CF] px-3 py-2">
                <div className="text-sm font-medium text-[#1B1F1A]">{p.plante}</div>
                <ul className="mt-1 space-y-1">
                  {mauvaises.map((x) => (
                    <li key={x.pot} className="flex flex-wrap items-center gap-2 text-xs">
                      <button
                        type="button"
                        onClick={() => onChoisir(p.plante, x.pot)}
                        title="Le regarder dans la visionneuse"
                        className="rounded-lg border border-[#DDD8CF] px-2 py-0.5 text-[#1B1F1A] hover:border-[#234632]"
                      >
                        {x.pot.replace(/\.glb$/, '')}
                      </button>
                      <span className="text-[#8A5A1B]">
                        {x.defauts.map((d) => LIBELLES[d] ?? d).join(', ')}
                      </span>
                      {x.defauts.includes('debordement') && (
                        <span className="text-[#6E746B]">
                          de {(x.debordement * 100).toFixed(0)} % du rayon, à{' '}
                          {(x.ou * 100).toFixed(0)} % de la hauteur
                        </span>
                      )}
                    </li>
                  ))}
                </ul>
              </li>
            ))}
          </ul>
        </div>
      )}

      {condamnees.length === 0 && fautives.length === 0 && restant === 0 && (
        <p className="mt-4 rounded-xl border border-dashed border-[#DDD8CF] bg-[#F7F6F3] px-4 py-6 text-center text-sm text-[#234632]">
          Aucune paire fautive. Rien à vérifier à l&apos;œil.
        </p>
      )}

      {saines > 0 && (
        <div className="mt-5">
          <button
            type="button"
            onClick={() => setTout(!tout)}
            className="text-xs text-[#6E746B] underline hover:text-[#234632]"
          >
            {tout ? 'masquer' : `voir les ${saines} paire(s) saine(s)`}
          </button>
          {tout && (
            <ul className="mt-2 space-y-1">
              {jugeables.map((p) => p.poses
                .filter((x) => x.defauts.length === 0)
                .map((x) => (
                  <li key={`${p.plante}/${x.pot}`} className="text-xs text-[#6E746B]">
                    <button
                      type="button"
                      onClick={() => onChoisir(p.plante, x.pot)}
                      className="text-[#1B1F1A] hover:text-[#234632]"
                    >
                      {p.plante} · {x.pot.replace(/\.glb$/, '')}
                    </button>
                    {' '}— échelle ×{x.echelle.toFixed(2)}, pot à{' '}
                    {(x.proportion * 100).toFixed(0)} % de la hauteur
                  </li>
                )))}
            </ul>
          )}
        </div>
      )}
    </section>
  );
}
