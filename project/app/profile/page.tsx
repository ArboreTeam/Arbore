'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { getCurrentUser, logout } from '@/lib/authService';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { 
  User, 
  CreditCard, 
  Truck, 
  Settings, 
  Star, 
  HelpCircle,
  LogOut,
  ChevronRight,
  Bell,
  Shield,
  Download
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { motion } from 'framer-motion';

interface UserProfile {
  uid: string;
  email: string;
  displayName: string;
}

export default function ProfilePage() {
  const [user, setUser] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    // Récupérer l'utilisateur actuellement connecté
    const currentUser = getCurrentUser();
    if (!currentUser) {
      router.push('/login');
    } else {
      setUser({
        uid: currentUser.uid,
        email: currentUser.email ?? '',
        displayName: currentUser.displayName ?? '',
      });
      setLoading(false);
    }
  }, [router]);

  const handleLogout = async () => {
    try {
      await logout();
      router.push('/');
    } catch (error) {
      console.error('Erreur lors de la déconnexion:', error);
    }
  };

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center pt-24">
          <div className="text-center">
            <div className="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-[#234632]"></div>
            <p className="mt-4 text-gray-600">Chargement...</p>
          </div>
        </div>
        <Footer />
      </>
    );
  }

  if (!user) {
    return null;
  }

  const stats = [
    { number: '12', label: 'PLANTES', color: 'from-green-400 to-green-600' },
    { number: '8', label: 'SCANS', color: 'from-blue-400 to-blue-600' },
    { number: '3', label: 'RAPPELS', color: 'from-orange-400 to-orange-600' },
  ];

  const menuItems = [
    {
      icon: User,
      title: 'Informations Personnelles',
      description: 'Gérez vos données personnelles',
      color: 'blue',
    },
    {
      icon: Shield,
      title: 'Sécurité',
      description: 'Gérez votre mot de passe et la sécurité',
      color: 'red',
    },
    {
      icon: Settings,
      title: 'Préférences',
      description: 'Personnalisez votre expérience',
      color: 'purple',
    },
    {
      icon: Star,
      title: 'Abonnement',
      description: 'Gérez votre abonnement',
      color: 'yellow',
    },
    {
      icon: HelpCircle,
      title: 'Aide & Support',
      description: 'Besoin d\'aide ? Contactez-nous',
      color: 'green',
    },
  ];

  const colorMap = {
    blue: 'from-blue-500 to-blue-600',
    orange: 'from-orange-500 to-orange-600',
    red: 'from-red-500 to-red-600',
    purple: 'from-purple-500 to-purple-600',
    yellow: 'from-yellow-500 to-yellow-600',
    indigo: 'from-indigo-500 to-indigo-600',
    green: 'from-green-500 to-green-600',
  };

  return (
    <>
      <Navbar />
      <main className="min-h-screen bg-arbore-beige pt-24">
        {/* Profile Header Card */}
        <section className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            className="bg-gradient-to-r from-[#234632] via-green-600 to-[#2F6B46] rounded-3xl shadow-xl p-8 md:p-12 text-white"
          >
            <div className="flex flex-col md:flex-row items-center gap-8">
              {/* Avatar */}
              <div className="flex-shrink-0">
                <div className="w-32 h-32 bg-white bg-opacity-20 rounded-full flex items-center justify-center border-4 border-white shadow-lg backdrop-blur-sm">
                  <div className="text-6xl">
                    {user.displayName.charAt(0).toUpperCase()}
                  </div>
                </div>
              </div>

              {/* User Info */}
              <div className="flex-1 text-center md:text-left">
                <h1 className="text-4xl md:text-5xl font-bold mb-2">
                  {user.displayName || 'Utilisateur'}
                </h1>
                <p className="text-green-100 text-lg mb-4">{user.email}</p>
                <p className="text-green-50 text-sm">
                  ID: <span className="font-mono text-xs">{user.uid}</span>
                </p>
              </div>
            </div>
          </motion.div>
        </section>

        {/* Stats Cards */}
        <section className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.1 }}
            className="grid grid-cols-1 md:grid-cols-3 gap-6"
          >
            {stats.map((stat, index) => (
              <div
                key={index}
                className={`bg-gradient-to-br ${stat.color} rounded-2xl shadow-lg p-8 text-white hover:shadow-xl transition-all transform hover:scale-105`}
              >
                <p className="text-5xl font-bold mb-3">{stat.number}</p>
                <p className="text-sm font-semibold opacity-90 tracking-wider">
                  {stat.label}
                </p>
              </div>
            ))}
          </motion.div>
        </section>

        {/* Menu Items */}
        <section className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.2 }}
          >
            <h2 className="text-3xl font-bold text-[#234632] mb-6">Paramètres du compte</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {menuItems.map((item, index) => {
                const IconComponent = item.icon;
                const gradientColor = colorMap[item.color as keyof typeof colorMap];
                return (
                  <motion.button
                    key={index}
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.5, delay: 0.3 + index * 0.05 }}
                    className="bg-white rounded-2xl shadow-md p-6 hover:shadow-xl transition-all hover:scale-105 text-left group"
                  >
                    <div className="flex items-start gap-4">
                      <div className={`w-14 h-14 bg-gradient-to-br ${gradientColor} rounded-xl flex items-center justify-center flex-shrink-0 shadow-md group-hover:shadow-lg transition-all`}>
                        <IconComponent className="w-7 h-7 text-white" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <h3 className="font-bold text-gray-900 text-lg mb-1 group-hover:text-[#234632] transition-colors">
                          {item.title}
                        </h3>
                        <p className="text-gray-600 text-sm">
                          {item.description}
                        </p>
                      </div>
                      <ChevronRight className="w-5 h-5 text-gray-400 flex-shrink-0 group-hover:text-[#234632] transition-colors mt-1" />
                    </div>
                  </motion.button>
                );
              })}
            </div>
          </motion.div>
        </section>

        {/* Logout Button */}
        <section className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mb-12">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.4 }}
          >
            <button
              onClick={handleLogout}
              className="w-full bg-gradient-to-r from-red-500 to-red-600 hover:from-red-600 hover:to-red-700 text-white font-bold py-4 px-6 rounded-2xl transition-all shadow-lg hover:shadow-xl hover:scale-105 flex items-center justify-center gap-3 text-lg"
            >
              <LogOut className="w-6 h-6" />
              Déconnexion
            </button>
          </motion.div>
        </section>
      </main>
      <Footer />
    </>
  );
}
