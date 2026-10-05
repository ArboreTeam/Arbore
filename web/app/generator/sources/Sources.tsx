'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

// Les images d'entrée, et le dépôt des tâches.
//
// Elles vivaient sur Drive pendant le spike : l'atelier ne pouvait alors pas
// déposer de tâche, il aurait écrit un chemin qu'il ne pouvait ni voir ni
// vérifier, et la faute ne se serait révélée qu'au moment où l'ouvrier prend la
// tâche — 165 s de GPU plus tard. Sur le volume, l'atelier les voit.
//
// Le nom du fichier EST le nom de la plante. C'est lui qui fait l'identité dans
// tout l'atelier, de la file aux artefacts au verdict.

type Source = {
  plante: string;
  fichier: string;
  octets: number;
  modifie: number;
  enFile: boolean;
  verdict?: 'validee' | 'invalidee' | 'ecartee';
  sansPot: boolean;
};

// Même taille que côté ouvrier, et pour la même raison : Next tronque à 10 Mo
// tout corps qui traverse son middleware, sans lever d'erreur.
const MORCEAU = 8 * 1024 * 1024;

const EXT = { 'image/png': '.png', 'image/jpeg': '.jpg', 'image/webp': '.webp' } as const;

/**
 * Nom de plante tiré du nom de fichier.
 *
 * Le serveur n'accepte que `[a-z0-9_-]`. Plutôt que de rejeter « Aloé Vera.png »
 * avec un message, on le transforme en `Aloe_Vera` et on montre le résultat
 * avant d'envoyer : la correction est visible, pas devinée.
 */
function nomDePlante(fichier: string): string {
  return fichier
    .replace(/\.[^.]+$/, '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 64);
}

function poids(o: number): string {
  return o < 1e6 ? `${Math.round(o / 1e3)} Ko` : `${(o / 1e6).toFixed(1)} Mo`;
}

export default function Sources() {
  const [liste, setListe] = useState<Source[] | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [envoi, setEnvoi] = useState<{ nom: string; part: number } | null>(null);
  const [occupe, setOccupe] = useState<string | null>(null);
  const champ = useRef<HTMLInputElement>(null);

  const recharger = useCallback(async () => {
    try {
      const r = await fetch('/api/generator/sources');
      if (!r.ok) throw new Error(String(r.status));
      setListe((await r.json()).sources);
    } catch {
      setErreur('liste indisponible');
    }
  }, []);

  useEffect(() => {
    void recharger();
  }, [recharger]);

  async function televerser(fichier: File) {
    const ext = EXT[fichier.type as keyof typeof EXT];
    if (!ext) {
      setErreur(`${fichier.name} : format refusé, il faut un PNG, un JPEG ou un WebP`);
      return;
    }
    const nom = `${nomDePlante(fichier.name)}${ext}`;
    setErreur(null);

    for (let position = 0; position < Math.max(fichier.size, 1); position += MORCEAU) {
      const bout = fichier.slice(position, position + MORCEAU);
      const dernier = position + MORCEAU >= fichier.size;
      setEnvoi({ nom, part: Math.round((position / Math.max(fichier.size, 1)) * 100) });
      const r = await fetch(
        `/api/generator/sources/${encodeURIComponent(nom)}?position=${position}${dernier ? '&final=1' : ''}`,
        { method: 'PUT', body: bout },
      );
      if (!r.ok) {
        setErreur(`${nom} : téléversement refusé (${r.status})`);
        setEnvoi(null);
        return;
      }
      if (dernier) break;
    }
    setEnvoi(null);
    await recharger();
  }

  async function choisir(fichiers: FileList | null) {
    if (!fichiers) return;
    for (const f of Array.from(fichiers)) await televerser(f);
    if (champ.current) champ.current.value = '';
  }

  async function deposer(plante: string) {
    setOccupe(plante);
    const r = await fetch('/api/generator/taches', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ plante }),
    });
    if (!r.ok) setErreur(`${plante} : dépôt refusé (${r.status})`);
    setOccupe(null);
    await recharger();
  }

  async function supprimer(s: Source) {
    setOccupe(s.plante);
    const r = await fetch(`/api/generator/sources/${encodeURIComponent(s.fichier)}`,
                          { method: 'DELETE' });
    if (!r.ok) {
      // 409 : une génération est en cours. On ne tire pas le tapis sous les
      // pieds de l'ouvrier, et réessayer plus tard marchera.
      const d = await r.json().catch(() => ({}));
      setErreur(`${s.plante} : ${d.error ?? `retrait refusé (${r.status})`}`);
    } else {
      const d = await r.json().catch(() => ({}));
      if (d.tachesRetirees) {
        setErreur(null);
        setInfo(`${s.plante} retirée, avec ${d.tachesRetirees} tâche(s) en attente`);
      }
    }
    setOccupe(null);
    await recharger();
  }

  /**
   * Une plante sans pot : l'ouvrier saute la détection, et elle n'entre pas
   * dans le périmètre des pots personnalisés. Un palmier hors pot a reçu une
   * proposition de coupe sur le premier lot ; la question n'avait pas lieu.
   */
  async function basculerSansPot(s: Source) {
    setOccupe(s.plante);
    await fetch(`/api/generator/sources/${encodeURIComponent(s.fichier)}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sansPot: !s.sansPot }),
    });
    setOccupe(null);
    await recharger();
  }

  const aDeposer = (liste ?? []).filter((s) => !s.enFile && !s.verdict);

  return (
    <>
      <section className="mt-8 rounded-2xl border border-dashed border-[#DDD8CF] bg-white/60 p-6">
        {/*
          Le contrôle natif est masqué plutôt que stylé : son libellé
          (« Choose Files », « No file chosen ») vient du navigateur et suit SA
          langue, pas celle de la page. Impossible à traduire autrement.
        */}
        <label className="inline-flex cursor-pointer items-center rounded-lg bg-[#234632] px-4 py-2 text-sm font-medium text-white">
          Choisir des images
          <input
            ref={champ}
            type="file"
            accept="image/png,image/jpeg,image/webp"
            multiple
            onChange={(e) => void choisir(e.target.files)}
            className="sr-only"
          />
        </label>
        <p className="mt-2 text-xs text-[#6E746B]">
          Le nom du fichier devient le nom de la plante. « Aloé Vera.png » donne{' '}
          <span className="font-mono">Aloe_Vera</span>. Déposer à nouveau remplace
          l&apos;image, utile quand le détourage s&apos;améliore.
        </p>
        {envoi && (
          <p className="mt-2 text-xs text-[#234632]">
            {envoi.nom} · {envoi.part} %
          </p>
        )}
      </section>

      {erreur && (
        <p className="mt-4 rounded-lg bg-[#F8D7D7] px-3 py-2 text-sm text-[#8A1B1B]">{erreur}</p>
      )}
      {info && (
        <p className="mt-4 rounded-lg bg-[#E7EDE6] px-3 py-2 text-sm text-[#234632]">{info}</p>
      )}

      {aDeposer.length > 1 && (
        <button
          type="button"
          onClick={async () => {
            for (const s of aDeposer) await deposer(s.plante);
          }}
          className="mt-6 rounded-lg bg-[#234632] px-4 py-2 text-sm font-medium text-white"
        >
          Déposer les {aDeposer.length} plantes en attente
        </button>
      )}

      <section className="mt-6">
        {liste === null ? (
          <p className="text-sm text-[#6E746B]">chargement…</p>
        ) : liste.length === 0 ? (
          <p className="rounded-2xl border border-dashed border-[#DDD8CF] bg-white/60 px-6 py-10 text-center text-sm text-[#6E746B]">
            Aucune image. Dépose les sources détourées ci-dessus : ce sont elles
            que l&apos;ouvrier ira chercher.
          </p>
        ) : (
          <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {liste.map((s) => (
              <li key={s.fichier} className="overflow-hidden rounded-2xl border border-[#DDD8CF] bg-white">
                <div className="aspect-square bg-[#F7F6F3]">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={`/api/generator/sources/${encodeURIComponent(s.fichier)}`}
                    alt={s.plante}
                    className="h-full w-full object-contain"
                  />
                </div>
                <div className="border-t border-[#DDD8CF] px-3 py-3">
                  <div className="truncate font-medium text-[#1B1F1A]" title={s.plante}>
                    {s.plante}
                  </div>
                  <div className="mt-0.5 text-xs text-[#6E746B]">{poids(s.octets)}</div>

                  <button
                    type="button"
                    disabled={occupe === s.plante}
                    onClick={() => void basculerSansPot(s)}
                    title="L'ouvrier ne cherchera pas de pot à retirer"
                    className={`mt-2 w-full rounded-lg px-2 py-1 text-[11px] ${
                      s.sansPot
                        ? 'bg-[#E7EDE6] text-[#234632]'
                        : 'border border-[#DDD8CF] text-[#6E746B] hover:border-[#234632]'
                    }`}
                  >
                    {s.sansPot ? 'sans pot ✓' : 'marquer sans pot'}
                  </button>

                  <div className="mt-3 flex gap-2">
                    {s.enFile ? (
                      <span className="flex-1 rounded-lg bg-[#F0EEEA] px-3 py-2 text-center text-xs text-[#6E746B]">
                        déjà en file
                      </span>
                    ) : s.verdict ? (
                      <button
                        type="button"
                        disabled={occupe === s.plante}
                        onClick={() => void deposer(s.plante)}
                        className="flex-1 rounded-lg border border-[#DDD8CF] px-3 py-2 text-xs text-[#1B1F1A] hover:border-[#234632]"
                      >
                        {s.verdict === 'validee' ? 'validée · régénérer' : 'invalidée · régénérer'}
                      </button>
                    ) : (
                      <button
                        type="button"
                        disabled={occupe === s.plante}
                        onClick={() => void deposer(s.plante)}
                        className="flex-1 rounded-lg bg-[#234632] px-3 py-2 text-xs font-medium text-white disabled:bg-[#B5BDB4]"
                      >
                        Déposer
                      </button>
                    )}
                    <button
                      type="button"
                      disabled={occupe === s.plante}
                      onClick={() => void supprimer(s)}
                      title="Retirer l'image (les aperçus déjà produits sont conservés)"
                      className="rounded-lg border border-[#DDD8CF] px-3 py-2 text-xs text-[#8A1B1B]"
                    >
                      ✕
                    </button>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
