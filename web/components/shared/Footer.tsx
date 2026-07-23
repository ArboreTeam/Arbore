import Link from 'next/link';
import { Instagram, Linkedin, Github, Leaf } from 'lucide-react';

export function Footer() {
  return (
    <footer className="bg-primary text-primary-foreground">
      <div className="mx-auto max-w-7xl px-4 py-14 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 gap-10 md:grid-cols-4">
          <div>
            <div className="mb-4 flex items-center gap-2.5">
              <div className="flex h-9 w-9 items-center justify-center rounded-[12px] bg-white/15">
                <Leaf className="h-5 w-5 text-primary-foreground" />
              </div>
              <span className="font-display text-xl font-extrabold">Arbore</span>
            </div>
            <p className="text-sm text-primary-foreground/70">
              Cultivez en harmonie. 🌱
            </p>
          </div>

          <div>
            <h3 className="mb-4 font-display font-bold">Navigation</h3>
            <ul className="space-y-2.5 text-sm">
              <li><Link href="/features" className="text-primary-foreground/70 transition-colors hover:text-primary-foreground">Fonctionnalités</Link></li>
              <li><Link href="/pricing" className="text-primary-foreground/70 transition-colors hover:text-primary-foreground">Tarifs</Link></li>
              <li><Link href="/about" className="text-primary-foreground/70 transition-colors hover:text-primary-foreground">À propos</Link></li>
            </ul>
          </div>

          <div>
            <h3 className="mb-4 font-display font-bold">Légal</h3>
            <ul className="space-y-2.5 text-sm">
              <li><a href="https://arbore.app/terms" className="text-primary-foreground/70 transition-colors hover:text-primary-foreground">Conditions d&apos;utilisation</a></li>
              <li><a href="https://arbore.app/privacy" className="text-primary-foreground/70 transition-colors hover:text-primary-foreground">Confidentialité</a></li>
            </ul>
          </div>

          <div>
            <h3 className="mb-4 font-display font-bold">Suivez-nous</h3>
            <div className="flex gap-3">
              {[Instagram, Linkedin, Github].map((Icon, i) => (
                <a
                  key={i}
                  href="#"
                  className="flex h-10 w-10 items-center justify-center rounded-full bg-white/10 transition-colors hover:bg-white/20"
                >
                  <Icon className="h-5 w-5" />
                </a>
              ))}
            </div>
          </div>
        </div>

        <div className="mt-10 border-t border-white/15 pt-8 text-center text-sm text-primary-foreground/70">
          <p>&copy; {new Date().getFullYear()} Arbore.</p>
        </div>
      </div>
    </footer>
  );
}
