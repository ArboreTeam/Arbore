import './globals.css';
import type { Metadata } from 'next';
import { Nunito } from 'next/font/google';
import { OfflineBanner } from '@/components/shared/OfflineBanner';

// Police d'affichage arrondie et chaleureuse (proche de SF Rounded utilisé par l'app iOS).
// Le corps de texte utilise la pile système (-apple-system…) = SF sur les appareils Apple.
const display = Nunito({
  subsets: ['latin'],
  weight: ['600', '700', '800'],
  variable: '--font-display',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Arbore — Composez le jardin de vos rêves',
  description:
    'Concevez votre jardin en réalité augmentée, recevez des suggestions de plantes et gardez chaque plante en pleine forme.',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr" className={display.variable}>
      <body>
        <a
          href="#main-content"
          className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[80] focus:rounded-pill focus:bg-primary focus:px-4 focus:py-2 focus:font-semibold focus:text-primary-foreground focus:shadow-hero"
        >
          Aller au contenu principal
        </a>
        <OfflineBanner />
        {children}
      </body>
    </html>
  );
}
