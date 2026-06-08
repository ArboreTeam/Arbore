const { withSentryConfig } = require('@sentry/nextjs');
const pkg = require('./package.json');

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Version de l'app exposée au bundle (affichée dans les paramètres). #23
  env: {
    NEXT_PUBLIC_APP_VERSION: pkg.version,
  },
  // Sortie autonome (server.js + node_modules minimal) → image Docker légère.
  output: 'standalone',
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
  poweredByHeader: false,
  // En-têtes de sécurité appliqués à toutes les routes.
  // (CSP volontairement absente ici : à ajouter en Report-Only puis enforce
  //  après recensement des sources Firebase/Sentry/Unsplash — cf. audit sécu.)
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Strict-Transport-Security', value: 'max-age=31536000' },
          {
            key: 'Permissions-Policy',
            value: 'camera=(), microphone=(), geolocation=(), browsing-topics=()',
          },
        ],
      },
    ];
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
