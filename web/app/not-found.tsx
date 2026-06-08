import Link from 'next/link';
import { Leaf } from 'lucide-react';

export default function NotFound() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-background px-4 text-center">
      <div className="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-secondary">
        <Leaf className="h-9 w-9 text-arbore-green" />
      </div>
      <p className="font-display text-6xl font-extrabold text-arbore-green">404</p>
      <h1 className="mt-2 font-display text-2xl font-bold text-arbore-ink">Page introuvable</h1>
      <p className="mt-2 max-w-sm text-arbore-muted">
        Cette page n&apos;existe pas ou a été déplacée.
      </p>
      <Link href="/" className="btn-arbore mt-6 px-6 py-3">
        Retour à l&apos;accueil
      </Link>
    </main>
  );
}
