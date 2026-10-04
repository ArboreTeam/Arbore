// Tableau de bord de l'atelier.
//
// Rien ici n'est public : le middleware exige une session valide pour tout ce
// qui vit sous cet hôte, et rend ces pages introuvables depuis le site public.
//
// L'écran de revue — plante, aperçus, candidats de coupe du pot — viendra
// quand les routes de la file seront développées (#609).
export const dynamic = 'force-dynamic';

export default function Atelier() {
  return (
    <main className="min-h-screen bg-[#F0EEEA] px-6 py-10">
      <div className="mx-auto max-w-4xl">
        <header className="flex items-start justify-between">
          <div>
            <h1 className="text-3xl font-bold text-[#1B1F1A]">Atelier 3D</h1>
            <p className="mt-1 text-sm text-[#6E746B]">
              File de génération et revue des modèles.
            </p>
          </div>
          <form action="/api/generator/logout" method="post">
            <button className="rounded-lg border border-[#DDD8CF] px-3 py-2 text-sm text-[#6E746B]">
              Quitter
            </button>
          </form>
        </header>

        <section className="mt-10 rounded-2xl border border-[#DDD8CF] bg-white p-6">
          <h2 className="font-semibold text-[#1B1F1A]">Prochaines étapes</h2>
          <ul className="mt-3 space-y-2 text-sm text-[#6E746B]">
            <li>· File de tâches — dépôt, réservation, expiration</li>
            <li>· Historique des graines, consigné au tirage</li>
            <li>· Revue : aperçus et candidats de coupe du pot</li>
          </ul>
        </section>
      </div>
    </main>
  );
}
