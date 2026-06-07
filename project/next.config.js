const { withSentryConfig } = require('@sentry/nextjs');

/** @type {import('next').NextConfig} */
const nextConfig = {
  eslint: {
    // Le lint s'exécute au build (les erreurs bloquent). Seuls des warnings
    // subsistent (img/next-image, exhaustive-deps) — non bloquants.
    ignoreDuringBuilds: false,
  },
  images: { unoptimized: true },
  // Requis en Next 13.5 pour charger instrumentation.ts (config Sentry serveur/edge).
  experimental: {
    instrumentationHook: true,
  },
};

// withSentryConfig n'échoue pas le build si DSN/authToken sont absents :
// l'upload des source maps est simplement ignoré (utile en local).
module.exports = withSentryConfig(nextConfig, {
  silent: !process.env.CI,
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  authToken: process.env.SENTRY_AUTH_TOKEN,
});
