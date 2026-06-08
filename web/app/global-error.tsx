'use client';

import { useEffect } from 'react';
import * as Sentry from '@sentry/nextjs';

// Capture les erreurs du root layout lui-même (remplace toute la page) — styles
// inline car la CSS de l'app peut ne pas être chargée à ce niveau.
export default function GlobalError({
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
    <html lang="fr">
      <body
        style={{
          display: 'flex',
          minHeight: '100vh',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          background: '#F0EEEA',
          color: '#1B1F1A',
          fontFamily: 'system-ui, -apple-system, sans-serif',
          textAlign: 'center',
          padding: '1rem',
          margin: 0,
        }}
      >
        <h1 style={{ fontSize: '1.5rem', fontWeight: 700, margin: 0 }}>Une erreur est survenue</h1>
        <p style={{ marginTop: '.5rem', color: '#6E746B' }}>Réessayez, ou rechargez la page.</p>
        <button
          onClick={reset}
          style={{
            marginTop: '1.5rem',
            borderRadius: 999,
            background: '#234632',
            color: '#fff',
            padding: '.75rem 1.5rem',
            fontWeight: 600,
            border: 'none',
            cursor: 'pointer',
          }}
        >
          Réessayer
        </button>
      </body>
    </html>
  );
}
