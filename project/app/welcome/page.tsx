'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Sprout, Plus, Calendar, History, Cloud, Leaf, Zap, Lightbulb, MapPin, Sparkles, Trash2 } from 'lucide-react';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { getCurrentUser, onAuthStateChange, getFirebaseToken } from '@/lib/authService';
import { useRouter } from 'next/navigation';

export default function WelcomePage() {
  const router = useRouter();
  const [userName, setUserName] = useState('');
  const [gardens, setGardens] = useState<any[]>([]);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [currentUser, setCurrentUser] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [deletingGardenId, setDeletingGardenId] = useState<string | null>(null);

  useEffect(() => {
    // Vérifier l'authentification Firebase
    const unsubscribe = onAuthStateChange((user) => {
      if (user) {
        setCurrentUser(user);
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
      const token = await getFirebaseToken();
      const response = await fetch(`/api/backend/gardens`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
      });

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
    { icon: Sparkles, label: 'Générer avec l\'IA', description: 'Ajouter une plante via IA', href: '/garden/generate', highlight: true },
  ];

  const deleteGarden = async (gardenId: string) => {
    if (!confirm('Supprimer ce jardin ? Cette action est irréversible.')) return;
    try {
      const token = await getFirebaseToken();
      const res = await fetch(`/api/backend/gardens/${gardenId}`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
      });
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
            <div className="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-[#2D5A27]"></div>
            <p className="mt-4 text-gray-600">Chargement...</p>
          </div>
        </div>
        <Footer />
      </>
    );
  }

  return (
    <>
      <Navbar />
      <main className="min-h-screen bg-gray-50 pt-24">
        {/* Welcome Section */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
          >
            <h1 className="text-5xl md:text-6xl font-bold text-[#2D5A27] mb-2">
              Bonjour, {userName} 👋
            </h1>
            <p className="text-xl text-gray-600">Sélectionnez un jardin pour commencer</p>
          </motion.div>
        </section>

        {/* Mes Jardins Section */}
        <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.2 }}
          >
            <div className="flex justify-between items-center mb-6">
              <h2 className="text-2xl font-bold text-[#2D5A27]">Mes Jardins</h2>
              <Button
                onClick={() => setShowCreateModal(true)}
                className="bg-[#2D5A27] hover:bg-[#234520] text-white rounded-lg px-6 flex items-center gap-2"
              >
                <Plus className="w-5 h-5" />
                Créer un jardin
              </Button>
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
                        className="bg-white rounded-xl p-6 shadow-sm hover:shadow-lg transition-all border border-gray-200 cursor-pointer h-full"
                      >
                        <div className="flex items-start justify-between mb-4">
                          <div className="bg-green-100 p-3 rounded-lg">
                            <Sprout className="w-8 h-8 text-[#2D5A27]" />
                          </div>
                          <div className="flex items-center gap-1 text-sm text-gray-500">
                            <MapPin className="w-4 h-4" />
                            {garden.wizard?.location || garden.location || 'Non défini'}
                          </div>
                        </div>

                        <h3 className="text-xl font-bold text-gray-900 mb-2">
                          {garden.name}
                        </h3>
                        <p className="text-sm text-gray-600 mb-4">
                          {garden.wizard?.description || garden.description || 'Aucune description'}
                        </p>

                        <div className="flex items-center gap-2 text-[#2D5A27] font-semibold">
                          <Leaf className="w-5 h-5" />
                          <span>{garden.plants?.length || 0} plantes</span>
                        </div>
                      </motion.div>
                    </Link>
                    <button
                      onClick={(e) => { e.preventDefault(); deleteGarden(gardenId); }}
                      className="absolute top-3 right-3 p-2 bg-white rounded-lg shadow opacity-0 group-hover:opacity-100 transition-opacity hover:bg-red-50 text-gray-400 hover:text-red-500"
                      title="Supprimer le jardin"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                );
              })}

              {/* Carte pour créer un nouveau jardin */}
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.6, delay: 0.1 * gardens.length }}
                whileHover={{ scale: 1.03, y: -5 }}
                whileTap={{ scale: 0.98 }}
                onClick={() => setShowCreateModal(true)}
                className="bg-gradient-to-br from-green-50 to-green-100 rounded-xl p-6 shadow-sm hover:shadow-lg transition-all border-2 border-dashed border-[#2D5A27] cursor-pointer h-full flex flex-col items-center justify-center text-center min-h-[200px]"
              >
                <div className="bg-white p-4 rounded-full mb-4">
                  <Plus className="w-10 h-10 text-[#2D5A27]" />
                </div>
                <h3 className="text-xl font-bold text-[#2D5A27] mb-2">
                  Créer un nouveau jardin
                </h3>
                <p className="text-sm text-gray-600">
                  Ajoutez un espace pour vos plantes
                </p>
              </motion.div>
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
            <h2 className="text-2xl font-bold text-[#2D5A27] mb-6">Actions rapides</h2>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
              {quickActions.map((action, index) => {
                const IconComponent = action.icon;
                return (
                  <Link key={index} href={action.href}>
                    <motion.div
                      whileHover={{ scale: 1.05 }}
                      whileTap={{ scale: 0.95 }}
                      className={`rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow border cursor-pointer h-full flex flex-col items-center text-center ${
                        action.highlight
                          ? 'bg-gradient-to-br from-purple-50 to-indigo-50 border-purple-200'
                          : 'bg-white border-gray-200'
                      }`}
                    >
                      <IconComponent className={`w-12 h-12 mb-4 ${action.highlight ? 'text-purple-500' : 'text-[#2D5A27]'}`} />
                      <h3 className={`font-semibold mb-1 ${action.highlight ? 'text-purple-700' : 'text-gray-900'}`}>{action.label}</h3>
                      <p className="text-sm text-gray-600">{action.description}</p>
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
            <h2 className="text-2xl font-bold text-[#2D5A27] mb-6">À découvrir</h2>
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
                    className="bg-white rounded-xl p-6 shadow-sm border border-gray-200"
                  >
                    <IconComponent className="w-10 h-10 text-[#2D5A27] mb-4" />
                    <h3 className="font-semibold text-gray-900 mb-2">{feature.title}</h3>
                    <p className="text-sm text-gray-600">{feature.description}</p>
                  </motion.div>
                );
              })}
            </div>
          </motion.div>
        </section>

        {/* Modal de création de jardin */}
        {showCreateModal && currentUser && (
          <CreateGardenModal
            onClose={() => setShowCreateModal(false)}
            onSuccess={() => {
              setShowCreateModal(false);
              fetchGardens(currentUser.uid);
            }}
            uid={currentUser.uid}
          />
        )}
      </main>
      <Footer />
    </>
  );
}

// Composant Modal pour créer un jardin
function CreateGardenModal({ onClose, onSuccess, uid }: { onClose: () => void; onSuccess: () => void; uid: string }) {
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    location: 'Intérieur/Extérieur',
  });
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);

    try {
      if (!uid) {
        alert('Erreur: Utilisateur non connecté');
        setIsSubmitting(false);
        return;
      }

      // Préparer les données pour l'API
      const gardenData = {
        uid: uid,
        name: formData.name,
        wizard: {
          description: formData.description,
          location: formData.location,
        },
        plants: [],
      };

      // Appeler l'API backend
      const token = await getFirebaseToken();
      const response = await fetch('/api/backend/gardens', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify(gardenData),
      });

      if (!response.ok) {
        throw new Error(`Erreur API: ${response.status}`);
      }

      const result = await response.json();
      console.log('Jardin créé:', result);
      
      // Succès - fermer la modale et recharger les jardins
      onSuccess();
    } catch (error) {
      console.error('Erreur lors de la création du jardin:', error);
      alert('Erreur lors de la création du jardin.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <motion.div
        initial={{ opacity: 0, scale: 0.9 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-white rounded-2xl max-w-md w-full p-8 shadow-2xl"
      >
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-2xl font-bold text-[#2D5A27]">Créer un jardin</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 text-2xl"
          >
            ×
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">
              Nom du jardin *
            </label>
            <input
              type="text"
              required
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-[#2D5A27] focus:border-transparent"
              placeholder="Mon jardin principal"
            />
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">
              Description
            </label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-[#2D5A27] focus:border-transparent"
              placeholder="Décrivez votre jardin..."
              rows={3}
            />
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">
              Localisation
            </label>
            <select
              value={formData.location}
              onChange={(e) => setFormData({ ...formData, location: e.target.value })}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-[#2D5A27] focus:border-transparent"
            >
              <option value="Intérieur">Intérieur</option>
              <option value="Extérieur">Extérieur</option>
              <option value="Intérieur/Extérieur">Intérieur/Extérieur</option>
            </select>
          </div>

          <div className="flex gap-4">
            <Button
              type="button"
              onClick={onClose}
              className="flex-1 bg-gray-200 hover:bg-gray-300 text-gray-700 rounded-lg"
            >
              Annuler
            </Button>
            <Button
              type="submit"
              disabled={isSubmitting}
              className="flex-1 bg-[#2D5A27] hover:bg-[#234520] text-white rounded-lg"
            >
              {isSubmitting ? 'Création...' : 'Créer'}
            </Button>
          </div>
        </form>
      </motion.div>
    </div>
  );
}