'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { onAuthStateChange } from '@/lib/authService';
import { API_URL, fetchWithAuth } from '@/lib/api';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { ArrowLeft, Sparkles, Loader2, CheckCircle2, AlertCircle } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { useEffect } from 'react';

type Status = 'idle' | 'loading' | 'success' | 'exists' | 'error';

export default function GeneratePage() {
  const router = useRouter();
  const [plantName, setPlantName] = useState('');
  const [status, setStatus] = useState<Status>('idle');
  const [generatedPlant, setGeneratedPlant] = useState<any>(null);

  useEffect(() => {
    const unsubscribe = onAuthStateChange((user) => {
      if (!user) router.push('/login');
    });
    return () => unsubscribe();
  }, [router]);

  const handleGenerate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!plantName.trim()) return;

    setStatus('loading');
    setGeneratedPlant(null);

    try {
      const response = await fetchWithAuth(`${API_URL}/plants/generate`, {
        method: 'POST',
        body: JSON.stringify({ name: plantName.trim() }),
      });

      if (response.status === 409) {
        setStatus('exists');
        return;
      }

      if (!response.ok) throw new Error();

      const data = await response.json();
      setGeneratedPlant(data.plant);
      setStatus('success');
    } catch {
      setStatus('error');
    }
  };

  const loadingMessages = [
    'Consultation de l\'IA...',
    'Génération des informations...',
    'Recherche des images...',
    'Sauvegarde dans la base...',
  ];
  const [msgIndex, setMsgIndex] = useState(0);

  useEffect(() => {
    if (status !== 'loading') return;
    const interval = setInterval(() => {
      setMsgIndex((i) => (i + 1) % loadingMessages.length);
    }, 2000);
    return () => clearInterval(interval);
  }, [status]);

  return (
    <>
      <Navbar />
      <main className="min-h-screen bg-arbore-beige pt-24 pb-16">
        <div className="max-w-2xl mx-auto px-4 sm:px-6">

          {/* Retour */}
          <button
            onClick={() => router.back()}
            className="flex items-center gap-2 text-[#234632] hover:text-[#16291D] font-semibold transition-colors mb-8"
          >
            <ArrowLeft className="w-5 h-5" />
            Retour
          </button>

          {/* Header */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="text-center mb-10"
          >
            <div className="w-16 h-16 bg-gradient-to-br from-purple-500 to-indigo-600 rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-lg">
              <Sparkles className="w-8 h-8 text-white" />
            </div>
            <h1 className="text-3xl font-bold text-gray-900 mb-2">Générer une plante avec l'IA</h1>
            <p className="text-gray-500">Entrez le nom d'une plante et l'IA génère automatiquement toutes ses informations</p>
          </motion.div>

          {/* Formulaire */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1 }}
            className="bg-white rounded-2xl shadow-md p-8 mb-6"
          >
            <form onSubmit={handleGenerate} className="space-y-4">
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-2">
                  Nom de la plante
                </label>
                <input
                  type="text"
                  value={plantName}
                  onChange={(e) => { setPlantName(e.target.value); setStatus('idle'); }}
                  placeholder="Ex: Monstera, Cactus, Orchidée..."
                  disabled={status === 'loading'}
                  className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-500 disabled:opacity-50 text-lg"
                />
              </div>
              <button
                type="submit"
                disabled={status === 'loading' || !plantName.trim()}
                className="w-full py-3 bg-gradient-to-r from-purple-500 to-indigo-600 hover:from-purple-600 hover:to-indigo-700 disabled:opacity-50 text-white font-bold rounded-xl shadow-md hover:shadow-lg transition-all flex items-center justify-center gap-2"
              >
                {status === 'loading' ? (
                  <Loader2 className="w-5 h-5 animate-spin" />
                ) : (
                  <Sparkles className="w-5 h-5" />
                )}
                {status === 'loading' ? 'Génération en cours...' : 'Générer avec l\'IA'}
              </button>
            </form>
          </motion.div>

          {/* États */}
          <AnimatePresence mode="wait">

            {/* Loading */}
            {status === 'loading' && (
              <motion.div
                key="loading"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                className="bg-purple-50 border border-purple-200 rounded-2xl p-6 text-center"
              >
                <Loader2 className="w-10 h-10 animate-spin text-purple-500 mx-auto mb-3" />
                <p className="text-purple-700 font-semibold">{loadingMessages[msgIndex]}</p>
                <p className="text-purple-500 text-sm mt-1">Cela peut prendre 10-20 secondes</p>
              </motion.div>
            )}

            {/* Succès */}
            {status === 'success' && generatedPlant && (
              <motion.div
                key="success"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                className="bg-white rounded-2xl shadow-md overflow-hidden"
              >
                {/* Image */}
                <div className="h-48 bg-gradient-to-br from-green-400 to-green-600 relative">
                  {generatedPlant.imageURLs?.[0] && (
                    <img
                      src={generatedPlant.imageURLs[0]}
                      alt={generatedPlant.name}
                      className="w-full h-full object-cover"
                    />
                  )}
                  <div className="absolute top-4 left-4">
                    <span className="bg-green-500 text-white px-3 py-1 rounded-full text-sm font-bold flex items-center gap-1">
                      <CheckCircle2 className="w-4 h-4" /> Générée avec succès !
                    </span>
                  </div>
                </div>

                <div className="p-6">
                  <h2 className="text-2xl font-bold text-gray-900 mb-1">{generatedPlant.name}</h2>
                  <p className="text-gray-500 mb-3">{generatedPlant.translations?.fr?.plantType || generatedPlant.type}</p>
                  {generatedPlant.translations?.fr?.description && (
                    <p className="text-gray-600 text-sm line-clamp-3 mb-6">{generatedPlant.translations.fr.description}</p>
                  )}
                  <div className="flex gap-3">
                    <button
                      onClick={() => router.push(`/garden/plant/${generatedPlant.id}?from=catalogue`)}
                      className="flex-1 py-3 bg-[#234632] hover:bg-[#16291D] text-white font-bold rounded-xl transition-all"
                    >
                      Voir la fiche complète
                    </button>
                    <button
                      onClick={() => { setPlantName(''); setStatus('idle'); setGeneratedPlant(null); }}
                      className="flex-1 py-3 border border-gray-300 text-gray-700 font-semibold rounded-xl hover:bg-arbore-beige transition-all"
                    >
                      Générer une autre
                    </button>
                  </div>
                </div>
              </motion.div>
            )}

            {/* Déjà existante */}
            {status === 'exists' && (
              <motion.div
                key="exists"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                className="bg-blue-50 border border-blue-200 rounded-2xl p-6 text-center"
              >
                <CheckCircle2 className="w-10 h-10 text-blue-500 mx-auto mb-3" />
                <p className="text-blue-700 font-semibold">Cette plante existe déjà dans le catalogue !</p>
                <p className="text-blue-500 text-sm mt-1 mb-4">Retrouvez-la dans le catalogue</p>
                <button
                  onClick={() => router.push('/garden/catalogue')}
                  className="px-6 py-2 bg-blue-500 hover:bg-blue-600 text-white font-semibold rounded-xl transition-all"
                >
                  Voir le catalogue
                </button>
              </motion.div>
            )}

            {/* Erreur */}
            {status === 'error' && (
              <motion.div
                key="error"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                className="bg-red-50 border border-red-200 rounded-2xl p-6 text-center"
              >
                <AlertCircle className="w-10 h-10 text-red-400 mx-auto mb-3" />
                <p className="text-red-700 font-semibold">Erreur lors de la génération</p>
                <p className="text-red-500 text-sm mt-1">Vérifiez que le service IA est bien lancé</p>
              </motion.div>
            )}

          </AnimatePresence>
        </div>
      </main>
      <Footer />
    </>
  );
}
