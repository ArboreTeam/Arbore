'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Sparkles, AlertCircle } from 'lucide-react';
import { signUp } from '@/lib/authService';

export default function SignupPage() {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const router = useRouter();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    // Validation
    if (!name || !email || !password || !confirmPassword) {
      setError('Tous les champs sont obligatoires');
      return;
    }

    if (password !== confirmPassword) {
      setError('Les mots de passe ne correspondent pas');
      return;
    }

    if (password.length < 6) {
      setError('Le mot de passe doit contenir au moins 6 caractères');
      return;
    }

    setLoading(true);

    try {
      // Inscription avec Firebase
      const user = await signUp(email, password, name);

      // Sauvegarder les infos utilisateur
      localStorage.setItem('userName', name);
      localStorage.setItem('userUID', user.uid);

      // Rediriger vers la page de bienvenue
      router.push('/welcome');
    } catch (err: any) {
      setError(err.message || 'Erreur lors de l\'inscription');
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#2D5A27] to-[#1a3419] flex items-center justify-center px-4 pt-20">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.6 }}
        className="max-w-md w-full"
      >
        <div className="bg-white/95 backdrop-blur rounded-2xl shadow-2xl p-8">
          {/* Header */}
          <div className="text-center mb-8">
            <Link href="/" className="flex items-center justify-center gap-2 mb-6">
              <div className="w-10 h-10 bg-[#2D5A27] rounded-full flex items-center justify-center">
                <span className="text-white font-bold text-xl">A</span>
              </div>
              <span className="text-2xl font-bold text-[#2D5A27]">Arbore</span>
            </Link>
            <h1 className="text-3xl font-bold text-[#2D5A27] mb-2">S'inscrire</h1>
            <p className="text-gray-600">Rejoignez la communauté Arbore</p>
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
                Nom complet
              </label>
              <Input
                type="text"
                placeholder="Votre nom"
                value={name}
                onChange={(e) => setName(e.target.value)}
                required
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-[#2D5A27] focus:border-transparent"
              />
            </div>

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

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Confirmer le mot de passe
              </label>
              <Input
                type="password"
                placeholder="••••••••"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-[#2D5A27] focus:border-transparent"
              />
            </div>

            <Button
              type="submit"
              disabled={loading}
              className="w-full bg-[#2D5A27] hover:bg-[#234520] text-white rounded-lg py-2 font-medium transition-colors"
            >
              {loading ? 'Inscription en cours...' : 'S\'inscrire'}
            </Button>
          </form>

          {/* Login Link */}
          <p className="text-center text-gray-600 text-sm mt-6">
            Vous avez déjà un compte ?{' '}
            <Link href="/login" className="text-[#2D5A27] font-semibold hover:underline">
              Se connecter
            </Link>
          </p>
        </div>
      </motion.div>
    </div>
  );
}
