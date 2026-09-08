// Sentry — configuration serveur (Node runtime), chargée via instrumentation.ts.
// No-op tant qu'aucun DSN n'est défini. Aucune PII.
import * as Sentry from '@sentry/nextjs';

const dsn = process.env.SENTRY_DSN || process.env.NEXT_PUBLIC_SENTRY_DSN;

Sentry.init({
  dsn,
  enabled: !!dsn,
  environment: process.env.NEXT_PUBLIC_SENTRY_ENV || process.env.NODE_ENV,
  tracesSampleRate: 0.1,
  sendDefaultPii: false,

  // Le healthcheck Docker interroge `/health` toutes les 30 s dans chaque
  // conteneur. Sans ce filtre il représenterait l'essentiel du tracing — le
  // relevé avant correction donnait 99,2 % du volume pour l'ancienne cible `/`
  // (#469). Un healthcheck qui réussit n'apprend rien ; s'il échoue, Docker
  // le signale déjà en marquant le conteneur `unhealthy`.
  ignoreTransactions: ['GET /health'],
});
