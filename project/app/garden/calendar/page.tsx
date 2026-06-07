'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { onAuthStateChange, getFirebaseToken } from '@/lib/authService';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { ChevronLeft, ChevronRight, Droplet, Calendar as CalendarIcon, ArrowLeft, Loader2, Leaf, CheckCircle2, Circle } from 'lucide-react';
import { motion } from 'framer-motion';

const API_URL = '/api/backend';

async function fetchWithAuth(url: string) {
  const token = await getFirebaseToken();
  return fetch(url, {
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
  });
}

// Extrait le nombre de jours entre deux arrosages depuis la chaîne de fréquence
function parseFrequencyDays(frequency: string): number {
  if (!frequency) return 7;
  const f = frequency.toLowerCase();
  if (f.includes('jour')) {
    const match = f.match(/(\d+)/);
    return match ? parseInt(match[1]) : 7;
  }
  if (f.includes('semaine')) {
    const match = f.match(/(\d+)/);
    const timesPerWeek = match ? parseInt(match[1]) : 1;
    return Math.round(7 / timesPerWeek);
  }
  if (f.includes('mois')) {
    return 30;
  }
  return 7;
}

// Génère les dates d'arrosage pour les 3 prochains mois
function generateWateringDates(frequencyDays: number): string[] {
  const dates: string[] = [];
  const today = new Date();
  const end = new Date(today);
  end.setMonth(end.getMonth() + 3);

  const current = new Date(today);
  while (current <= end) {
    dates.push(current.toISOString().split('T')[0]);
    current.setDate(current.getDate() + frequencyDays);
  }
  return dates;
}

interface PlantWithSchedule {
  id: string;
  name: string;
  type: string;
  imageURL?: string;
  frequency: string;
  frequencyDays: number;
  wateringDates: string[];
}

export default function CalendarPage() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [plants, setPlants] = useState<PlantWithSchedule[]>([]);
  const [currentDate, setCurrentDate] = useState(new Date());
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  // clé : "plantId_date"
  const [watered, setWatered] = useState<Set<string>>(() => {
    if (typeof window === 'undefined') return new Set();
    try {
      const stored = localStorage.getItem('arbore_watered');
      return stored ? new Set(JSON.parse(stored)) : new Set();
    } catch { return new Set(); }
  });

  const toggleWatered = (plantId: string, date: string, plantName: string, plantType: string, imageURL?: string) => {
    const key = `${plantId}_${date}`;
    setWatered((prev) => {
      const next = new Set(prev);
      if (next.has(key)) {
        next.delete(key);
        // Retirer de l'historique
        try {
          const history = JSON.parse(localStorage.getItem('arbore_history') || '[]');
          const updated = history.filter((e: any) => e.key !== key);
          localStorage.setItem('arbore_history', JSON.stringify(updated));
        } catch {}
      } else {
        next.add(key);
        // Ajouter à l'historique
        try {
          const history = JSON.parse(localStorage.getItem('arbore_history') || '[]');
          history.unshift({ key, plantId, plantName, plantType, imageURL, date, wateredAt: new Date().toISOString() });
          localStorage.setItem('arbore_history', JSON.stringify(history));
        } catch {}
      }
      localStorage.setItem('arbore_watered', JSON.stringify(Array.from(next)));
      return next;
    });
  };

  const isWatered = (plantId: string, date: string) => watered.has(`${plantId}_${date}`);

  useEffect(() => {
    const unsubscribe = onAuthStateChange(async (user) => {
      if (!user) { router.push('/login'); return; }
      await loadPlants();
    });
    return () => unsubscribe();
  }, [router]);

  const loadPlants = async () => {
    try {
      // Récupérer tous les jardins
      const gardensRes = await fetchWithAuth(`${API_URL}/gardens`);
      if (!gardensRes.ok) return;
      const gardens = await gardensRes.json();

      // Collecter tous les plantIds uniques
      const allPlantIds = new Set<string>();
      for (const garden of (gardens || [])) {
        for (const p of (garden.plants || [])) {
          if (p.plantId) allPlantIds.add(p.plantId);
        }
      }

      if (allPlantIds.size === 0) { setLoading(false); return; }

      // Charger les détails de chaque plante
      const plantDetails = await Promise.all(
        Array.from(allPlantIds).map(async (id) => {
          try {
            const r = await fetchWithAuth(`${API_URL}/plants/${id}`);
            if (!r.ok) return null;
            return await r.json();
          } catch { return null; }
        })
      );

      const result: PlantWithSchedule[] = plantDetails
        .filter(Boolean)
        .map((p: any) => {
          const frequency = p.translations?.fr?.water?.frequency || '';
          const frequencyDays = parseFrequencyDays(frequency);
          return {
            id: p.id || p._id,
            name: p.name,
            type: p.translations?.fr?.plantType || p.type || '',
            imageURL: p.imageURLs?.[0],
            frequency,
            frequencyDays,
            wateringDates: generateWateringDates(frequencyDays),
          };
        });

      setPlants(result);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const getDaysInMonth = (date: Date) => new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();

  const getFirstDayOfMonth = (date: Date) => {
    const day = new Date(date.getFullYear(), date.getMonth(), 1).getDay();
    return day === 0 ? 7 : day;
  };

  const formatDate = (day: number) =>
    `${currentDate.getFullYear()}-${String(currentDate.getMonth() + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;

  const getPlantsToWater = (dateStr: string) =>
    plants.filter((p) => p.wateringDates.includes(dateStr));

  const prevMonth = () => { setCurrentDate(new Date(currentDate.getFullYear(), currentDate.getMonth() - 1)); setSelectedDate(null); };
  const nextMonth = () => { setCurrentDate(new Date(currentDate.getFullYear(), currentDate.getMonth() + 1)); setSelectedDate(null); };

  const daysInMonth = getDaysInMonth(currentDate);
  const firstDay = getFirstDayOfMonth(currentDate);
  const monthNames = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

  const days: (number | null)[] = [];
  for (let i = 1; i < firstDay; i++) days.push(null);
  for (let i = 1; i <= daysInMonth; i++) days.push(i);

  const today = new Date();
  const isCurrentMonth = currentDate.getMonth() === today.getMonth() && currentDate.getFullYear() === today.getFullYear();

  // Stats
  const totalWateringsThisMonth = plants.reduce((acc, p) => {
    const monthStr = `${currentDate.getFullYear()}-${String(currentDate.getMonth() + 1).padStart(2, '0')}`;
    return acc + p.wateringDates.filter((d) => d.startsWith(monthStr)).length;
  }, 0);

  const daysWithWatering = new Set(
    plants.flatMap((p) => {
      const monthStr = `${currentDate.getFullYear()}-${String(currentDate.getMonth() + 1).padStart(2, '0')}`;
      return p.wateringDates.filter((d) => d.startsWith(monthStr));
    })
  ).size;

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

  return (
    <>
      <Navbar />
      <main className="min-h-screen bg-gray-50 pt-24 pb-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {/* Header */}
          <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} className="mb-8">
            <div className="flex items-center gap-4 mb-4">
              <button
                onClick={() => router.back()}
                className="flex items-center gap-2 text-gray-600 hover:text-[#2D5A27] transition-colors"
              >
                <ArrowLeft className="w-5 h-5" />
                Retour
              </button>
            </div>
            <h1 className="text-5xl font-bold text-[#2D5A27] mb-2">Calendrier d'Arrosage 📅</h1>
            <p className="text-lg text-gray-600">Planifiez et suivez l'arrosage de vos plantes</p>
          </motion.div>

          {plants.length === 0 ? (
            <div className="text-center py-20">
              <Leaf className="w-16 h-16 text-gray-200 mx-auto mb-4" />
              <p className="text-xl text-gray-500 mb-2">Aucune plante dans vos jardins</p>
              <p className="text-gray-400 mb-6">Ajoutez des plantes depuis le catalogue pour voir votre calendrier</p>
              <button
                onClick={() => router.push('/garden/catalogue')}
                className="bg-[#2D5A27] hover:bg-[#1f4620] text-white font-bold py-3 px-8 rounded-full"
              >
                Parcourir le catalogue
              </button>
            </div>
          ) : (
            <>
              <div className="grid lg:grid-cols-3 gap-8">
                {/* Calendrier */}
                <motion.div initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} className="lg:col-span-2">
                  <div className="bg-white rounded-2xl shadow-lg p-6 md:p-8">
                    <div className="flex items-center justify-between mb-8">
                      <button onClick={prevMonth} className="p-3 hover:bg-gray-100 rounded-xl transition-colors">
                        <ChevronLeft size={24} className="text-gray-700" />
                      </button>
                      <h2 className="text-2xl md:text-3xl font-bold text-gray-800">
                        {monthNames[currentDate.getMonth()]} {currentDate.getFullYear()}
                      </h2>
                      <button onClick={nextMonth} className="p-3 hover:bg-gray-100 rounded-xl transition-colors">
                        <ChevronRight size={24} className="text-gray-700" />
                      </button>
                    </div>

                    <div className="grid grid-cols-7 gap-2 mb-4">
                      {['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'].map((d) => (
                        <div key={d} className="text-center font-bold text-gray-700 py-2 text-sm">{d}</div>
                      ))}
                    </div>

                    <div className="grid grid-cols-7 gap-2">
                      {days.map((day, index) => {
                        const dateStr = day ? formatDate(day) : null;
                        const plantsToWater = day ? getPlantsToWater(dateStr!) : [];
                        const isToday = day === today.getDate() && isCurrentMonth;
                        const isSelected = selectedDate === dateStr;

                        return (
                          <motion.button
                            key={index}
                            onClick={() => dateStr && setSelectedDate(isSelected ? null : dateStr)}
                            whileHover={{ scale: day ? 1.05 : 1 }}
                            whileTap={{ scale: day ? 0.95 : 1 }}
                            className={`aspect-square p-2 rounded-xl border-2 transition-all flex flex-col items-center justify-center ${
                              !day
                                ? 'bg-gray-50 border-transparent cursor-default'
                                : isSelected
                                ? 'bg-[#2D5A27] border-[#2D5A27] text-white shadow-lg'
                                : isToday
                                ? 'bg-blue-50 border-blue-400 shadow-md'
                                : plantsToWater.length > 0
                                ? 'bg-green-50 border-green-400 hover:border-green-500 hover:shadow-md'
                                : 'bg-white border-gray-200 hover:border-gray-300 hover:shadow-sm'
                            }`}
                          >
                            {day && (
                              <>
                                <span className={`font-bold text-sm ${isSelected ? 'text-white' : 'text-gray-800'}`}>{day}</span>
                                {plantsToWater.length > 0 && (
                                  <div className="mt-0.5 flex items-center gap-0.5">
                                    <Droplet size={10} className={`${isSelected ? 'text-white' : 'text-blue-500'} fill-current`} />
                                    <span className={`text-xs font-semibold ${isSelected ? 'text-white' : 'text-blue-600'}`}>
                                      {plantsToWater.length}
                                    </span>
                                  </div>
                                )}
                              </>
                            )}
                          </motion.button>
                        );
                      })}
                    </div>
                  </div>
                </motion.div>

                {/* Sidebar */}
                <motion.div initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }}>
                  <div className="bg-white rounded-2xl shadow-lg p-8 sticky top-28">
                    <div className="flex items-center gap-2 mb-6">
                      <CalendarIcon className="w-6 h-6 text-[#2D5A27]" />
                      <h3 className="text-xl font-bold text-gray-800">
                        {selectedDate ? 'À arroser ce jour' : 'Sélectionnez une date'}
                      </h3>
                    </div>

                    {selectedDate && getPlantsToWater(selectedDate).length > 0 ? (
                      <div className="space-y-3 max-h-[520px] overflow-y-auto pr-1">
                        {getPlantsToWater(selectedDate).map((plant, idx) => {
                          const done = isWatered(plant.id, selectedDate);
                          return (
                            <motion.div
                              key={plant.id}
                              initial={{ opacity: 0, y: 10 }}
                              animate={{ opacity: 1, y: 0 }}
                              transition={{ delay: idx * 0.08 }}
                              className={`p-5 rounded-xl border transition-all ${done ? 'bg-green-50 border-green-300' : 'bg-white border-gray-200'}`}
                            >
                              <div className="flex items-center gap-3">
                                {plant.imageURL ? (
                                  <img src={plant.imageURL} alt={plant.name} className={`w-10 h-10 rounded-lg object-cover ${done ? 'opacity-50' : ''}`} />
                                ) : (
                                  <div className="w-10 h-10 rounded-lg bg-green-100 flex items-center justify-center">
                                    <Leaf className="w-5 h-5 text-green-600" />
                                  </div>
                                )}
                                <div className="flex-1 min-w-0">
                                  <p className={`font-bold text-base truncate ${done ? 'line-through text-gray-400' : 'text-gray-800'}`}>{plant.name}</p>
                                  <div className="flex items-center gap-1 text-xs text-blue-500 mt-0.5">
                                    <Droplet size={10} className="fill-current" />
                                    <span>{plant.frequency || `Tous les ${plant.frequencyDays} jours`}</span>
                                  </div>
                                </div>
                                <button
                                  onClick={() => toggleWatered(plant.id, selectedDate, plant.name, plant.type, plant.imageURL)}
                                  className="shrink-0 transition-transform hover:scale-110"
                                  title={done ? 'Annuler' : 'Marquer comme arrosé'}
                                >
                                  {done
                                    ? <CheckCircle2 className="w-7 h-7 text-green-500" />
                                    : <Circle className="w-7 h-7 text-gray-300" />
                                  }
                                </button>
                              </div>
                            </motion.div>
                          );
                        })}
                      </div>
                    ) : selectedDate ? (
                      <div className="text-center py-10">
                        <div className="text-5xl mb-3">✅</div>
                        <p className="text-gray-500 font-medium">Aucune plante à arroser ce jour</p>
                      </div>
                    ) : (
                      <div className="text-center py-10">
                        <div className="text-5xl mb-3">👆</div>
                        <p className="text-gray-500 font-medium text-sm">Cliquez sur une date pour voir les plantes à arroser</p>
                      </div>
                    )}

                    {/* Légende */}
                    <div className="mt-6 pt-4 border-t border-gray-200 space-y-2 text-sm">
                      <div className="flex items-center gap-2">
                        <div className="w-5 h-5 rounded bg-blue-50 border-2 border-blue-400" />
                        <span className="text-gray-600">Aujourd'hui</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <div className="w-5 h-5 rounded bg-green-50 border-2 border-green-400 flex items-center justify-center">
                          <Droplet size={10} className="text-blue-500" />
                        </div>
                        <span className="text-gray-600">À arroser</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <div className="w-5 h-5 rounded bg-[#2D5A27]" />
                        <span className="text-gray-600">Sélectionné</span>
                      </div>
                    </div>
                  </div>
                </motion.div>
              </div>

              {/* Stats */}
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.3 }}
                className="mt-10 grid md:grid-cols-3 gap-4"
              >
                <div className="bg-white rounded-2xl border border-gray-200 p-5 flex items-center gap-4 shadow-sm">
                  <div className="w-12 h-12 rounded-xl bg-green-100 flex items-center justify-center shrink-0">
                    <Leaf className="w-6 h-6 text-[#2D5A27]" />
                  </div>
                  <div>
                    <p className="text-3xl font-bold text-gray-900">{plants.length}</p>
                    <p className="text-sm text-gray-500">Plantes suivies</p>
                  </div>
                </div>
                <div className="bg-white rounded-2xl border border-gray-200 p-5 flex items-center gap-4 shadow-sm">
                  <div className="w-12 h-12 rounded-xl bg-blue-100 flex items-center justify-center shrink-0">
                    <Droplet className="w-6 h-6 text-blue-500" />
                  </div>
                  <div>
                    <p className="text-3xl font-bold text-gray-900">{totalWateringsThisMonth}</p>
                    <p className="text-sm text-gray-500">Arrosages ce mois</p>
                  </div>
                </div>
                <div className="bg-white rounded-2xl border border-gray-200 p-5 flex items-center gap-4 shadow-sm">
                  <div className="w-12 h-12 rounded-xl bg-purple-100 flex items-center justify-center shrink-0">
                    <CalendarIcon className="w-6 h-6 text-purple-500" />
                  </div>
                  <div>
                    <p className="text-3xl font-bold text-gray-900">{daysWithWatering}</p>
                    <p className="text-sm text-gray-500">Jours d'arrosage</p>
                  </div>
                </div>
              </motion.div>
            </>
          )}
        </div>
      </main>
      <Footer />
    </>
  );
}
