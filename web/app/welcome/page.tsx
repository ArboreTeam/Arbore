'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { Sprout, Smartphone, Calendar, History, Cloud, Leaf, Zap, Lightbulb, MapPin, Trash2 } from 'lucide-react';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { onAuthStateChange } from '@/lib/authService';
import { API_URL, fetchWithAuth } from '@/lib/api';
import { useRouter } from 'next/navigation';

export default function WelcomePage() {
  const router = useRouter();
  const [userName, setUserName] = useState('');
  const [gardens, setGardens] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [deletingGardenId, setDeletingGardenId] = useState<string | null>(null);

  useEffect(() => {
    // Vérifier l'authentification Firebase
    const unsubscribe = onAuthStateChange((user) => {
      if (user) {
        setUserName(user.displayName || user.email?.split('@')[0] || 'Utilisateur');
        setLoading(false);
        // Récupérer les jardins une fois l'utilisateur chargé
        fetchGardens(user.uid);
      } else {
        // Pas d'utilisateur connecté, rediriger vers login
        router.push('/login');
      }
    });

    return () => unsubscribe();
  }, [router]);

  const fetchGardens = async (uid: string) => {
    try {
      if (!uid) {
        console.error('Pas d\'UID utilisateur trouvé');
        setGardens([]);
        return;
      }

      // Appeler l'API backend
      const response = await fetchWithAuth(`${API_URL}/gardens`);

      if (!response.ok) {
        throw new Error(`Erreur API: ${response.status}`);
      }

      const data = await response.json();
      setGardens(data || []);
    } catch (error) {
      console.error('Erreur lors de la récupération des jardins:', error);
      setGardens([]);
    }
  };

  const quickActions = [
    { icon: Calendar, label: 'Calendrier', description: "Planifier l'entretien", href: '/garden/calendar' },
    { icon: History, label: 'Historique', description: 'Voir mes actions', href: '/garden/history' },
    { icon: Cloud, label: 'Infos Saison', description: 'Conseils saisonniers', href: '/garden/seasons' },
  ];

  const deleteGarden = async (gardenId: string) => {
    if (!confirm('Supprimer ce jardin ? Cette action est irréversible.')) return;
    try {
      const res = await fetchWithAuth(`${API_URL}/gardens/${gardenId}`, { method: 'DELETE' });
      if (!res.ok) throw new Error();
      setGardens((prev) => prev.filter((g: any) => (g._id || g.id) !== gardenId));
    } catch {
      alert('Erreur lors de la suppression du jardin.');
    }
  };

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center pt-24">
          <div className="text-center">
            <div className="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-[#234632]"></div>
            <p className="mt-4 text-arbore-muted">Chargement...</p>
          </div>
        </div>
        <Footer />
      </>
    );
  }

  return (
    <>
      <Navbar />
      <main id="main-content" className="min-h-screen bg-arbore-beige pt-24">
        {/* Welcome Section */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
          >
            <h1 className="text-5xl md:text-6xl font-bold text-[#234632] mb-2">
              Bonjour, {userName} 👋
            </h1>
            <p className="text-xl text-arbore-muted">Sélectionnez un jardin pour commencer</p>
          </motion.div>
        </section>

        {/* Mes Jardins Section */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.2 }}
          >
            <div className="mb-6">
              <h2 className="text-2xl font-bold text-[#234632]">Mes Jardins</h2>
            </div>

            {/* Grid des jardins */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {gardens.map((garden, index) => {
                const gardenId = garden._id || garden.id;
                return (
                  <div key={gardenId} className="relative group">
                    <Link href={`/garden?id=${gardenId}`}>
                      <motion.div
                        initial={{ opacity: 0, y: 20 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.6, delay: 0.1 * index }}
                        whileHover={{ scale: 1.03, y: -5 }}
                        whileTap={{ scale: 0.98 }}
                        className="bg-white rounded-card p-6 shadow-soft hover:shadow-card transition-all border border-border cursor-pointer h-full"
                      >
                        <div className="flex items-start justify-between mb-4">
                          <div className="bg-secondary p-3 rounded-lg">
                            <Sprout className="w-8 h-8 text-[#234632]" />
                          </div>
                          <div className="flex items-center gap-1 text-sm text-arbore-muted">
                            <MapPin className="w-4 h-4" />
                            {garden.wizard?.location || garden.location || 'Non défini'}
                          </div>
                        </div>

                        <h3 className="text-xl font-bold text-arbore-ink mb-2">
                          {garden.name}
                        </h3>
                        <p className="text-sm text-arbore-muted mb-4">
                          {garden.wizard?.description || garden.description || 'Aucune description'}
                        </p>

                        <div className="flex items-center gap-2 text-[#234632] font-semibold">
                          <Leaf className="w-5 h-5" />
                          <span>{garden.plants?.length || 0} plantes</span>
                        </div>
                      </motion.div>
                    </Link>
                    <button
                      onClick={(e) => { e.preventDefault(); deleteGarden(gardenId); }}
                      className="absolute top-3 right-3 p-2 bg-white rounded-lg shadow opacity-0 group-hover:opacity-100 transition-opacity hover:bg-red-50 text-arbore-muted hover:text-red-500"
                      aria-label="Supprimer le jardin"
                      title="Supprimer le jardin"
                    >
                      <Trash2 aria-hidden className="w-4 h-4" />
                    </button>
                  </div>
                );
              })}

              {/* La création de jardin se fait sur iOS (placement en réalité augmentée).
                  Le web sert à consulter / gérer ses jardins. */}
              <div className="rounded-card border-2 border-dashed border-border bg-secondary/40 p-6 flex flex-col items-center justify-center text-center min-h-[200px]">
                <div className="bg-white p-4 rounded-full mb-4 shadow-soft">
                  <Smartphone className="w-9 h-9 text-[#234632]" />
                </div>
                <h3 className="text-lg font-bold text-arbore-ink mb-1">
                  Créez vos jardins sur iPhone
                </h3>
                <p className="text-sm text-arbore-muted">
                  La conception se fait en réalité augmentée dans l&apos;app Arbore.
                  Retrouvez-les ici pour les consulter.
                </p>
              </div>
            </div>
          </motion.div>
        </section>

        {/* Quick Actions */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.3 }}
          >
            <h2 className="text-2xl font-bold text-[#234632] mb-6">Actions rapides</h2>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
              {quickActions.map((action, index) => {
                const IconComponent = action.icon;
                return (
                  <Link key={index} href={action.href}>
                    <motion.div
                      whileHover={{ scale: 1.05 }}
                      whileTap={{ scale: 0.95 }}
                      className="rounded-card p-6 shadow-soft hover:shadow-card transition-shadow border border-border bg-white cursor-pointer h-full flex flex-col items-center text-center"
                    >
                      <IconComponent className="w-12 h-12 mb-4 text-[#234632]" />
                      <h3 className="font-semibold mb-1 text-arbore-ink">{action.label}</h3>
                      <p className="text-sm text-arbore-muted">{action.description}</p>
                    </motion.div>
                  </Link>
                );
              })}
            </div>
          </motion.div>
        </section>

        {/* Featured Section */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.5 }}
          >
            <h2 className="text-2xl font-bold text-[#234632] mb-6">À découvrir</h2>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              {[
                { icon: Leaf, title: 'Diagnostic IA', description: 'Analysez la santé de vos plantes avec notre IA' },
                { icon: Zap, title: 'Rappels intelligents', description: 'Recevez des notifications personnalisées' },
                { icon: Lightbulb, title: 'Conseils experts', description: 'Obtenez des recommandations adaptées' },
              ].map((feature, index) => {
                const IconComponent = feature.icon;
                return (
                  <motion.div
                    key={index}
                    whileHover={{ scale: 1.02 }}
                    className="bg-white rounded-card p-6 shadow-soft border border-border"
                  >
                    <IconComponent className="w-10 h-10 text-[#234632] mb-4" />
                    <h3 className="font-semibold text-arbore-ink mb-2">{feature.title}</h3>
                    <p className="text-sm text-arbore-muted">{feature.description}</p>
                  </motion.div>
                );
              })}
            </div>
          </motion.div>
        </section>

      </main>
      <Footer />
    </>
  );
}

