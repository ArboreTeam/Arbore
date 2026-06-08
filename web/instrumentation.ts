// Next.js instrumentation hook — charge la config Sentry côté serveur/edge.
// (Le client est chargé automatiquement via sentry.client.config.ts.)
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    await import('./sentry.server.config');
  }
  if (process.env.NEXT_RUNTIME === 'edge') {
    await import('./sentry.edge.config');
  }
}
