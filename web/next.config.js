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
  images: { unoptimized: true },
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
          // OAuth via signInWithPopup (Google/Apple) : la valeur par défaut du
          // navigateur isole la popup et fait échouer window.close/closed
          // (warnings COOP en console). `same-origin-allow-popups` garde
          // l'isolation cross-origin tout en autorisant le dialogue avec la popup.
          { key: 'Cross-Origin-Opener-Policy', value: 'same-origin-allow-popups' },
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
