'use client';

import { useEffect } from 'react';
import Link from 'next/link';
import { AlertTriangle, RotateCcw } from 'lucide-react';
import * as Sentry from '@sentry/nextjs';

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-background px-4 text-center">
      <div className="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-arbore-danger/15">
        <AlertTriangle className="h-9 w-9 text-arbore-danger" />
      </div>
      <h1 className="font-display text-2xl font-bold text-arbore-ink">Une erreur est survenue</h1>
      <p className="mt-2 max-w-sm text-arbore-muted">
        Quelque chose s&apos;est mal passé de notre côté. Réessayez, ou revenez à l&apos;accueil.
      </p>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
        <button onClick={reset} className="btn-arbore px-6 py-3">
          <RotateCcw className="h-5 w-5" />
          Réessayer
        </button>
        <Link href="/" className="btn-arbore-ghost px-6 py-3">
          Accueil
        </Link>
      </div>
    </main>
  );
}
