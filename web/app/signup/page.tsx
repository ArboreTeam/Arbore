'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { Sprout, AlertCircle, User, Mail, Lock, Loader2 } from 'lucide-react';
import { signUp, signInWithGoogle, signInWithApple } from '@/lib/authService';
import { AppleIcon, GoogleIcon } from '@/components/shared/SocialIcons';

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
      const user = await signUp(email, password, name);
      localStorage.setItem('userName', name);
      localStorage.setItem('userUID', user.uid);
      router.push('/welcome');
    } catch (err: any) {
      setError(err.message || "Erreur lors de l'inscription");
      setLoading(false);
    }
  };

  const handleProvider = async (fn: () => Promise<any>) => {
    setError('');
    try {
      const user = await fn();
      localStorage.setItem('userName', user.displayName || user.email?.split('@')[0] || '');
      localStorage.setItem('userUID', user.uid);
      router.push('/welcome');
    } catch (err: any) {
      if (err?.code === 'auth/popup-closed-by-user' || err?.code === 'auth/cancelled-popup-request') return;
      setError(err?.message || 'Connexion impossible');
    }
  };

  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background px-4 py-12">
      <div className="pointer-events-none absolute -top-24 left-1/2 h-80 w-80 -translate-x-1/2 rounded-full bg-arbore-sage opacity-25 blur-3xl" />

      <motion.div
        initial={{ opacity: 0, y: 24 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="relative w-full max-w-md space-y-5"
      >
        <div className="arbore-hero px-8 py-8 text-center">
          <Link href="/" className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-white/15 backdrop-blur-sm">
            <Sprout className="h-8 w-8 text-primary-foreground" />
          </Link>
          <h1 className="font-display text-3xl font-extrabold text-primary-foreground">Rejoignez Arbore</h1>
          <p className="mt-1 text-primary-foreground/80">Créez votre compte gratuit</p>
        </div>

        <div className="arbore-card p-7">
          {error && (
            <motion.div
              initial={{ opacity: 0, y: -8 }}
              animate={{ opacity: 1, y: 0 }}
              className="mb-5 flex items-start gap-3 rounded-[14px] border border-arbore-danger/30 bg-arbore-danger/10 p-3.5"
            >
              <AlertCircle className="mt-0.5 h-5 w-5 flex-shrink-0 text-arbore-danger" />
              <p className="text-sm text-arbore-danger">{error}</p>
            </motion.div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-arbore-green">Nom complet</label>
              <div className="relative">
                <User className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-arbore-muted" />
                <input type="text" placeholder="Votre nom" value={name} onChange={(e) => setName(e.target.value)} required className="arbore-input pl-10" />
              </div>
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-arbore-green">Adresse email</label>
              <div className="relative">
                <Mail className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-arbore-muted" />
                <input type="email" placeholder="vous@exemple.com" value={email} onChange={(e) => setEmail(e.target.value)} required className="arbore-input pl-10" />
              </div>
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-arbore-green">Mot de passe</label>
              <div className="relative">
                <Lock className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-arbore-muted" />
                <input type="password" placeholder="••••••••" value={password} onChange={(e) => setPassword(e.target.value)} required className="arbore-input pl-10" />
              </div>
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-arbore-green">Confirmer le mot de passe</label>
              <div className="relative">
                <Lock className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-arbore-muted" />
                <input type="password" placeholder="••••••••" value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} required className="arbore-input pl-10" />
              </div>
            </div>

            <button type="submit" disabled={loading} className="btn-arbore w-full">
              {loading ? <Loader2 className="h-5 w-5 animate-spin" /> : "S'inscrire"}
            </button>
          </form>

          <div className="my-5 flex items-center gap-4">
            <div className="h-px flex-1 bg-border" />
            <span className="text-sm text-arbore-muted">ou</span>
            <div className="h-px flex-1 bg-border" />
          </div>

          <div className="space-y-3">
            <button onClick={() => handleProvider(signInWithApple)} className="flex w-full items-center justify-center gap-2.5 rounded-pill bg-arbore-ink py-3 font-semibold text-white transition active:scale-[0.98]">
              <AppleIcon className="h-5 w-5" />
              Continuer avec Apple
            </button>
            <button onClick={() => handleProvider(signInWithGoogle)} className="flex w-full items-center justify-center gap-2.5 rounded-pill border border-border bg-card py-3 font-semibold text-arbore-ink transition hover:bg-secondary active:scale-[0.98]">
              <GoogleIcon className="h-5 w-5" />
              Continuer avec Google
            </button>
          </div>

          <p className="mt-6 text-center text-sm text-arbore-muted">
            Déjà un compte ?{' '}
            <Link href="/login" className="font-semibold text-arbore-green hover:underline">Se connecter</Link>
          </p>
        </div>
      </motion.div>
    </main>
  );
}
