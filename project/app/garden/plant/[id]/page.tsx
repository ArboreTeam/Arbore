'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams, useSearchParams } from 'next/navigation';
import { onAuthStateChange, getFirebaseToken } from '@/lib/authService';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import {
  ArrowLeft,
  Droplet,
  Sun,
  Leaf,
  Heart,
  ShieldCheck,
  Sprout,
  Loader2,
  AlertCircle,
  Plus,
  Trash2,
  X,
  CheckCircle2
} from 'lucide-react';
import { motion } from 'framer-motion';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

async function fetchWithAuth(url: string, options: RequestInit = {}) {
  const token = await getFirebaseToken();
  return fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': process.env.NEXT_PUBLIC_ARBORE_API_KEY || '',
      'Authorization': `Bearer ${token}`,
      ...options.headers,
    },
  });
}

export default function PlantDetailPage() {
  const router = useRouter();
  const params = useParams();
  const searchParams = useSearchParams();
  const plantId = params.id as string;
  const fromGarden = searchParams.get('from') === 'garden';
  const gardenId = searchParams.get('gardenId');

  const [plant, setPlant] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  // Modal ajouter au jardin
  const [removingFromGarden, setRemovingFromGarden] = useState(false);
  const [showGardenModal, setShowGardenModal] = useState(false);
  const [gardens, setGardens] = useState<any[]>([]);
  const [loadingGardens, setLoadingGardens] = useState(false);
  const [addingToGarden, setAddingToGarden] = useState<string | null>(null);
  const [addedToGardens, setAddedToGardens] = useState<Set<string>>(new Set());

  useEffect(() => {
    const unsubscribe = onAuthStateChange((user) => {
      if (!user) {
        router.push('/login');
      } else {
        fetchPlant();
      }
    });
    return () => unsubscribe();
  }, [plantId, router]);

  const fetchPlant = async () => {
    try {
      const response = await fetchWithAuth(`${API_URL}/plants/${plantId}`);
      if (response.status === 404) { setNotFound(true); return; }
      if (!response.ok) throw new Error();
      setPlant(await response.json());
    } catch {
      setNotFound(true);
    } finally {
      setLoading(false);
    }
  };

  const removeFromGarden = async () => {
    if (!gardenId) return;
    setRemovingFromGarden(true);
    try {
      // Récupérer le jardin pour avoir la liste actuelle
      const res = await fetchWithAuth(`${API_URL}/gardens/${gardenId}`);
      if (!res.ok) throw new Error();
      const garden = await res.json();
      const newPlants = (garden.plants || []).filter((p: any) => p.plantId !== plantId);
      const updateRes = await fetchWithAuth(`${API_URL}/gardens/${gardenId}`, {
        method: 'PUT',
        body: JSON.stringify({ plants: newPlants }),
      } as any);
      if (!updateRes.ok) throw new Error();
      router.back();
    } catch {
      alert('Erreur lors de la suppression');
    } finally {
      setRemovingFromGarden(false);
    }
  };

  const openGardenModal = async () => {
    setShowGardenModal(true);
    setLoadingGardens(true);
    try {
      const response = await fetchWithAuth(`${API_URL}/gardens`);
      if (!response.ok) throw new Error();
      const data = await response.json();
      setGardens(data || []);
    } catch {
      setGardens([]);
    } finally {
      setLoadingGardens(false);
    }
  };

  const addToGarden = async (garden: any) => {
    setAddingToGarden(garden.id);
    try {
      // Construire la nouvelle liste de plantes
      const currentPlants = garden.plants || [];
      const alreadyIn = currentPlants.some((p: any) => p.plantId === plantId);
      if (alreadyIn) {
        setAddedToGardens(prev => new Set(prev).add(garden.id));
        return;
      }
      const newPlants = [...currentPlants, { plantId }];

      const response = await fetchWithAuth(`${API_URL}/gardens/${garden.id}`, {
        method: 'PUT',
        body: JSON.stringify({ plants: newPlants }),
      });
      if (!response.ok) throw new Error();
      setAddedToGardens(prev => new Set(prev).add(garden.id));
    } catch {
      alert('Erreur lors de l\'ajout au jardin');
    } finally {
      setAddingToGarden(null);
    }
  };

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center pt-24">
          <Loader2 className="w-12 h-12 animate-spin text-[#2D5A27]" />
        </div>
        <Footer />
      </>
    );
  }

  if (notFound || !plant) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center pt-24">
          <div className="text-center">
            <AlertCircle className="w-16 h-16 text-gray-300 mx-auto mb-4" />
            <p className="text-xl text-gray-600">Plante non trouvée</p>
            <button onClick={() => router.back()} className="mt-4 text-[#2D5A27] font-semibold underline">
              Retour
            </button>
          </div>
        </div>
        <Footer />
      </>
    );
  }

  const fr = plant.translations?.fr;
  const image = plant.imageURLs?.[0];

  return (
    <>
      <Navbar />
      <main className="min-h-screen bg-gray-50 pt-24 pb-16">

        {/* Barre retour + bouton ajouter */}
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 mb-6 flex items-center justify-between">
          <button
            onClick={() => router.back()}
            className="flex items-center gap-2 text-[#2D5A27] hover:text-[#1f4620] font-semibold transition-colors"
          >
            <ArrowLeft className="w-5 h-5" />
            Retour
          </button>

          {fromGarden ? (
            <button
              onClick={removeFromGarden}
              disabled={removingFromGarden}
              className="flex items-center gap-2 bg-red-500 hover:bg-red-600 disabled:opacity-60 text-white font-bold py-2 px-5 rounded-full shadow-md hover:shadow-lg transition-all"
            >
              {removingFromGarden ? <Loader2 className="w-4 h-4 animate-spin" /> : <Trash2 className="w-4 h-4" />}
              Supprimer du jardin
            </button>
          ) : (
            <button
              onClick={openGardenModal}
              className="flex items-center gap-2 bg-[#2D5A27] hover:bg-[#1f4620] text-white font-bold py-2 px-5 rounded-full shadow-md hover:shadow-lg transition-all"
            >
              <Plus className="w-4 h-4" />
              Ajouter à mon jardin
            </button>
          )}
        </div>

        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 space-y-8">

          {/* Hero */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="rounded-3xl overflow-hidden shadow-lg relative h-80 bg-gradient-to-br from-green-400 to-green-700"
          >
            {image && (
              <img src={image} alt={plant.name} className="w-full h-full object-cover absolute inset-0" />
            )}
            <div className="absolute inset-0 bg-black/40" />
            <div className="absolute inset-0 flex flex-col items-center justify-center text-center p-8 z-10">
              <h1 className="text-4xl md:text-5xl font-bold text-white mb-2">{plant.name}</h1>
              <p className="text-xl text-white/90">{fr?.plantType || plant.type}</p>
            </div>
          </motion.div>

          {/* Description */}
          {fr?.description && (
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
              className="bg-white rounded-2xl shadow-md p-8">
              <h2 className="text-2xl font-bold text-[#2D5A27] mb-3 flex items-center gap-2">
                <Leaf className="w-6 h-6" /> Description
              </h2>
              <p className="text-gray-700 text-lg leading-relaxed">{fr.description}</p>
            </motion.div>
          )}

          {/* Lumière */}
          {fr?.sun && (
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.15 }}
              className="bg-white rounded-2xl shadow-md p-8">
              <h2 className="text-2xl font-bold text-[#2D5A27] mb-4 flex items-center gap-2">
                <Sun className="w-6 h-6 text-orange-500" /> Lumière
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {fr.sun.lightType && <Info label="Type de lumière" value={fr.sun.lightType} />}
                {fr.sun.durationPerDay && <Info label="Durée par jour" value={fr.sun.durationPerDay} />}
                {fr.sun.orientation && <Info label="Orientation" value={fr.sun.orientation} />}
                {fr.sun.windowDistance && <Info label="Distance fenêtre" value={fr.sun.windowDistance} />}
              </div>
              {fr.sun.recommendedRooms?.length > 0 && (
                <div className="mt-4">
                  <p className="text-sm font-semibold text-gray-600 mb-2">Pièces recommandées</p>
                  <div className="flex flex-wrap gap-2">
                    {fr.sun.recommendedRooms.map((room: string, i: number) => (
                      <span key={i} className="px-3 py-1 bg-orange-100 text-orange-700 rounded-full text-sm">{room}</span>
                    ))}
                  </div>
                </div>
              )}
              {fr.sun.tips?.length > 0 && <Tips items={fr.sun.tips} />}
            </motion.div>
          )}

          {/* Arrosage */}
          {fr?.water && (
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}
              className="bg-white rounded-2xl shadow-md p-8">
              <h2 className="text-2xl font-bold text-[#2D5A27] mb-4 flex items-center gap-2">
                <Droplet className="w-6 h-6 text-blue-500" /> Arrosage
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {fr.water.frequency && <Info label="Fréquence" value={fr.water.frequency} />}
                {fr.water.amount && <Info label="Quantité" value={fr.water.amount} />}
                {fr.water.method && <Info label="Méthode" value={fr.water.method} />}
                {fr.water.humidity && <Info label="Humidité" value={fr.water.humidity} />}
                {fr.water.recommendedWater && <Info label="Eau recommandée" value={fr.water.recommendedWater} />}
              </div>
              {fr.water.signsLack && (
                <div className="mt-4 p-4 bg-yellow-50 rounded-xl border border-yellow-200">
                  <p className="text-sm font-semibold text-yellow-700 mb-1">Signes de manque d'eau</p>
                  <p className="text-gray-700 text-sm">{fr.water.signsLack}</p>
                </div>
              )}
              {fr.water.signsExcess && (
                <div className="mt-3 p-4 bg-red-50 rounded-xl border border-red-200">
                  <p className="text-sm font-semibold text-red-700 mb-1">Signes d'excès d'eau</p>
                  <p className="text-gray-700 text-sm">{fr.water.signsExcess}</p>
                </div>
              )}
            </motion.div>
          )}

          {/* Santé */}
          {fr?.health && (
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.25 }}
              className="bg-white rounded-2xl shadow-md p-8">
              <h2 className="text-2xl font-bold text-[#2D5A27] mb-4 flex items-center gap-2">
                <ShieldCheck className="w-6 h-6 text-green-500" /> Santé & Maladies
              </h2>
              {fr.health.commonProblems?.length > 0 && <TagList label="Problèmes courants" items={fr.health.commonProblems} color="red" />}
              {fr.health.pests?.length > 0 && <TagList label="Parasites" items={fr.health.pests} color="orange" />}
              {fr.health.treatments?.length > 0 && <TagList label="Traitements" items={fr.health.treatments} color="green" />}
              {fr.health.prevention?.length > 0 && <TagList label="Prévention" items={fr.health.prevention} color="blue" />}
            </motion.div>
          )}

          {/* Cycle de vie */}
          {fr?.lifeCycle && (
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 }}
              className="bg-white rounded-2xl shadow-md p-8">
              <h2 className="text-2xl font-bold text-[#2D5A27] mb-4 flex items-center gap-2">
                <Sprout className="w-6 h-6 text-emerald-500" /> Cycle de vie
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {fr.lifeCycle.growth && <Info label="Croissance" value={fr.lifeCycle.growth} />}
                {fr.lifeCycle.flowering && <Info label="Floraison" value={fr.lifeCycle.flowering} />}
                {fr.lifeCycle.dormancy && <Info label="Dormance" value={fr.lifeCycle.dormancy} />}
                {fr.lifeCycle.fertilizer && <Info label="Fertilisation" value={fr.lifeCycle.fertilizer} />}
                {fr.lifeCycle.pruning && <Info label="Taille" value={fr.lifeCycle.pruning} />}
              </div>
            </motion.div>
          )}

          {/* Entretien */}
          {fr?.care && (
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.35 }}
              className="bg-white rounded-2xl shadow-md p-8">
              <h2 className="text-2xl font-bold text-[#2D5A27] mb-4 flex items-center gap-2">
                <Heart className="w-6 h-6 text-pink-500" /> Entretien
              </h2>
              {fr.care.weekly?.length > 0 && <CareList label="Chaque semaine" items={fr.care.weekly} />}
              {fr.care.monthly?.length > 0 && <CareList label="Chaque mois" items={fr.care.monthly} />}
              {fr.care.yearly?.length > 0 && <CareList label="Chaque année" items={fr.care.yearly} />}
              {fr.care.extraTips?.length > 0 && <Tips items={fr.care.extraTips} />}
            </motion.div>
          )}

        </div>

        {/* Modal choisir jardin */}
        {showGardenModal && (
          <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              className="bg-white rounded-2xl shadow-2xl max-w-md w-full"
            >
              <div className="flex items-center justify-between p-6 border-b border-gray-200">
                <h2 className="text-xl font-bold text-[#2D5A27]">Choisir un jardin</h2>
                <button onClick={() => setShowGardenModal(false)}>
                  <X className="w-6 h-6 text-gray-500 hover:text-gray-700" />
                </button>
              </div>

              <div className="p-6">
                {loadingGardens ? (
                  <div className="flex justify-center py-8">
                    <Loader2 className="w-8 h-8 animate-spin text-[#2D5A27]" />
                  </div>
                ) : gardens.length === 0 ? (
                  <div className="text-center py-8">
                    <Leaf className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                    <p className="text-gray-500">Aucun jardin trouvé</p>
                    <button
                      onClick={() => { setShowGardenModal(false); router.push('/welcome'); }}
                      className="mt-3 text-[#2D5A27] font-semibold underline text-sm"
                    >
                      Créer un jardin
                    </button>
                  </div>
                ) : (
                  <div className="space-y-3">
                    {gardens.map((garden: any) => {
                      const added = addedToGardens.has(garden.id);
                      const isLoading = addingToGarden === garden.id;
                      return (
                        <button
                          key={garden.id}
                          onClick={() => !added && addToGarden(garden)}
                          disabled={added || isLoading}
                          className={`w-full flex items-center justify-between p-4 rounded-xl border-2 transition-all ${
                            added
                              ? 'border-green-400 bg-green-50'
                              : 'border-gray-200 hover:border-[#2D5A27] hover:bg-gray-50'
                          }`}
                        >
                          <div className="flex items-center gap-3">
                            <div className="w-10 h-10 bg-gradient-to-br from-green-400 to-green-600 rounded-xl flex items-center justify-center">
                              <Leaf className="w-5 h-5 text-white" />
                            </div>
                            <div className="text-left">
                              <p className="font-semibold text-gray-900">{garden.name}</p>
                              <p className="text-xs text-gray-500">{garden.plants?.length || 0} plante(s)</p>
                            </div>
                          </div>
                          {isLoading ? (
                            <Loader2 className="w-5 h-5 animate-spin text-[#2D5A27]" />
                          ) : added ? (
                            <CheckCircle2 className="w-5 h-5 text-green-500" />
                          ) : (
                            <Plus className="w-5 h-5 text-gray-400" />
                          )}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>

              {!loadingGardens && gardens.length > 0 && (
                <div className="px-6 pb-6">
                  <button
                    onClick={() => setShowGardenModal(false)}
                    className="w-full py-2 border border-gray-300 text-gray-700 font-semibold rounded-xl hover:bg-gray-50"
                  >
                    Fermer
                  </button>
                </div>
              )}
            </motion.div>
          </div>
        )}

      </main>
      <Footer />
    </>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-gray-50 rounded-xl p-4">
      <p className="text-xs text-gray-500 font-semibold uppercase tracking-wide mb-1">{label}</p>
      <p className="text-gray-800 font-medium">{value}</p>
    </div>
  );
}

function TagList({ label, items, color }: { label: string; items: string[]; color: string }) {
  const colors: any = {
    red: 'bg-red-100 text-red-700',
    orange: 'bg-orange-100 text-orange-700',
    green: 'bg-green-100 text-green-700',
    blue: 'bg-blue-100 text-blue-700',
  };
  return (
    <div className="mb-4">
      <p className="text-sm font-semibold text-gray-600 mb-2">{label}</p>
      <div className="flex flex-wrap gap-2">
        {items.map((item, i) => (
          <span key={i} className={`px-3 py-1 rounded-full text-sm ${colors[color]}`}>{item}</span>
        ))}
      </div>
    </div>
  );
}

function CareList({ label, items }: { label: string; items: string[] }) {
  return (
    <div className="mb-4">
      <p className="text-sm font-semibold text-gray-600 mb-2">{label}</p>
      <ul className="space-y-1">
        {items.map((item, i) => (
          <li key={i} className="flex items-start gap-2 text-gray-700 text-sm">
            <span className="text-[#2D5A27] mt-0.5">•</span> {item}
          </li>
        ))}
      </ul>
    </div>
  );
}

function Tips({ items }: { items: string[] }) {
  return (
    <div className="mt-4 p-4 bg-green-50 rounded-xl border border-green-200">
      <p className="text-sm font-semibold text-green-700 mb-2">Conseils</p>
      <ul className="space-y-1">
        {items.map((tip, i) => (
          <li key={i} className="text-gray-700 text-sm flex items-start gap-2">
            <span className="text-green-500 mt-0.5">✓</span> {tip}
          </li>
        ))}
      </ul>
    </div>
  );
}
