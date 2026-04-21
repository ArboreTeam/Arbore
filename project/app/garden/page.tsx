'use client';

import { useState, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { onAuthStateChange, getFirebaseToken } from '@/lib/authService';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { Plus, Droplet, Sun, Leaf, Calendar, CloudSun, Loader2, ArrowLeft, AlertCircle } from 'lucide-react';
import { motion } from 'framer-motion';
import { Suspense } from 'react';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

async function fetchWithAuth(url: string) {
  const token = await getFirebaseToken();
  return fetch(url, {
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': process.env.NEXT_PUBLIC_ARBORE_API_KEY || '',
      'Authorization': `Bearer ${token}`,
    },
  });
}

function GardenContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const gardenId = searchParams.get('id');

  const [loading, setLoading] = useState(true);
  const [garden, setGarden] = useState<any>(null);
  const [plants, setPlants] = useState<any[]>([]);
  const [loadingPlants, setLoadingPlants] = useState(false);

  useEffect(() => {
    const unsubscribe = onAuthStateChange((user) => {
      if (!user) {
        router.push('/login');
      } else if (!gardenId) {
        router.push('/welcome');
      } else {
        fetchGardenAndPlants();
      }
    });
    return () => unsubscribe();
  }, [gardenId, router]);

  const fetchGardenAndPlants = async () => {
    try {
      setLoading(true);
      const res = await fetchWithAuth(`${API_URL}/gardens/${gardenId}`);
      if (!res.ok) { router.push('/welcome'); return; }
      const gardenData = await res.json();
      setGarden(gardenData);

      // Récupérer les détails de chaque plante du jardin
      const plantIds: string[] = (gardenData.plants || []).map((p: any) => p.plantId);
      if (plantIds.length === 0) { setLoading(false); return; }

      setLoadingPlants(true);
      const plantDetails = await Promise.all(
        plantIds.map(async (plantId: string) => {
          try {
            const r = await fetchWithAuth(`${API_URL}/plants/${plantId}`);
            if (!r.ok) return null;
            return await r.json();
          } catch { return null; }
        })
      );
      setPlants(plantDetails.filter(Boolean));
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
      setLoadingPlants(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center pt-24">
        <Loader2 className="w-12 h-12 animate-spin text-[#2D5A27]" />
      </div>
    );
  }

  return (
    <main className="min-h-screen bg-gray-50 pt-24 pb-16">
      {/* Header */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-10">
        <div className="flex items-center gap-4 mb-6">
          <button
            onClick={() => router.push('/welcome')}
            className="flex items-center gap-2 text-[#2D5A27] hover:text-[#1f4620] font-semibold transition-colors"
          >
            <ArrowLeft className="w-5 h-5" />
            Mes jardins
          </button>
        </div>

        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-6">
          <div>
            <h1 className="text-4xl font-bold text-[#2D5A27] mb-1">
              {garden?.name || 'Mon Jardin'} 🌱
            </h1>
            <p className="text-gray-500">{plants.length} plante{plants.length !== 1 ? 's' : ''}</p>
          </div>
          <div className="flex flex-wrap gap-3">
            <button
              onClick={() => router.push('/garden/calendar')}
              className="bg-gradient-to-r from-[#2D5A27] to-[#3d7a37] text-white font-bold py-2 px-5 rounded-full shadow hover:shadow-lg transition-all flex items-center gap-2"
            >
              <Calendar className="w-4 h-4" /> Calendrier
            </button>
            <button
              onClick={() => router.push('/garden/seasons')}
              className="bg-gradient-to-r from-amber-500 to-orange-600 text-white font-bold py-2 px-5 rounded-full shadow hover:shadow-lg transition-all flex items-center gap-2"
            >
              <CloudSun className="w-4 h-4" /> Saisons
            </button>
            <button
              onClick={() => router.push('/garden/catalogue')}
              className="bg-gradient-to-r from-[#2D5A27] to-[#3d7a37] text-white font-bold py-2 px-5 rounded-full shadow hover:shadow-lg transition-all flex items-center gap-2"
            >
              <Plus className="w-4 h-4" /> Ajouter une plante
            </button>
          </div>
        </div>
      </section>

      {/* Plantes */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {loadingPlants ? (
          <div className="flex justify-center py-20">
            <Loader2 className="w-10 h-10 animate-spin text-[#2D5A27]" />
          </div>
        ) : plants.length === 0 ? (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="text-center py-20"
          >
            <Leaf className="w-20 h-20 text-gray-200 mx-auto mb-4" />
            <p className="text-xl text-gray-500 mb-2">Ce jardin est vide</p>
            <p className="text-gray-400 mb-6">Ajoutez des plantes depuis le catalogue</p>
            <button
              onClick={() => router.push('/garden/catalogue')}
              className="bg-[#2D5A27] hover:bg-[#1f4620] text-white font-bold py-3 px-8 rounded-full shadow-lg transition-all inline-flex items-center gap-2"
            >
              <Plus className="w-5 h-5" /> Parcourir le catalogue
            </button>
          </motion.div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {plants.map((plant, index) => (
              <motion.button
                key={plant.id}
                onClick={() => router.push(`/garden/plant/${plant.id}?from=garden&gardenId=${gardenId}`)}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
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
                  <div className="flex items-center justify-between text-sm bg-blue-50 -mx-5 -mb-5 px-5 py-3 rounded-b-2xl">
                    <span className="text-gray-500 flex items-center gap-1">
                      <Droplet className="w-4 h-4 text-blue-500" /> Arrosage
                    </span>
                    <span className="font-semibold text-blue-600">
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
  );
}

export default function GardenPage() {
  return (
    <>
      <Navbar />
      <Suspense fallback={
        <div className="min-h-screen flex items-center justify-center pt-24">
          <Loader2 className="w-12 h-12 animate-spin text-[#2D5A27]" />
        </div>
      }>
        <GardenContent />
      </Suspense>
      <Footer />
    </>
  );
}
