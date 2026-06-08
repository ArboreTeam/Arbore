'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { getCurrentUser, logout } from '@/lib/authService';
import { API_URL, fetchWithAuth } from '@/lib/api';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { SettingsRow, SectionHeader } from '@/components/shared/SettingsRow';
import { LogOut, Download, ShieldCheck, FileText, Info, Trash2, Loader2, Sparkles } from 'lucide-react';
import { motion } from 'framer-motion';

interface UserProfile {
  uid: string;
  email: string;
  displayName: string;
  photoURL?: string | null;
}

export default function ProfilePage() {
  const [user, setUser] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [exporting, setExporting] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const router = useRouter();

  useEffect(() => {
    const currentUser = getCurrentUser();
    if (!currentUser) {
      router.push('/login');
    } else {
      setUser({
        uid: currentUser.uid,
        email: currentUser.email ?? '',
        displayName: currentUser.displayName ?? '',
        photoURL: currentUser.photoURL,
      });
      setLoading(false);
    }
  }, [router]);

  const handleLogout = async () => {
    try {
      await logout();
      router.push('/');
    } catch (e) {
      console.error('Erreur lors de la déconnexion:', e);
    }
  };

  const handleExport = async () => {
    setExporting(true);
    try {
      const res = await fetchWithAuth(`${API_URL}/users/export`);
      if (!res.ok) throw new Error();
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'arbore-mes-donnees.json';
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      alert('Le téléchargement de vos données a échoué.');
    } finally {
      setExporting(false);
    }
  };

  const handleDelete = async () => {
    if (!confirm('Supprimer définitivement votre compte et toutes vos données ? Cette action est irréversible.')) return;
    setDeleting(true);
    try {
      const res = await fetchWithAuth(`${API_URL}/users`, { method: 'DELETE' });
      if (!res.ok) throw new Error();
      await logout();
      router.push('/');
    } catch {
      alert('La suppression du compte a échoué.');
      setDeleting(false);
    }
  };

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="flex min-h-screen items-center justify-center pt-24">
          <Loader2 className="h-10 w-10 animate-spin text-arbore-green" />
        </div>
        <Footer />
      </>
    );
  }
  if (!user) return null;

  const initial = (user.displayName || user.email || '?').charAt(0).toUpperCase();

  return (
    <>
      <Navbar />
      <main className="min-h-screen bg-background pt-24 pb-16">
        <div className="mx-auto max-w-2xl space-y-7 px-4 sm:px-6">
          {/* En-tête profil */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="arbore-card flex flex-col items-center p-8 text-center"
          >
            <div className="relative">
              {user.photoURL ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={user.photoURL}
                  alt=""
                  className="h-24 w-24 rounded-full object-cover ring-4 ring-white shadow-hero"
                />
              ) : (
                <div className="flex h-24 w-24 items-center justify-center rounded-full bg-gradient-to-br from-arbore-sage to-arbore-green text-4xl font-bold text-white ring-4 ring-white shadow-hero">
                  {initial}
                </div>
              )}
            </div>
            <h1 className="mt-4 font-display text-2xl font-extrabold text-arbore-ink">
              {user.displayName || 'Utilisateur'}
            </h1>
            <p className="mt-1 text-arbore-muted">{user.email}</p>
          </motion.div>

          {/* Plan (bêta gratuite) */}
          <div className="arbore-hero flex items-center gap-4 p-5">
            <div className="flex h-11 w-11 items-center justify-center rounded-[14px] bg-white/15">
              <Sparkles className="h-5 w-5 text-primary-foreground" />
            </div>
            <div className="flex-1">
              <p className="font-display font-bold text-primary-foreground">Bêta gratuite</p>
              <p className="text-sm text-primary-foreground/80">Toutes les fonctionnalités débloquées pendant la bêta.</p>
            </div>
          </div>

          {/* Compte */}
          <section>
            <SectionHeader>Compte</SectionHeader>
            <div className="space-y-3">
              <SettingsRow
                icon={Download}
                tone="success"
                title="Télécharger mes données"
                subtitle="Exportez l'ensemble de vos données (RGPD)"
                onClick={handleExport}
                trailing={exporting ? <Loader2 className="h-4 w-4 animate-spin text-arbore-muted" /> : undefined}
              />
              <SettingsRow icon={Info} tone="muted" title="À propos d'Arbore" href="/about" />
            </div>
          </section>

          {/* Légal */}
          <section>
            <SectionHeader>Confidentialité &amp; mentions légales</SectionHeader>
            <div className="space-y-3">
              <SettingsRow icon={ShieldCheck} tone="sage" title="Politique de confidentialité" href="https://arbore.app/privacy" />
              <SettingsRow icon={FileText} tone="green" title="Conditions d'utilisation" href="https://arbore.app/terms" />
            </div>
          </section>

          {/* Zone danger */}
          <section>
            <SectionHeader>Compte</SectionHeader>
            <div className="space-y-3">
              <SettingsRow
                icon={Trash2}
                danger
                title="Supprimer mon compte"
                subtitle="Efface définitivement votre compte et vos jardins"
                onClick={handleDelete}
                trailing={deleting ? <Loader2 className="h-4 w-4 animate-spin text-arbore-danger" /> : undefined}
              />
              <button
                onClick={handleLogout}
                className="flex w-full items-center justify-center gap-2 rounded-pill bg-arbore-danger py-3.5 font-semibold text-white shadow-soft transition hover:brightness-95 active:scale-[0.98]"
              >
                <LogOut className="h-5 w-5" />
                Se déconnecter
              </button>
            </div>
          </section>

          <p className="pt-2 text-center text-xs text-arbore-muted">Arbore — bêta publique</p>
        </div>
      </main>
      <Footer />
    </>
  );
}
