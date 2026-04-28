'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Sparkles, AlertCircle } from 'lucide-react';
import { login } from '@/lib/authService';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const router = useRouter();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      // Connexion avec Firebase
      const user = await login(email, password);
      
      // Récupérer le nom d'utilisateur (displayName ou email)
      const userName = user.displayName || email.split('@')[0];
      localStorage.setItem('userName', userName);
      localStorage.setItem('userUID', user.uid);

      // Rediriger vers la page de bienvenue
      router.push('/welcome');
    } catch (err: any) {
      setError(err.message || 'Erreur lors de la connexion');
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#2D5A27] to-[#1a3419] flex items-center justify-center px-4 pt-20">
      <div className="w-full max-w-md">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          className="bg-white rounded-2xl shadow-2xl p-8"
        >
          {/* Header */}
          <div className="text-center mb-8">
            <Link href="/" className="flex items-center justify-center gap-2 mb-6">
              <div className="w-10 h-10 bg-[#2D5A27] rounded-full flex items-center justify-center">
                <span className="text-white font-bold text-xl">A</span>
              </div>
              <span className="text-2xl font-bold text-[#2D5A27]">Arbore</span>
            </Link>
            <h1 className="text-3xl font-bold text-[#2D5A27] mb-2">Bienvenue</h1>
            <p className="text-gray-600">Connectez-vous à votre compte</p>
          </div>

          {/* Error Alert */}
          {error && (
            <motion.div
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg flex items-start gap-3"
            >
              <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
              <p className="text-red-800 text-sm">{error}</p>
            </motion.div>
          )}

          {/* Form */}
          <form onSubmit={handleSubmit} className="space-y-5">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Adresse email
              </label>
              <Input
                type="email"
                placeholder="vous@exemple.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-[#2D5A27] focus:border-transparent"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Mot de passe
              </label>
              <Input
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-[#2D5A27] focus:border-transparent"
              />
            </div>

            <div className="flex items-center justify-between text-sm">
              <label className="flex items-center gap-2">
                <input type="checkbox" className="w-4 h-4 text-[#2D5A27] rounded" />
                <span className="text-gray-600">Se souvenir de moi</span>
              </label>
              <a href="#" className="text-[#2D5A27] hover:underline">
                Mot de passe oublié ?
              </a>
            </div>

            <Button
              type="submit"
              disabled={loading}
              className="w-full bg-[#2D5A27] hover:bg-[#234520] text-white rounded-lg py-2 font-medium transition-colors"
            >
              {loading ? 'Connexion en cours...' : 'Se connecter'}
            </Button>
          </form>

          {/* Divider */}
          <div className="my-6 flex items-center gap-4">
            <div className="flex-1 h-px bg-gray-300"></div>
            <span className="text-sm text-gray-500">ou</span>
            <div className="flex-1 h-px bg-gray-300"></div>
          </div>

          {/* Social Login */}
          <div className="space-y-3">
            <Button
              variant="outline"
              className="w-full border-gray-300 text-gray-700 hover:bg-gray-50 rounded-lg py-2"
            >
              Continuer avec Google
            </Button>
          </div>

          {/* Signup Link */}
          <p className="text-center text-gray-600 text-sm mt-6">
            Vous n&apos;avez pas de compte ?{' '}
            <a href="#" className="text-[#2D5A27] font-semibold hover:underline">
              S&apos;inscrire
            </a>
          </p>
        </motion.div>

        {/* Decorative Elements */}
        <div className="absolute -bottom-10 -right-10 w-40 h-40 bg-[#84CC16] rounded-full opacity-10 blur-3xl"></div>
        <div className="absolute -top-10 -left-10 w-40 h-40 bg-[#2D5A27] rounded-full opacity-10 blur-3xl"></div>
      </div>
    </div>
  );
}
