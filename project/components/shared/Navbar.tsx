'use client';

import Link from 'next/link';
import { useState, useEffect } from 'react';
import { Menu, X, LogOut, User, Settings } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { onAuthStateChange, logout } from '@/lib/authService';

export function Navbar() {
  const [isOpen, setIsOpen] = useState(false);
  const [isProfileOpen, setIsProfileOpen] = useState(false);
  const [user, setUser] = useState<any>(null);

  useEffect(() => {
    const unsubscribe = onAuthStateChange((firebaseUser) => {
      setUser(firebaseUser);
    });
    return () => unsubscribe();
  }, []);

  const handleLogout = async () => {
    await logout();
    setUser(null);
    setIsProfileOpen(false);
    window.location.href = '/';
  };

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-200">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          <Link href={user ? "/welcome" : "/"} className="flex items-center gap-2">
            <div className="w-8 h-8 bg-[#2D5A27] rounded-full flex items-center justify-center">
              <span className="text-white font-bold text-lg">A</span>
            </div>
            <span className="text-xl font-bold text-[#2D5A27]">Arbore</span>
          </Link>

          {/* Menu non connecté */}
          {!user && (
            <>
              <div className="hidden md:flex items-center gap-8">
                <Link
                  href="/features"
                  className="text-gray-700 hover:text-[#2D5A27] transition-colors"
                >
                  Fonctionnalités
                </Link>
                <Link
                  href="/pricing"
                  className="text-gray-700 hover:text-[#2D5A27] transition-colors"
                >
                  Tarifs
                </Link>
                <Link
                  href="/about"
                  className="text-gray-700 hover:text-[#2D5A27] transition-colors"
                >
                  À propos
                </Link>
                <Link href="/login">
                  <Button variant="outline" className="border-[#2D5A27] text-[#2D5A27] hover:bg-[#2D5A27] hover:text-white rounded-full">
                    Connexion
                  </Button>
                </Link>
                <Link href="/signup">
                  <Button className="bg-[#2D5A27] hover:bg-[#234520] text-white rounded-full">
                    S'inscrire
                  </Button>
                </Link>
              </div>

              <button
                className="md:hidden"
                onClick={() => setIsOpen(!isOpen)}
                aria-label="Toggle menu"
              >
                {isOpen ? (
                  <X className="w-6 h-6 text-gray-700" />
                ) : (
                  <Menu className="w-6 h-6 text-gray-700" />
                )}
              </button>

              {isOpen && (
                <div className="md:hidden absolute top-16 left-0 right-0 bg-white border-b border-gray-200 py-4 px-4 space-y-4">
                  <Link
                    href="/features"
                    className="block text-gray-700 hover:text-[#2D5A27] transition-colors"
                    onClick={() => setIsOpen(false)}
                  >
                    Fonctionnalités
                  </Link>
                  <Link
                    href="/pricing"
                    className="block text-gray-700 hover:text-[#2D5A27] transition-colors"
                    onClick={() => setIsOpen(false)}
                  >
                    Tarifs
                  </Link>
                  <Link
                    href="/about"
                    className="block text-gray-700 hover:text-[#2D5A27] transition-colors"
                    onClick={() => setIsOpen(false)}
                  >
                    À propos
                  </Link>
                  <Link href="/login" onClick={() => setIsOpen(false)} className="w-full block">
                    <Button variant="outline" className="w-full border-[#2D5A27] text-[#2D5A27] hover:bg-[#2D5A27] hover:text-white rounded-full">
                      Connexion
                    </Button>
                  </Link>
                  <Link href="/signup" onClick={() => setIsOpen(false)} className="w-full block">
                    <Button className="w-full bg-[#2D5A27] hover:bg-[#234520] text-white rounded-full">
                      S'inscrire
                    </Button>
                  </Link>
                </div>
              )}
            </>
          )}

          {/* Menu connecté */}
          {user && (
            <div className="flex items-center gap-4 relative">
              <button
                onClick={() => setIsProfileOpen(!isProfileOpen)}
                className="flex items-center gap-2 px-4 py-2 rounded-full hover:bg-gray-100 transition-colors"
              >
                <div className="w-8 h-8 bg-[#2D5A27] rounded-full flex items-center justify-center">
                  <span className="text-white font-bold text-sm">
                    {user.displayName.charAt(0).toUpperCase()}
                  </span>
                </div>
                <span className="text-sm font-medium text-gray-700 hidden sm:inline">
                  {user.displayName}
                </span>
              </button>

              {/* Profile Dropdown */}
              {isProfileOpen && (
                <div className="absolute top-16 right-0 bg-white rounded-lg shadow-lg border border-gray-200 py-2 w-48 z-50">
                  <Link href="/profile" className="flex items-center gap-3 px-4 py-2 text-gray-700 hover:bg-gray-50 transition-colors">
                    <User className="w-4 h-4" />
                    <span>Mon profil</span>
                  </Link>
                  <Link href="/settings" className="flex items-center gap-3 px-4 py-2 text-gray-700 hover:bg-gray-50 transition-colors">
                    <Settings className="w-4 h-4" />
                    <span>Paramètres</span>
                  </Link>
                  <button
                    onClick={handleLogout}
                    className="w-full flex items-center gap-3 px-4 py-2 text-red-600 hover:bg-red-50 transition-colors"
                  >
                    <LogOut className="w-4 h-4" />
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
