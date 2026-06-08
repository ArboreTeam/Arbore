// Sentry — configuration navigateur (chargée automatiquement par @sentry/nextjs).
// No-op tant qu'aucun DSN n'est défini (NEXT_PUBLIC_SENTRY_DSN).
// Privacy-first : aucune PII, pas de Session Replay (cohérent avec la posture
// confidentialité du projet). À gater sur le consentement si une bannière est ajoutée.
import * as Sentry from '@sentry/nextjs';

const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

Sentry.init({
  dsn,
  enabled: !!dsn,
  environment: process.env.NEXT_PUBLIC_SENTRY_ENV || process.env.NODE_ENV,
  tracesSampleRate: 0.1,
  sendDefaultPii: false,
  replaysSessionSampleRate: 0,
  replaysOnErrorSampleRate: 0,
});
