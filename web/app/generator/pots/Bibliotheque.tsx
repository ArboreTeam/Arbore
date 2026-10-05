'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

import Essayage, { type Plante, type Pot } from './Essayage';

// La bibliothèque de pots, et l'essayage.
//
// Un seul contexte WebGL pour tout l'écran : une vignette 3D par pot serait
// plus jolie, mais les navigateurs en plafonnent le nombre autour de seize et
// une bibliothèque de cent pots les épuiserait. On liste donc les pots par
// leurs mesures, et on en regarde un à la fois.

const MORCEAU = 8 * 1024 * 1024;

function poids(o: number): string {
  return o < 1e6 ? `${Math.round(o / 1e3)} Ko` : `${(o / 1e6).toFixed(1)} Mo`;
}

/** Le serveur n'accepte que `[a-z0-9_-].glb`. On montre la correction. */
function nomDePot(fichier: string): string {
  const base = fichier
    .replace(/\.[^.]+$/, '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 64);
  return `${base || 'pot'}.glb`;
}

export default function Bibliotheque() {
  const [pots, setPots] = useState<Pot[] | null>(null);
  const [plantes, setPlantes] = useState<Plante[]>([]);
  const [potChoisi, setPotChoisi] = useState<Pot | null>(null);
  const [planteChoisie, setPlanteChoisie] = useState<Plante | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);
  const [envoi, setEnvoi] = useState<string | null>(null);
  const champ = useRef<HTMLInputElement>(null);

  /**
   * Remplace une liste SEULEMENT si son contenu a changé.
   *
   * Sans ce contrôle, chaque rafraîchissement rendrait des objets neufs, la
   * sélection changerait d'identité, et la visionneuse rechargerait un GLB de
   * cinquante mégaoctets sous les yeux de qui est en train de le regarder.
   */
  function remplacerSiChange<T>(ancien: T[] | null, neuf: T[]): T[] {
    return ancien && JSON.stringify(ancien) === JSON.stringify(neuf) ? ancien : neuf;
  }

  const recharger = useCallback(async () => {
    try {
      const [p, q] = await Promise.all([
        fetch('/api/generator/pots').then((r) => r.json()),
        fetch('/api/generator/plantes').then((r) => r.json()),
      ]);
      setPots((v) => remplacerSiChange(v, p.pots ?? []));
      setPlantes((v) => remplacerSiChange(v, q.plantes ?? []));
      setErreur(null);
    } catch {
      setErreur('liste indisponible');
    }
  }, []);

  useEffect(() => {
    void recharger();
    // Les plantes arrivent au fil des validations, et les lots durent des
    // heures : recharger à la main pour voir la liste grandir décourage de
    // s'en servir. Rien ne part quand l'onglet est en arrière-plan.
    const t = setInterval(() => {
      if (document.visibilityState === 'visible') void recharger();
    }, 30_000);
    return () => clearInterval(t);
  }, [recharger]);

  async function televerser(fichier: File) {
    const nom = nomDePot(fichier.name);
    setErreur(null);
    for (let position = 0; position < Math.max(fichier.size, 1); position += MORCEAU) {
      const dernier = position + MORCEAU >= fichier.size;
      setEnvoi(`${nom} · ${Math.round((position / Math.max(fichier.size, 1)) * 100)} %`);
      const r = await fetch(
        `/api/generator/pots/${encodeURIComponent(nom)}?position=${position}${dernier ? '&final=1' : ''}`,
        { method: 'PUT', body: fichier.slice(position, position + MORCEAU) },
      );
      if (!r.ok) {
        // 422 : le maillage ne ressemble pas à un pot. Le serveur l'a refusé
        // AVANT de le ranger, et n'en a rien gardé.
        const d = await r.json().catch(() => ({}));
        setErreur(`${nom} : ${d.error ?? `refusé (${r.status})`}`);
        setEnvoi(null);
        return;
      }
      if (dernier) break;
    }
    setEnvoi(null);
    await recharger();
  }

  // La sélection suit le contenu, pas l'identité : si la liste est remplacée,
  // on retrouve le même pot et la même plante par leur nom plutôt que de
  // perdre ce qui est affiché.
  useEffect(() => {
    if (potChoisi && pots) {
      const a = pots.find((x) => x.fichier === potChoisi.fichier);
      if (!a) setPotChoisi(null);
      else if (a !== potChoisi) setPotChoisi(a);
    }
  }, [pots, potChoisi]);

  useEffect(() => {
    if (planteChoisie) {
      const a = plantes.find((x) => x.plante === planteChoisie.plante);
      if (!a) setPlanteChoisie(null);
      else if (a !== planteChoisie) setPlanteChoisie(a);
    }
  }, [plantes, planteChoisie]);

  async function supprimer(p: Pot) {
    await fetch(`/api/generator/pots/${encodeURIComponent(p.fichier)}`, { method: 'DELETE' });
    if (potChoisi?.fichier === p.fichier) setPotChoisi(null);
    await recharger();
  }

  return (
    <>
      <section className="mt-8 rounded-2xl border border-dashed border-[#DDD8CF] bg-white/60 p-6">
        <label className="inline-flex cursor-pointer items-center rounded-lg bg-[#234632] px-4 py-2 text-sm font-medium text-white">
          Déposer des pots
          <input
            ref={champ}
            type="file"
            accept=".glb,model/gltf-binary"
            multiple
            onChange={async (e) => {
              for (const f of Array.from(e.target.files ?? [])) await televerser(f);
              if (champ.current) champ.current.value = '';
            }}
            className="sr-only"
          />
        </label>
        <p className="mt-2 text-xs text-[#6E746B]">
          Des GLB. Le rebord est mesuré au dépôt — hauteur, rayon, axe — et c&apos;est
          lui qui permet de poser le pot sous n&apos;importe quelle plante. Un maillage
          dont le rebord n&apos;est pas mesurable est refusé sur-le-champ, pas rangé
          pour être découvert inutilisable plus tard.
        </p>
        {envoi && <p className="mt-2 text-xs text-[#234632]">{envoi}</p>}
      </section>

      {erreur && (
        <p className="mt-4 rounded-lg bg-[#F8D7D7] px-3 py-2 text-sm text-[#8A1B1B]">{erreur}</p>
      )}

      <section className="mt-8 grid gap-6 lg:grid-cols-[1fr_380px]">
        <div>
          <h2 className="font-semibold text-[#1B1F1A]">Essayage</h2>
          <p className="mt-1 text-xs text-[#6E746B]">
            Le pot est mis à l&apos;échelle sur le rayon du socle et sa lèvre posée à
            la hauteur de coupe. Aucun réglage à la main.
          </p>
          <div className="mt-3">
            <Essayage plante={planteChoisie} pot={potChoisi} />
          </div>

          <label className="mt-4 block text-xs text-[#6E746B]">
            Plante
            <select
              value={planteChoisie?.plante ?? ''}
              onChange={(e) =>
                setPlanteChoisie(plantes.find((p) => p.plante === e.target.value) ?? null)}
              className="mt-1 block w-full rounded-lg border border-[#DDD8CF] bg-white px-3 py-2 text-sm text-[#1B1F1A]"
            >
              <option value="">— aucune —</option>
              {plantes.map((p) => (
                <option key={p.plante} value={p.plante}>
                  {p.plante}
                  {p.verdict === 'validee' ? ' · validée' : ''}
                </option>
              ))}
            </select>
          </label>
          {plantes.length === 0 && (
            <p className="mt-2 text-xs text-[#8A5A1B]">
              Aucune plante posable. Il en faut une dont le pot a été détecté : son
              socle dit où poser le nouveau.
            </p>
          )}
        </div>

        <div>
          <h2 className="font-semibold text-[#1B1F1A]">
            Pots {pots ? `· ${pots.length}` : ''}
          </h2>
          {pots === null ? (
            <p className="mt-3 text-sm text-[#6E746B]">chargement…</p>
          ) : pots.length === 0 ? (
            <p className="mt-3 rounded-2xl border border-dashed border-[#DDD8CF] bg-white/60 px-5 py-8 text-center text-sm text-[#6E746B]">
              Bibliothèque vide.
            </p>
          ) : (
            <ul className="mt-3 divide-y divide-[#DDD8CF] overflow-hidden rounded-2xl border border-[#DDD8CF] bg-white">
              {pots.map((p) => {
                const actif = potChoisi?.fichier === p.fichier;
                return (
                  <li key={p.fichier} className={actif ? 'bg-[#E7EDE6]' : ''}>
                    <div className="flex items-center gap-2 px-4 py-3">
                      <button
                        type="button"
                        onClick={() => setPotChoisi(actif ? null : p)}
                        className="flex-1 text-left"
                      >
                        <div className="truncate text-sm font-medium text-[#1B1F1A]">
                          {p.fichier.replace(/\.glb$/, '')}
                        </div>
                        <div className="mt-0.5 text-xs text-[#6E746B]">
                          rayon {p.rayon.toFixed(3)} · haut. {p.hauteur.toFixed(3)} ·{' '}
                          {p.triangles.toLocaleString('fr-FR')} tri · {poids(p.octets)}
                        </div>
                      </button>
                      <button
                        type="button"
                        onClick={() => void supprimer(p)}
                        title="Retirer de la bibliothèque"
                        className="rounded-lg border border-[#DDD8CF] px-2 py-1 text-xs text-[#8A1B1B]"
                      >
                        ✕
                      </button>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </section>
    </>
  );
}
