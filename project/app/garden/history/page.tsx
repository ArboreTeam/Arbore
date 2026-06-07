'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { onAuthStateChange } from '@/lib/authService';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { ArrowLeft, Droplet, Leaf, Trash2, History } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';

interface HistoryEntry {
  key: string;
  plantId: string;
  plantName: string;
  plantType: string;
  imageURL?: string;
  date: string;
  wateredAt: string;
}

function formatDate(dateStr: string) {
  const [year, month, day] = dateStr.split('-').map(Number);
  return new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(year, month - 1, day));
}

function formatTime(isoStr: string) {
  return new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit' }).format(new Date(isoStr));
}

function groupByDate(entries: HistoryEntry[]) {
  const groups: Record<string, HistoryEntry[]> = {};
  for (const e of entries) {
    const day = e.wateredAt.split('T')[0];
    if (!groups[day]) groups[day] = [];
    groups[day].push(e);
  }
  return groups;
}

export default function HistoryPage() {
  const router = useRouter();
  const [history, setHistory] = useState<HistoryEntry[]>([]);

  useEffect(() => {
    const unsubscribe = onAuthStateChange((user) => {
      if (!user) { router.push('/login'); return; }
      try {
        const stored = localStorage.getItem('arbore_history');
        setHistory(stored ? JSON.parse(stored) : []);
      } catch {
        setHistory([]);
      }
    });
    return () => unsubscribe();
  }, [router]);

  const removeEntry = (key: string) => {
    const updated = history.filter((e) => e.key !== key);
    setHistory(updated);
    localStorage.setItem('arbore_history', JSON.stringify(updated));
    // Retirer aussi du set "watered"
    try {
      const watered = JSON.parse(localStorage.getItem('arbore_watered') || '[]');
      localStorage.setItem('arbore_watered', JSON.stringify(watered.filter((k: string) => k !== key)));
    } catch {}
  };

  const clearAll = () => {
    if (!confirm('Effacer tout l\'historique ?')) return;
    setHistory([]);
    localStorage.removeItem('arbore_history');
    localStorage.removeItem('arbore_watered');
  };

  const groups = groupByDate(history);
  const sortedDays = Object.keys(groups).sort((a, b) => b.localeCompare(a));

  return (
    <>
      <Navbar />
      <main className="min-h-screen bg-arbore-beige pt-24 pb-16">
        <div className="max-w-2xl mx-auto px-4 sm:px-6">

          <button
            onClick={() => router.back()}
            className="flex items-center gap-2 text-[#234632] hover:text-[#16291D] font-semibold transition-colors mb-6"
          >
            <ArrowLeft className="w-5 h-5" />
            Retour
          </button>

          <div className="flex items-center justify-between mb-8">
            <div>
              <h1 className="text-4xl font-bold text-[#234632] mb-1">Historique 📋</h1>
              <p className="text-gray-500">Vos arrosages enregistrés</p>
            </div>
            {history.length > 0 && (
              <button
                onClick={clearAll}
                className="flex items-center gap-2 text-sm text-red-400 hover:text-red-600 font-medium transition-colors"
              >
                <Trash2 className="w-4 h-4" />
                Tout effacer
              </button>
            )}
          </div>

          {history.length === 0 ? (
            <div className="text-center py-24">
              <History className="w-16 h-16 text-gray-200 mx-auto mb-4" />
              <p className="text-xl text-gray-400 font-medium">Aucun arrosage enregistré</p>
              <p className="text-gray-400 text-sm mt-2">Cochez vos arrosages dans le calendrier pour les voir ici</p>
              <button
                onClick={() => router.push('/garden/calendar')}
                className="mt-6 bg-[#234632] hover:bg-[#16291D] text-white font-bold py-3 px-8 rounded-full"
              >
                Aller au calendrier
              </button>
            </div>
          ) : (
            <div className="space-y-8">
              <AnimatePresence>
                {sortedDays.map((day) => (
                  <motion.div key={day} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
                    <p className="text-sm font-bold text-gray-400 uppercase tracking-wide mb-3">
                      {formatDate(day)}
                    </p>
                    <div className="space-y-3">
                      {groups[day].map((entry) => (
                        <motion.div
                          key={entry.key}
                          layout
                          exit={{ opacity: 0, x: -20 }}
                          className="bg-white rounded-2xl border border-gray-200 p-4 flex items-center gap-4 shadow-sm"
                        >
                          {entry.imageURL ? (
                            <img src={entry.imageURL} alt={entry.plantName} className="w-12 h-12 rounded-xl object-cover shrink-0" />
                          ) : (
                            <div className="w-12 h-12 rounded-xl bg-green-100 flex items-center justify-center shrink-0">
                              <Leaf className="w-6 h-6 text-green-600" />
                            </div>
                          )}

                          <div className="flex-1 min-w-0">
                            <p className="font-bold text-gray-800 truncate">{entry.plantName}</p>
                            <p className="text-sm text-gray-500">{entry.plantType}</p>
                            <div className="flex items-center gap-1 mt-1 text-xs text-blue-500">
                              <Droplet className="w-3 h-3 fill-current" />
                              <span>Arrosé · {formatDate(entry.date)} à {formatTime(entry.wateredAt)}</span>
                            </div>
                          </div>

                          <button
                            onClick={() => removeEntry(entry.key)}
                            className="p-2 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-400 transition-colors shrink-0"
                            title="Supprimer"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </motion.div>
                      ))}
                    </div>
                  </motion.div>
                ))}
              </AnimatePresence>
            </div>
          )}
        </div>
      </main>
      <Footer />
    </>
  );
}
