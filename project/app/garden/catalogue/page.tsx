'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { onAuthStateChange } from '@/lib/authService';
import { API_URL, fetchWithAuth } from '@/lib/api';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { ArrowLeft, Leaf, Search, Droplet, Sun, Loader2, Sparkles } from 'lucide-react';
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
      <main className="min-h-screen bg-arbore-beige pt-24 pb-16">
        {/* Header */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-8">
          <button
            onClick={() => router.back()}
            className="flex items-center gap-2 text-[#234632] hover:text-[#16291D] font-semibold transition-colors mb-6"
          >
            <ArrowLeft className="w-5 h-5" />
            Retour
          </button>

          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-6">
            <div>
              <h1 className="text-4xl font-bold text-[#234632] mb-1">Catalogue de plantes 🌿</h1>
              <p className="text-gray-500">Cliquez sur une plante pour voir ses détails et l'ajouter à votre jardin</p>
            </div>
            <button
              onClick={() => router.push('/garden/generate')}
              className="flex items-center gap-2 bg-gradient-to-r from-purple-500 to-indigo-600 hover:from-purple-600 hover:to-indigo-700 text-white font-bold py-3 px-6 rounded-full shadow-md hover:shadow-lg transition-all whitespace-nowrap"
            >
              <Sparkles className="w-5 h-5" />
              Générer avec l'IA
            </button>
          </div>

          {/* Recherche */}
          <div className="relative max-w-lg">
            <Search className="absolute left-4 top-3.5 w-5 h-5 text-gray-400" />
            <input
              type="text"
              placeholder="Rechercher une plante..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-12 pr-4 py-3 border border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-[#234632]"
            />
          </div>
        </section>

        {/* Liste */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {loading ? (
            <div className="flex justify-center py-20">
              <Loader2 className="w-10 h-10 animate-spin text-[#234632]" />
            </div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-20">
              <Leaf className="w-16 h-16 text-gray-200 mx-auto mb-4" />
              <p className="text-xl text-gray-500">Aucune plante trouvée</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {filtered.map((plant, index) => (
                <motion.button
                  key={plant.id}
                  onClick={() => router.push(`/garden/plant/${plant.id}?from=catalogue`)}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.4, delay: index * 0.05 }}
                  className="bg-white rounded-2xl shadow-md hover:shadow-xl transition-all overflow-hidden group cursor-pointer text-left w-full"
                >
                  <div className="bg-gradient-to-br from-green-400 to-green-600 h-44 relative overflow-hidden">
                    {plant.imageURLs?.[0] ? (
                      <img
                        src={plant.imageURLs[0]}
                        alt={plant.name}
                        className="w-full h-full object-cover group-hover:scale-110 transition-transform"
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center">
                        <Leaf className="w-16 h-16 text-white opacity-40" />
                      </div>
                    )}
                  </div>
                  <div className="p-5">
                    <h3 className="text-lg font-bold text-gray-900 mb-1">{plant.name}</h3>
                    <p className="text-gray-500 text-sm mb-3">{plant.translations?.fr?.plantType || plant.type}</p>
                    {plant.translations?.fr?.description && (
                      <p className="text-gray-600 text-sm line-clamp-2 mb-3">{plant.translations.fr.description}</p>
                    )}
                    <div className="flex gap-3 text-sm border-t border-gray-100 pt-3">
                      <span className="flex items-center gap-1 text-orange-500">
                        <Sun className="w-4 h-4" />
                        {plant.translations?.fr?.sun?.lightType || '—'}
                      </span>
                      <span className="flex items-center gap-1 text-blue-500">
                        <Droplet className="w-4 h-4" />
                        {plant.translations?.fr?.water?.frequency || '—'}
                      </span>
                    </div>
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
