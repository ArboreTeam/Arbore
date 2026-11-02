'use client';

import { useCallback, useEffect, useState } from 'react';

import { CLARTE_CIEL_MAX, type ReglagesVignette, clarte } from '@/lib/generator/vignette';

type Fiche = {
  id: string;
  nom: string;
  potless: boolean;
  empreinteModele: string | null;
  empreinteVignette: string | null;
  /** Version du modèle dont la vignette servie est issue. */
  empreinteVignetteModele: string | null;
  /** La provenance ne correspond plus au modèle servi — ou est inconnue. */
  perimee: boolean;
  url: string;
};

type Apercu = {
  env: string; total: number; sansVignette: number; perimees: number; plantes: Fiche[];
};

type TacheAffichee = {
  id: string; env: string; plante: string; etat: string; erreur?: string;
};

const CHAMPS: Array<[keyof ReglagesVignette, string, string]> = [
  ['echantillons', 'échantillons', 'number'],
  ['puissanceCle', 'puissance de la clé', 'number'],
  ['ambiante', 'ambiante', 'number'],
  ['teinteSol', 'teinte du sol', 'number'],
];

export default function Pilote({
  environnements, defauts, clarteCielMax, file,
}: {
  environnements: string[];
  defauts: ReglagesVignette;
  clarteCielMax: number;
  file: TacheAffichee[];
}) {
  const [env, setEnv] = useState(environnements[0]);
  const [apercu, setApercu] = useState<Apercu | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);
  const [chargement, setChargement] = useState(false);
  const [reglages, setReglages] = useState<ReglagesVignette>(defauts);
  const [choisies, setChoisies] = useState<Set<string>>(new Set());
  const [message, setMessage] = useState<string | null>(null);

  const charger = useCallback(async (nom: string) => {
    setChargement(true);
    setErreur(null);
    setApercu(null);
    setChoisies(new Set());
    try {
      const r = await fetch(`/api/generator/vignettes/apercu?env=${encodeURIComponent(nom)}`);
      const j = await r.json();
      if (!r.ok) throw new Error(j?.error ?? `erreur ${r.status}`);
      setApercu(j);
    } catch (e) {
      // Dire la panne. Une grille vide ferait passer un réseau coupé pour un
      // catalogue sans vignettes — exactement le genre de silence que cet
      // écran existe pour supprimer.
      setErreur(e instanceof Error ? e.message : 'environnement injoignable');
    } finally {
      setChargement(false);
    }
  }, []);

  useEffect(() => { void charger(env); }, [env, charger]);

  const clarteCiel = clarte(reglages.ciel);
  const cielRefuse = !Number.isFinite(clarteCiel) || clarteCiel > clarteCielMax;

  const basculer = (id: string) => setChoisies((s) => {
    const n = new Set(s);
    if (n.has(id)) n.delete(id); else n.add(id);
    return n;
  });

  const deposer = async () => {
    setMessage(null);
    const r = await fetch('/api/generator/vignettes', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ env, plantes: Array.from(choisies), reglages }),
    });
    const j = await r.json().catch(() => null);
    setMessage(r.ok
      ? `${j?.posees ?? 0} déposée(s), ${j?.ignorees ?? 0} déjà en file`
      : (j?.error ?? `refus ${r.status}`));
    if (r.ok) setChoisies(new Set());
  };

  const enFile = file.filter((t) => t.etat === 'en_attente' || t.etat === 'en_cours');

  return (
    <>
      <div className="mb-4 flex flex-wrap items-center gap-2">
        {environnements.map((nom) => (
          <button
            key={nom}
            onClick={() => setEnv(nom)}
            className={`rounded-full border px-4 py-1.5 text-sm ${
              nom === env
                ? 'border-[#234632] bg-[#234632] text-white'
                : 'border-[#DDD8CF] bg-white text-[#1B1F1A]'
            }`}
          >
            {nom}
          </button>
        ))}
        {apercu && (
          <span className="ml-2 text-sm text-[#6E746B]">
            {apercu.total} plante{apercu.total > 1 ? 's' : ''} · {apercu.sansVignette} sans
            empreinte de vignette · <strong>{apercu.perimees} à refaire</strong>
          </span>
        )}
      </div>

      <p className="mb-4 rounded-xl border border-[#DDD8CF] bg-white px-3 py-2 text-[12px] text-[#6E746B]">
        Cette page montre un environnement à la fois, avec ses propres fiches. Une
        comparaison d&apos;un environnement à l&apos;autre n&apos;est pas proposée :
        rien ne garantit aujourd&apos;hui que les deux catalogues désignent la même
        plante par le même identifiant.
      </p>

      <div className="mb-5 rounded-2xl border border-[#DDD8CF] bg-white p-4">
        <div className="mb-3 text-sm font-semibold text-[#1B1F1A]">Réglages de rendu</div>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
          {(['ciel', 'herbe'] as const).map((k) => (
            <label key={k} className="text-[11px] text-[#6E746B]">
              {k}
              <input
                type="color"
                value={reglages[k]}
                onChange={(e) => setReglages({ ...reglages, [k]: e.target.value })}
                className="mt-1 block h-9 w-full rounded border border-[#DDD8CF]"
              />
            </label>
          ))}
          {CHAMPS.map(([cle, libelle]) => (
            <label key={cle} className="text-[11px] text-[#6E746B]">
              {libelle}
              <input
                type="number"
                step={cle === 'echantillons' ? 1 : 0.01}
                value={reglages[cle]}
                onChange={(e) => setReglages({ ...reglages, [cle]: Number(e.target.value) })}
                className="mt-1 block h-9 w-full rounded border border-[#DDD8CF] px-2 text-[#1B1F1A]"
              />
            </label>
          ))}
        </div>

        <div className={`mt-3 rounded-xl px-3 py-2 text-[12px] ${
          cielRefuse
            ? 'border border-[#E6B3B3] bg-[#FBEDED] text-[#8A1B1B]'
            : 'border border-[#DDD8CF] bg-[#F7F5F1] text-[#6E746B]'
        }`}>
          Clarté du ciel : <strong>{Number.isFinite(clarteCiel) ? Math.round(clarteCiel) : '—'}</strong>
          {' '}· plafond {clarteCielMax}
          {cielRefuse && (
            <>
              {' '}— au-delà de 225, <code>hasLegacyWhiteWallDarkFloor</code> fait
              refuser la vignette par l&apos;app, qui garde alors l&apos;ancienne image
              sans rien signaler. Le fond de l&apos;app lui-même, #F0EEEA, mesure 238.
            </>
          )}
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <button
            onClick={() => void deposer()}
            disabled={cielRefuse || choisies.size === 0}
            className="rounded-full bg-[#234632] px-4 py-2 text-sm text-white disabled:opacity-40"
          >
            Rendre {choisies.size > 0 ? `${choisies.size} vignette(s)` : '— rien de choisi'}
          </button>
          <button
            onClick={() => setChoisies(new Set(apercu?.plantes.map((p) => p.id) ?? []))}
            className="rounded-full border border-[#DDD8CF] bg-white px-4 py-2 text-sm"
          >
            tout choisir
          </button>
          {/*
            Le bouton qui évite de refaire les 123 pour une plante qui a changé :
            une passe complète dure près de neuf heures.
          */}
          <button
            onClick={() => setChoisies(new Set(
              (apercu?.plantes ?? []).filter((p) => p.perimee).map((p) => p.id),
            ))}
            disabled={!apercu || apercu.perimees === 0}
            className="rounded-full border border-[#DDD8CF] bg-white px-4 py-2 text-sm disabled:opacity-40"
          >
            seulement les {apercu?.perimees ?? 0} à refaire
          </button>
          <button
            onClick={() => setChoisies(new Set())}
            className="rounded-full border border-[#DDD8CF] bg-white px-4 py-2 text-sm"
          >
            aucune
          </button>
          <button
            onClick={() => setReglages(defauts)}
            className="rounded-full border border-[#DDD8CF] bg-white px-4 py-2 text-sm"
          >
            réglages par défaut
          </button>
          {message && <span className="text-sm text-[#6E746B]">{message}</span>}
        </div>
      </div>

      {enFile.length > 0 && (
        <div className="mb-4 rounded-2xl border border-[#E3C9A8] bg-[#FBF3E8] px-4 py-3 text-sm text-[#8A5A1B]">
          {enFile.length} vignette{enFile.length > 1 ? 's' : ''} en file ·{' '}
          {enFile.filter((t) => t.etat === 'en_cours').length} en cours
        </div>
      )}

      {erreur && (
        <div className="mb-4 rounded-2xl border border-[#E6B3B3] bg-[#FBEDED] px-4 py-3 text-sm text-[#8A1B1B]">
          {erreur}
        </div>
      )}

      {chargement && <div className="text-sm text-[#6E746B]">chargement…</div>}

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5 xl:grid-cols-6">
        {apercu?.plantes.map((p) => (
          <button
            key={p.id}
            onClick={() => basculer(p.id)}
            className={`overflow-hidden rounded-xl border bg-white text-left ${
              choisies.has(p.id) ? 'border-[#234632] ring-2 ring-[#234632]' : 'border-[#DDD8CF]'
            }`}
          >
            {/* Pas de next/image : la source est une autre origine, choisie à
                l'exécution parmi les environnements déclarés. */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={p.url}
              alt={p.nom}
              loading="lazy"
              className="aspect-[4/5] w-full bg-[#F2F0EC] object-contain"
            />
            <div className="px-2 py-1.5">
              <div className="truncate text-[12px] font-medium text-[#1B1F1A]">{p.nom}</div>
              <div className="text-[10px] text-[#6E746B]">
                {p.empreinteVignette ? `v ${p.empreinteVignette}` : 'aucune empreinte'}
                {p.potless ? ' · sans pot' : ''}
              </div>
            </div>
          </button>
        ))}
      </div>
    </>
  );
}
