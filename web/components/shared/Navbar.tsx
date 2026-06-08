'use client';

import Link from 'next/link';
import { useState, useEffect } from 'react';
import { Menu, X, LogOut, User, Settings, Leaf } from 'lucide-react';
import { onAuthStateChange, logout } from '@/lib/authService';

function Logo() {
  return (
    <div className="flex h-9 w-9 items-center justify-center rounded-[12px] bg-primary shadow-soft">
      <Leaf className="h-5 w-5 text-primary-foreground" />
    </div>
  );
}

export function Navbar() {
  const [isOpen, setIsOpen] = useState(false);
  const [isProfileOpen, setIsProfileOpen] = useState(false);
  const [user, setUser] = useState<any>(null);

  useEffect(() => {
    const unsubscribe = onAuthStateChange((firebaseUser) => setUser(firebaseUser));
    return () => unsubscribe();
  }, []);

  const handleLogout = async () => {
    await logout();
    setUser(null);
    setIsProfileOpen(false);
    window.location.href = '/';
  };

  const initial = (user?.displayName || user?.email || '?').charAt(0).toUpperCase();

  return (
    <nav className="fixed inset-x-0 top-0 z-50 border-b border-border bg-background/80 backdrop-blur-xl">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 items-center justify-between">
          <Link href={user ? '/welcome' : '/'} className="flex items-center gap-2.5">
            <Logo />
            <span className="font-display text-xl font-extrabold text-arbore-green">Arbore</span>
          </Link>

          {/* Non connecté */}
          {!user && (
            <>
              <div className="hidden items-center gap-7 md:flex">
                <Link href="/features" className="text-sm font-semibold text-arbore-muted transition-colors hover:text-arbore-green">
                  Fonctionnalités
                </Link>
                <Link href="/pricing" className="text-sm font-semibold text-arbore-muted transition-colors hover:text-arbore-green">
                  Tarifs
                </Link>
                <Link href="/about" className="text-sm font-semibold text-arbore-muted transition-colors hover:text-arbore-green">
                  À propos
                </Link>
                <Link href="/login" className="btn-arbore-ghost px-5 py-2 text-sm">
                  Connexion
                </Link>
                <Link href="/signup" className="btn-arbore px-5 py-2 text-sm">
                  S&apos;inscrire
                </Link>
              </div>

              <button className="md:hidden" onClick={() => setIsOpen(!isOpen)} aria-label="Menu">
                {isOpen ? <X className="h-6 w-6 text-arbore-green" /> : <Menu className="h-6 w-6 text-arbore-green" />}
              </button>

              {isOpen && (
                <div className="absolute inset-x-0 top-16 space-y-3 border-b border-border bg-background px-4 py-4 md:hidden">
                  <Link href="/features" className="block font-semibold text-arbore-muted hover:text-arbore-green" onClick={() => setIsOpen(false)}>
                    Fonctionnalités
                  </Link>
                  <Link href="/pricing" className="block font-semibold text-arbore-muted hover:text-arbore-green" onClick={() => setIsOpen(false)}>
                    Tarifs
                  </Link>
                  <Link href="/about" className="block font-semibold text-arbore-muted hover:text-arbore-green" onClick={() => setIsOpen(false)}>
                    À propos
                  </Link>
                  <Link href="/login" className="btn-arbore-ghost w-full" onClick={() => setIsOpen(false)}>
                    Connexion
                  </Link>
                  <Link href="/signup" className="btn-arbore w-full" onClick={() => setIsOpen(false)}>
                    S&apos;inscrire
                  </Link>
                </div>
              )}
            </>
          )}

          {/* Connecté */}
          {user && (
            <div className="relative flex items-center gap-4">
              <button
                onClick={() => setIsProfileOpen(!isProfileOpen)}
                className="flex items-center gap-2 rounded-pill px-2 py-1.5 transition-colors hover:bg-secondary"
              >
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-primary">
                  <span className="text-sm font-bold text-primary-foreground">{initial}</span>
                </div>
                <span className="hidden text-sm font-semibold text-arbore-green sm:inline">
                  {user.displayName || user.email}
                </span>
              </button>

              {isProfileOpen && (
                <div className="arbore-card absolute right-0 top-16 w-52 overflow-hidden p-1.5">
                  <Link href="/profile" className="flex items-center gap-3 rounded-[12px] px-3 py-2.5 text-sm font-medium text-arbore-green transition-colors hover:bg-secondary">
                    <User className="h-4 w-4" />
                    <span>Mon profil</span>
                  </Link>
                  <Link href="/settings" className="flex items-center gap-3 rounded-[12px] px-3 py-2.5 text-sm font-medium text-arbore-green transition-colors hover:bg-secondary">
                    <Settings className="h-4 w-4" />
                    <span>Paramètres</span>
                  </Link>
                  <button
                    onClick={handleLogout}
                    className="flex w-full items-center gap-3 rounded-[12px] px-3 py-2.5 text-sm font-medium text-arbore-danger transition-colors hover:bg-arbore-danger/10"
                  >
                    <LogOut className="h-4 w-4" />
                    <span>Déconnexion</span>
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </nav>
  );
}
