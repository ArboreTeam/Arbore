// Route de santé dédiée au healthcheck Docker (#469).
//
// Avant, le healthcheck visait `/`. Mesuré côté Sentry sur 7 jours : `GET /`
// représentait 21 880 spans sur 22 060 — 99,2 % du volume tracé — quand toutes
// les vraies pages réunies en totalisaient 180. Le tracing ne décrivait donc
// pas l'usage du site, mais la sonde qui le surveille.
//
// Le coût n'était PAS celui du rendu : `/` est prérendu statique, le
// healthcheck ne faisait que servir un fichier. C'est le bruit dans Sentry qui
// pose problème, pas le calcul.
//
// Pourquoi une route dédiée plutôt qu'un simple filtre : `/` est aussi la vraie
// page d'accueil. Filtrer `GET /` aurait rendu invisible le trafic qu'on veut
// justement voir. Séparer les deux chemins est ce qui permet de taire l'un sans
// taire l'autre.
//
// `force-dynamic` est nécessaire : sans lui, Next.js prérendrait cette réponse
// au build et la servirait en statique. Le healthcheck ne prouverait alors plus
// que le processus répond — il ne testerait que la capacité à servir un
// fichier, ce qui est précisément ce qu'un healthcheck ne doit pas faire.
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export function GET() {
  return NextResponse.json({ status: 'ok', service: 'arbore-web' });
}
