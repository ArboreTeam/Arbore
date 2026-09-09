// Sentry — configuration serveur (Node runtime), chargée via instrumentation.ts.
// No-op tant qu'aucun DSN n'est défini. Aucune PII.
import * as Sentry from '@sentry/nextjs';

const dsn = process.env.SENTRY_DSN || process.env.NEXT_PUBLIC_SENTRY_DSN;

Sentry.init({
  dsn,
  enabled: !!dsn,
  // `SENTRY_ENVIRONMENT` D'ABORD, et c'est tout l'objet du correctif (#469).
  //
  // `NEXT_PUBLIC_SENTRY_ENV` est inliné À LA COMPILATION par Next.js : la valeur
  // posée sur le conteneur n'a aucun effet, le code compilé ne lit plus
  // `process.env`. `web/.env` la laissant vide, le repli tombait sur `NODE_ENV`
  // — `production` dans tout build Next. Prod et dev remontaient donc sous la
  // même étiquette, indistinguables.
  //
  // Ce fichier tourne côté serveur, au runtime : une variable NON préfixée
  // `NEXT_PUBLIC_` y est lue à l'exécution. Une seule image sert donc les deux
  // environnements, chacun s'étiquetant lui-même.
  environment:
    process.env.SENTRY_ENVIRONMENT ||
    process.env.NEXT_PUBLIC_SENTRY_ENV ||
    process.env.NODE_ENV,
  tracesSampleRate: 0.1,
  sendDefaultPii: false,

  // Le healthcheck Docker interroge `/health` toutes les 30 s dans chaque
  // conteneur. Sans ce filtre il représenterait l'essentiel du tracing — le
  // relevé avant correction donnait 99,2 % du volume pour l'ancienne cible `/`
  // (#469). Un healthcheck qui réussit n'apprend rien ; s'il échoue, Docker
  // le signale déjà en marquant le conteneur `unhealthy`.
  ignoreTransactions: ['GET /health'],
});
