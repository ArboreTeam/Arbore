'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { onAuthStateChange } from '@/lib/authService';
import { API_URL, fetchWithAuth } from '@/lib/api';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { ArrowLeft, Leaf, Search, Droplet, Sun, Loader2 } from 'lucide-react';
import { motion } from 'framer-motion';

export default function CataloguePage() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [plants, setPlants] = useState<any[]>([]);
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    const unsubscribe = onAuthStateChange((user) => {
      if (!user) { router.push('/login'); return; }
      fetchPlants();
    });
    return () => unsubscribe();
  }, [router]);

  const fetchPlants = async () => {
    try {
      const res = await fetchWithAuth(`${API_URL}/plants`);
      if (!res.ok) throw new Error();
      setPlants(await res.json() || []);
    } catch {
      setPlants([]);
    } finally {
      setLoading(false);
    }
  };

  const filtered = plants.filter((p) =>
    p.name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
    p.translations?.fr?.plantType?.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <>
      <Navbar />
      <main id="main-content" className="min-h-screen bg-background pt-24 pb-16">
        {/* Header */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-8">
          <button
            onClick={() => router.back()}
            className="mb-6 flex items-center gap-2 font-semibold text-arbore-green transition-colors hover:text-arbore-green-dark"
          >
            <ArrowLeft className="h-5 w-5" />
            Retour
          </button>

          <div className="mb-6">
            <h1 className="mb-1 font-display text-4xl font-extrabold text-arbore-green">Catalogue</h1>
            <p className="text-arbore-muted">Choisissez une plante pour voir ses détails et l&apos;ajouter à votre jardin</p>
          </div>

          {/* Recherche */}
          <div className="relative max-w-lg">
            <Search className="pointer-events-none absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-arbore-muted" />
            <input
              type="text"
              aria-label="Rechercher une plante"
              placeholder="Rechercher une plante…"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="arbore-input pl-12"
            />
          </div>
        </section>

        {/* Liste */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {loading ? (
            <div className="flex justify-center py-20">
              <Loader2 className="h-10 w-10 animate-spin text-arbore-green" />
            </div>
          ) : filtered.length === 0 ? (
            <div className="py-20 text-center">
              <Leaf className="mx-auto mb-4 h-16 w-16 text-arbore-sage/50" />
              <p className="text-xl text-arbore-muted">Aucune plante trouvée</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
              {filtered.map((plant, index) => (
                <motion.button
                  key={plant.id}
                  onClick={() => router.push(`/garden/plant/${plant.id}?from=catalogue`)}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.4, delay: index * 0.05 }}
                  whileHover={{ y: -4 }}
                  className="arbore-card group w-full overflow-hidden text-left transition-shadow hover:shadow-card"
                >
                  {/* Image + overlay + nom (façon PlantCard iOS) */}
                  <div className="relative h-52 overflow-hidden bg-arbore-soft">
                    {plant.imageURLs?.[0] ? (
                      <img loading="lazy" decoding="async"
                        src={plant.imageURLs[0]}
                        alt={plant.name}
                        className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-105"
                      />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center">
                        <Leaf className="h-16 w-16 text-arbore-sage" />
                      </div>
                    )}
                    <div className="absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-black/70 to-transparent" />
                    <div className="absolute inset-x-0 bottom-0 p-4">
                      <h3 className="font-display text-lg font-bold text-white drop-shadow">{plant.name}</h3>
                      <p className="text-sm text-white/85">{plant.translations?.fr?.plantType || plant.type}</p>
                    </div>
                  </div>
                  {/* Pied : chips entretien */}
                  <div className="flex gap-2 p-4">
                    <span className="inline-flex items-center gap-1.5 rounded-pill bg-arbore-gold/15 px-3 py-1 text-sm font-medium text-arbore-ink">
                      <Sun className="h-4 w-4 text-arbore-gold" />
                      {plant.translations?.fr?.sun?.lightType || '—'}
                    </span>
                    <span className="inline-flex items-center gap-1.5 rounded-pill bg-secondary px-3 py-1 text-sm font-medium text-arbore-green">
                      <Droplet className="h-4 w-4" />
                      {plant.translations?.fr?.water?.frequency || '—'}
                    </span>
                  </div>
                </motion.button>
              ))}
            </div>
          )}
        </section>
      </main>
      <Footer />
    </>
  );
}
