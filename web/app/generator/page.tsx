// Tableau de bord de l'atelier.
//
// Rien ici n'est public : le middleware exige une session valide pour tout ce
// qui vit sous cet hôte, et rend ces pages introuvables depuis le site public.
//
// Composant serveur qui lit le dépôt directement, sans passer par ses propres
// routes HTTP. Un aller-retour réseau vers soi-même n'apporterait rien ici —
// les routes existent pour l'ouvrier, qui est ailleurs.
import Link from 'next/link';

import { aRevoir, bilan, lire } from '@/lib/generator/depot';

export const dynamic = 'force-dynamic';

function Compteur({ valeur, libelle, accent }: { valeur: number; libelle: string; accent?: boolean }) {
  return (
    <div className="rounded-xl border border-[#DDD8CF] bg-white px-4 py-3">
      <div className={`text-2xl font-semibold ${accent && valeur > 0 ? 'text-[#234632]' : 'text-[#1B1F1A]'}`}>
        {valeur}
      </div>
      <div className="mt-0.5 text-xs text-[#6E746B]">{libelle}</div>
    </div>
  );
}

export default function Atelier() {
  const b = bilan();
  const file = aRevoir();
  const etat = lire();
  const echecs = etat.taches.filter((t) => t.etat === 'echec').slice(-5).reverse();

  return (
    <main className="min-h-screen bg-[#F0EEEA] px-6 py-10">
      <div className="mx-auto max-w-5xl">
        <header className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-3xl font-bold text-[#1B1F1A]">Atelier 3D</h1>
            <p className="mt-1 text-sm text-[#6E746B]">
              File de génération et revue des modèles.
            </p>
          </div>
          <form action="/api/generator/logout" method="post">
            <button className="rounded-lg border border-[#DDD8CF] bg-white px-3 py-2 text-sm text-[#6E746B] hover:bg-[#F0EEEA]">
              Quitter
            </button>
          </form>
        </header>

        <section className="mt-8 grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7">
          <Compteur valeur={b.enAttente} libelle="en attente" />
          <Compteur valeur={b.enCours} libelle="en cours" />
          <Compteur valeur={file.length} libelle="à revoir" accent />
          <Compteur valeur={b.validees} libelle="validées" />
          <Compteur valeur={b.invalidees} libelle="invalidées" />
          <Compteur valeur={b.echecs} libelle="échecs" />
          <Compteur valeur={b.grainesBrulees} libelle="graines brûlées" />
        </section>

        {b.octetsLiberes > 0 && (
          <p className="mt-3 text-xs text-[#6E746B]">
            {(b.octetsLiberes / 1e9).toFixed(1)} Go de maillages effacés après verdict.
            Les aperçus sont conservés.
          </p>
        )}

        <section className="mt-10">
          <h2 className="font-semibold text-[#1B1F1A]">À revoir</h2>

          {file.length === 0 ? (
            <p className="mt-3 rounded-2xl border border-dashed border-[#DDD8CF] bg-white/60 px-6 py-10 text-center text-sm text-[#6E746B]">
              Rien à revoir. L&apos;ouvrier dépose ici les plantes qu&apos;il a livrées.
            </p>
          ) : (
            <ul className="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {file.map((p) => (
                <li key={p.plante}>
                  <Link
                    href={`/generator/revue/${p.plante}`}
                    className="block overflow-hidden rounded-2xl border border-[#DDD8CF] bg-white transition hover:border-[#234632]"
                  >
                    <div className="aspect-square bg-[#F7F6F3]">
                      {p.apercus[0] ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={`/api/generator/artefacts/${p.plante}/${p.apercus[0]}`}
                          alt={`Aperçu de ${p.plante}`}
                          className="h-full w-full object-contain"
                        />
                      ) : (
                        <div className="flex h-full items-center justify-center text-xs text-[#6E746B]">
                          aucun aperçu
                        </div>
                      )}
                    </div>
                    <div className="border-t border-[#DDD8CF] px-4 py-3">
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-[#1B1F1A]">{p.plante}</span>
                        {p.arbitrage && (
                          <span className="rounded-full bg-[#FBE9D0] px-2 py-0.5 text-[11px] text-[#8A5A1B]">
                            arbitrage
                          </span>
                        )}
                      </div>
                      <div className="mt-1 text-xs text-[#6E746B]">
                        graine {p.graine ?? '—'}
                        {p.essai && p.essai > 1 ? ` · essai ${p.essai}` : ''}
                        {!p.accepte ? ' · portillon rejeté' : ''}
                      </div>
                    </div>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </section>

        {echecs.length > 0 && (
          <section className="mt-10">
            <h2 className="font-semibold text-[#1B1F1A]">Derniers échecs</h2>
            <ul className="mt-3 divide-y divide-[#DDD8CF] rounded-2xl border border-[#DDD8CF] bg-white">
              {echecs.map((t) => (
                <li key={t.id} className="px-4 py-3">
                  <div className="text-sm font-medium text-[#1B1F1A]">{t.plante}</div>
                  <div className="mt-0.5 break-all font-mono text-xs text-[#6E746B]">{t.erreur}</div>
                </li>
              ))}
            </ul>
          </section>
        )}
      </div>
    </main>
  );
}
