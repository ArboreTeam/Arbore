// Sentry — configuration navigateur (chargée automatiquement par @sentry/nextjs).
// No-op tant qu'aucun DSN n'est défini (NEXT_PUBLIC_SENTRY_DSN).
// Privacy-first : aucune PII, pas de Session Replay (cohérent avec la posture
// confidentialité du projet). À gater sur le consentement si une bannière est ajoutée.
import * as Sentry from '@sentry/nextjs';

const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

Sentry.init({
  dsn,
  enabled: !!dsn,
  // ⚠️ Limite connue et assumée (#469). Contrairement aux configs serveur et
  // edge, ce fichier est exécuté par le NAVIGATEUR : il ne peut pas lire une
  // variable d'environnement au runtime. Next.js inline les `NEXT_PUBLIC_*` à la
  // compilation, donc l'étiquette est figée dans l'image — et comme `web/.env`
  // laisse la valeur vide, le repli `NODE_ENV` donne `production` partout.
  //
  // Conséquence : les erreurs NAVIGATEUR d'un web de dev seraient étiquetées
  // `production`. C'est sans effet aujourd'hui — sur 90 jours, le projet n'a
  // reçu aucune transaction de navigateur (`pageload`, `navigation`) : tout le
  // volume vient du serveur, et le serveur s'étiquette correctement depuis ce
  // correctif.
  //
  // Y remédier exigerait une image par environnement, ou l'injection de la
  // valeur dans le document par le serveur. Ni l'un ni l'autre ne se justifie
  // tant que le web de dev n'a pas d'utilisateurs.
  environment: process.env.NEXT_PUBLIC_SENTRY_ENV || process.env.NODE_ENV,
  tracesSampleRate: 0.1,
  sendDefaultPii: false,
  replaysSessionSampleRate: 0,
  replaysOnErrorSampleRate: 0,
});
